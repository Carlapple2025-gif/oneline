import AppKit
import SwiftUI

@MainActor
final class CapturePanelController: NSObject {
    private var panel: CapturePanel?
    private let model: CaptureViewModel
    private let settings: SettingsStore
    private var keyMonitor: Any?

    var onOpenSettings: (() -> Void)?
    var onOpenPrivacy: ((PrivacyTarget) -> Void)?

    init(model: CaptureViewModel, settings: SettingsStore) {
        self.model = model
        self.settings = settings
        super.init()
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func toggle(relativeTo button: NSStatusBarButton?) {
        if isVisible {
            hide()
        } else {
            show(relativeTo: button)
        }
    }

    func show(relativeTo button: NSStatusBarButton?) {
        let panel = ensurePanel()
        model.clearFeedback()
        model.refreshPreview()

        if let button {
            position(panel: panel, below: button)
        } else {
            positionCentered(panel: panel)
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        model.requestFocus()
    }

    func show(prefill: String, relativeTo button: NSStatusBarButton?) {
        model.fill(with: prefill)
        show(relativeTo: button)
    }

    func hide() {
        guard let panel else { return }
        panel.orderOut(nil)
        removeKeyMonitor()
        model.clearFeedback()

        // 快速面板关闭后把焦点还给上一个 App；设置窗口打开时不要隐藏整个 App。
        let hasOtherMainWindow = NSApp.windows.contains {
            $0 !== panel && $0.isVisible && $0.canBecomeMain
        }
        if !hasOtherMainWindow {
            NSApp.hide(nil)
        }
    }

    private func ensurePanel() -> CapturePanel {
        if let panel { return panel }

        let rootView = CapturePanelView(
            model: model,
            settings: settings,
            onClose: { [weak self] in self?.hide() },
            onOpenPrivacy: { [weak self] target in
                self?.hide()
                self?.onOpenPrivacy?(target)
            }
        )

        let hostingView = NSHostingView(rootView: rootView)
        let panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 312),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.isMovableByWindowBackground = false
        panel.title = "一行"
        panel.delegate = self

        model.onOpenSettings = { [weak self] in
            self?.hide()
            self?.onOpenSettings?()
        }

        self.panel = panel
        return panel
    }

    private func position(panel: NSPanel, below button: NSStatusBarButton) {
        guard let buttonWindow = button.window else {
            positionCentered(panel: panel)
            return
        }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = panel.frame.size

        var x = buttonRect.maxX - size.width
        var y = buttonRect.minY - size.height - 6
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        if y < visible.minY + 8 {
            y = visible.minY + 8
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func positionCentered(panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - 72
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible, panel.isKeyWindow else { return event }

            if event.keyCode == 53 { // esc
                self.hide()
                return nil
            }

            if (event.keyCode == 36 || event.keyCode == 76), // return / enter
               event.modifierFlags.contains(.command) {
                Task { @MainActor in
                    await self.model.submit()
                }
                return nil
            }

            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

extension CapturePanelController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        installKeyMonitor()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !model.isSaving else { return }
        // 点击其他窗口时收起，避免面板一直悬在最上层。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible, !panel.isKeyWindow, !self.model.isSaving else { return }
            self.hide()
        }
    }
}

final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
