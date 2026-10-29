import AppKit
import OneLineCore
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct CapturePanelView: View {
    @ObservedObject var model: CaptureViewModel
    @ObservedObject var settings: SettingsStore
    let onClose: () -> Void
    let onOpenPrivacy: (PrivacyTarget) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            editor
                .padding(.horizontal, 16)
                .padding(.top, 2)
            preview
                .padding(.horizontal, 16)
                .padding(.top, 10)
            syntaxHint
                .padding(.horizontal, 16)
                .padding(.top, 10)
            footer
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
        .frame(width: 460, height: 312, alignment: .top)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                isFocused = true
            }
        }
        .onChange(of: model.focusToken) { _, _ in
            isFocused = true
        }
        .onExitCommand(perform: onClose)
    }

    private var panelBackground: some View {
        ZStack {
            VisualEffectView(material: .popover)
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.07),
                    Color.clear,
                    Color.primary.opacity(0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.20, green: 0.47, blue: 0.98),
                                Color(red: 0.52, green: 0.30, blue: 0.93)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                HStack(spacing: 2) {
                    Capsule(style: .continuous)
                        .frame(width: 12, height: 3)
                    Capsule(style: .continuous)
                        .frame(width: 2, height: 9)
                }
                .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)
            .shadow(color: Color.black.opacity(0.12), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text("一行")
                    .font(.system(size: 15, weight: .semibold))
                Text("日历 · 待办 · 备忘录")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if settings.hotKeyPreset.isEnabled {
                Text(settings.hotKeyPreset.title)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.055))
                    )
            }

            headerButton(systemName: "gearshape", help: "设置") {
                model.openSettings()
            }
            headerButton(systemName: "xmark", help: "关闭") {
                onClose()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func headerButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - 输入区

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if model.text.isEmpty {
                Text(placeholderText)
                    .font(.system(size: 14.5))
                    .foregroundStyle(.tertiary)
                    .lineSpacing(3)
                    .padding(.top, 7)
                    .padding(.leading, 6)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $model.text)
                .font(.system(size: 14.5))
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, -4)
                .padding(.vertical, -3)
                .focused($isFocused)
        }
        .frame(height: 78, alignment: .topLeading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isFocused ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.09),
                    lineWidth: isFocused ? 1.4 : 1
                )
        )
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    // MARK: - 预览

    private var preview: some View {
        Group {
            switch model.preview {
            case .empty:
                emptyPreview
            case .invalid(let message):
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
            case .ready(let capture):
                readyPreview(capture)
            }
        }
        .frame(height: 62, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placeholderText: String {
        switch settings.defaultKind {
        case .event:
            return "c 产品评审 明天 14:00-15:00 @工作"
        case .reminder:
            return "r 买牛奶 明天 18:00 @购物"
        case .note:
            return "n 读书笔记\n第一行标题，换行写正文"
        }
    }

    private var emptyPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            if settings.defaultKind == .note {
                hintLine(icon: "text.alignleft", text: "第一行是标题，换行继续写正文")
                hintLine(icon: "note.text", text: "备忘内容原样保存，不解析日期、标签和清单")
            } else {
                hintLine(icon: "text.append", text: "时间写在末尾，例如「明天 14:00」「下周一 10点」「每周五」")
                hintLine(icon: "at", text: "用 @日历 或 @清单 指定位置，用 #标签 补充标记")
            }
        }
    }

    private func hintLine(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9.5))
                .frame(width: 11)
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.tertiary)
    }

    private func readyPreview(_ capture: ParsedCapture) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                HStack(spacing: 4) {
                    Image(systemName: CaptureFormatting.icon(capture.kind))
                        .font(.system(size: 9, weight: .semibold))
                    Text(CaptureFormatting.kindName(capture.kind))
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(CaptureFormatting.color(capture.kind))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(CaptureFormatting.color(capture.kind).opacity(0.12))
                )

                Text(capture.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let priority = CaptureFormatting.priorityLabel(capture.priority) {
                    Text(priority)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 7) {
                Image(systemName: capture.kind == .reminder ? "clock" : (capture.kind == .note ? "note.text" : "calendar.badge.clock"))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                Text(noteLocationLine(for: capture))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let list = capture.listHint, !list.isEmpty {
                    Text("· @\(list)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !capture.tags.isEmpty {
                    Text("· " + capture.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            if let warning = capture.warnings.first {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 8.5))
                    Text(warning)
                        .lineLimit(1)
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.orange)
            }
        }
    }

    private func noteLocationLine(for capture: ParsedCapture) -> String {
        guard capture.kind == .note else {
            return CaptureFormatting.timingLine(
                kind: capture.kind,
                timing: capture.timing,
                recurrence: capture.recurrence
            )
        }
        let folder = settings.notesFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        if folder.isEmpty {
            return "保存到备忘录 · 默认文件夹"
        }
        return "保存到备忘录 · \(folder)"
    }

    // MARK: - 语法提示

    private var syntaxHint: some View {
        HStack(spacing: 10) {
            hintItem("c", "日程")
            hintItem("r", "待办")
            hintItem("n", "备忘")
            hintItem("#", "标签")
            hintItem("@", "清单")
            hintItem("!!", "优先级")
            Spacer(minLength: 0)
            Text("无前缀写入\(CaptureFormatting.kindName(settings.defaultKind))")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
    }

    private func hintItem(_ token: String, _ name: String) -> some View {
        HStack(spacing: 3) {
            Text(token)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(name)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 底部

    private var footer: some View {
        HStack(alignment: .center, spacing: 10) {
            statusView
            Spacer(minLength: 6)
            saveButton
        }
        .frame(minHeight: 34)
    }

    @ViewBuilder
    private var statusView: some View {
        if let feedback = model.feedback {
            switch feedback {
            case .success(let message, let detail):
                VStack(alignment: .leading, spacing: 2) {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            case .failure(let message, let hint, let privacyTarget):
                VStack(alignment: .leading, spacing: 2) {
                    Label(message, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                    if let hint {
                        HStack(spacing: 5) {
                            Text(hint)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if let privacyTarget {
                                Button("去设置") {
                                    onOpenPrivacy(privacyTarget)
                                }
                                .buttonStyle(.link)
                                .font(.system(size: 9.5))
                            }
                        }
                    }
                }
            }
        } else {
            Text("⌘↩ 保存 · 回车换行 · esc 关闭")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private var saveButton: some View {
        Button {
            Task { await model.submit() }
        } label: {
            HStack(spacing: 5) {
                if model.isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: "arrow.turn.down.left")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                Text(model.isSaving ? "写入中" : "保存")
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(minWidth: 58)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .tint(Color.accentColor)
        .disabled(!model.canSubmit)
        .keyboardShortcut(.return, modifiers: [.command])
    }
}
