import AppKit
import OneLineCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: SettingsStore!
    private var eventKit: EventKitService!
    private var permissions: PermissionCenter!
    private var history: HistoryStore!
    private var captureModel: CaptureViewModel!
    private var panelController: CapturePanelController!
    private var statusController: StatusItemController!
    private var settingsWindowController: SettingsWindowController!
    private var hotKeyManager: HotKeyManager!
    private var loginItemManager: LoginItemManager!

    private var hotKeyObserver: NSObjectProtocol?
    private var hotKeyChangedObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = SettingsStore()
        eventKit = EventKitService()
        permissions = PermissionCenter(eventKit: eventKit)
        history = HistoryStore()
        loginItemManager = LoginItemManager()

        let notes = NotesService()
        let service = CaptureService(eventKit: eventKit, permissions: permissions, notes: notes)
        captureModel = CaptureViewModel(settings: settings, service: service, history: history)

        settingsWindowController = SettingsWindowController(
            settings: settings,
            permissions: permissions,
            loginItem: loginItemManager
        )
        panelController = CapturePanelController(model: captureModel, settings: settings)
        panelController.onOpenSettings = { [weak self] in self?.openSettings() }
        panelController.onOpenPrivacy = { [weak self] target in self?.openPrivacy(target) }

        statusController = StatusItemController(settings: settings)
        statusController.recentProvider = { [weak self] in self?.history.entries ?? [] }
        statusController.onToggle = { [weak self] in self?.toggleCapture() }
        statusController.onOpenRecent = { [weak self] rawInput in self?.openRecent(rawInput) }
        statusController.onSettings = { [weak self] in self?.openSettings() }
        statusController.onAbout = { [weak self] in self?.showAbout() }
        statusController.onClearRecent = { [weak self] in self?.history.clear() }
        statusController.onQuit = { NSApp.terminate(nil) }

        hotKeyManager = HotKeyManager()
        hotKeyManager.apply(settings.hotKeyPreset)

        if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.toggleCapture()
            }
        }
        if CommandLine.arguments.contains("--show-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.openSettings()
            }
        }
        if CommandLine.arguments.contains("--auto-hide") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                self?.panelController.hide()
            }
        }

        hotKeyObserver = NotificationCenter.default.addObserver(
            forName: .oneLineHotKeyPressed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.toggleCapture() }
        }

        hotKeyChangedObserver = NotificationCenter.default.addObserver(
            forName: .oneLineHotKeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.hotKeyManager.apply(self.settings.hotKeyPreset)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.unregister()
        if let hotKeyObserver {
            NotificationCenter.default.removeObserver(hotKeyObserver)
        }
        if let hotKeyChangedObserver {
            NotificationCenter.default.removeObserver(hotKeyChangedObserver)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        permissions?.refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func toggleCapture() {
        panelController?.toggle(relativeTo: statusController?.statusButton)
    }

    private func openRecent(_ rawInput: String) {
        panelController?.show(prefill: rawInput, relativeTo: statusController?.statusButton)
    }

    private func openSettings() {
        panelController.hide()
        settingsWindowController.show()
    }

    private func openPrivacy(_ target: PrivacyTarget) {
        permissions.openPrivacySettings(target)
    }

    private func showAbout() {
        let credits = NSMutableAttributedString(
            string: "一行，记入日历、待办与备忘录。\n使用 EventKit 与 AppleScript，数据只在本机处理。\n\n快捷键可在设置中修改。",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "一行",
            .applicationVersion: "1.0.0",
            .version: "1.0.0",
            .credits: credits
        ])
    }
}
