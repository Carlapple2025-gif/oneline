import AppKit
import Combine
import EventKit
import OneLineCore
import SwiftUI

private struct CalendarOption: Identifiable, Hashable {
    let id: String
    let title: String
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permissions: PermissionCenter
    @ObservedObject var loginItem: LoginItemManager

    @State private var calendars: [CalendarOption] = []
    @State private var reminderLists: [CalendarOption] = []

    private var appPathHint: String? {
        if Bundle.main.bundlePath.hasPrefix("/Applications/") {
            return nil
        }
        return "把「一行」移到「应用程序」文件夹后再开启，登录项会更稳定。"
    }

    var body: some View {
        Form {
            Section {
                Picker("无前缀时写入", selection: $settings.defaultKind) {
                    Text("待办").tag(CaptureKind.reminder)
                    Text("日程").tag(CaptureKind.event)
                    Text("备忘录").tag(CaptureKind.note)
                }

                Picker("默认日历", selection: $settings.defaultCalendarID) {
                    Text("系统默认").tag("")
                    ForEach(calendars) { calendar in
                        Text(calendar.title).tag(calendar.id)
                    }
                }

                Picker("默认提醒清单", selection: $settings.defaultReminderListID) {
                    Text("系统默认").tag("")
                    ForEach(reminderLists) { list in
                        Text(list.title).tag(list.id)
                    }
                }

                TextField(
                    "备忘录文件夹",
                    text: $settings.notesFolder,
                    prompt: Text("留空使用默认文件夹")
                )
            } header: {
                Text("写入位置")
            } footer: {
                Text("前缀 c / r / n 会覆盖这里的默认值。@名称 可临时指定日历或清单。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("全局快捷键", selection: $settings.hotKeyPreset) {
                    ForEach(HotKeyPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }

                Toggle(
                    "登录时自动启动",
                    isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { loginItem.setEnabled($0) }
                    )
                )

                if let hint = appPathHint {
                    Text(hint)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                if loginItem.needsApproval {
                    Text("需要在系统设置 › 通用 › 登录项 中允许「一行」。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                }
                if let error = loginItem.errorMessage {
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                }
            } header: {
                Text("入口")
            }

            Section {
                permissionRow(
                    title: "日历",
                    icon: "calendar",
                    state: permissions.events,
                    grantedDetail: "可以读取日历并写入日程",
                    request: { requestAccess(.event) },
                    openSettings: { permissions.openPrivacySettings(.calendars) }
                )

                permissionRow(
                    title: "提醒事项",
                    icon: "checkmark.circle",
                    state: permissions.reminders,
                    grantedDetail: "可以读取清单并写入待办",
                    request: { requestAccess(.reminder) },
                    openSettings: { permissions.openPrivacySettings(.reminders) }
                )

                HStack(spacing: 10) {
                    Image(systemName: "note.text")
                        .frame(width: 20)
                        .foregroundStyle(CaptureFormatting.color(.note))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("备忘录")
                            .font(.system(size: 12, weight: .medium))
                        Text("首次保存时系统会询问自动化权限")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("自动化设置") {
                        permissions.openPrivacySettings(.automation)
                    }
                    .controlSize(.small)
                }
            } header: {
                HStack {
                    Text("权限")
                    Spacer()
                    Button("刷新") {
                        permissions.refresh()
                        reloadDestinations()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 10.5))
                }
            } footer: {
                Text("一行不联网，所有内容通过 macOS 官方接口直接写入本机 App。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 620)
        .onAppear {
            permissions.refresh()
            loginItem.refresh()
            reloadDestinations()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
            loginItem.refresh()
            reloadDestinations()
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        icon: String,
        state: EventAccessState,
        grantedDetail: String,
        request: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(state.isGranted ? Color.green : Color.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(state.isGranted ? grantedDetail : stateDescription(state))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(state.label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(stateColor(state))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(stateColor(state).opacity(0.10))
                )

            if state == .notDetermined {
                Button("授权", action: request)
                    .controlSize(.small)
            } else if !state.isGranted {
                Button("系统设置", action: openSettings)
                    .controlSize(.small)
            }
        }
    }

    private func stateDescription(_ state: EventAccessState) -> String {
        switch state {
        case .notDetermined: return "尚未授权"
        case .granted: return ""
        case .writeOnly: return "只能写入，无法读取日历列表"
        case .denied: return "权限已被拒绝"
        case .restricted: return "受系统限制"
        }
    }

    private func stateColor(_ state: EventAccessState) -> Color {
        switch state {
        case .granted: return .green
        case .notDetermined: return .secondary
        case .writeOnly: return .orange
        case .denied, .restricted: return .red
        }
    }

    private func requestAccess(_ kind: CaptureKind) {
        Task {
            await permissions.requestAccess(for: kind)
            reloadDestinations()
        }
    }

    private func reloadDestinations() {
        if permissions.events.isGranted {
            calendars = permissions.eventKit.eventCalendars.map {
                CalendarOption(id: $0.calendarIdentifier, title: $0.title)
            }
        } else {
            calendars = []
        }

        if permissions.reminders.isGranted {
            reminderLists = permissions.eventKit.reminderLists.map {
                CalendarOption(id: $0.calendarIdentifier, title: $0.title)
            }
        } else {
            reminderLists = []
        }

        if permissions.events.isGranted,
           !settings.defaultCalendarID.isEmpty,
           !calendars.contains(where: { $0.id == settings.defaultCalendarID }) {
            settings.defaultCalendarID = ""
        }
        if permissions.reminders.isGranted,
           !settings.defaultReminderListID.isEmpty,
           !reminderLists.contains(where: { $0.id == settings.defaultReminderListID }) {
            settings.defaultReminderListID = ""
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let rootView: SettingsView

    init(settings: SettingsStore, permissions: PermissionCenter, loginItem: LoginItemManager) {
        rootView = SettingsView(
            settings: settings,
            permissions: permissions,
            loginItem: loginItem
        )
        super.init()
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "一行设置"
        window.delegate = self
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.hide(nil)
    }
}
