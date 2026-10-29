import AppKit
import SwiftUI

@MainActor
enum SnapshotRenderer {
    static func run(path: String, sample: String) -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--dark") {
            app.appearance = NSAppearance(named: .darkAqua)
        }

        let suiteName = "oneline.snapshot.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return 1 }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        let eventKit = EventKitService()
        let permissions = PermissionCenter(eventKit: eventKit)
        let history = HistoryStore(defaults: defaults)
        let loginItem = LoginItemManager()
        let service = CaptureService(eventKit: eventKit, permissions: permissions, notes: NotesService())
        let model = CaptureViewModel(settings: settings, service: service, history: history)

        let rootView: AnyView
        let size: NSSize

        if sample == "settings" {
            rootView = AnyView(
                SettingsView(
                    settings: settings,
                    permissions: permissions,
                    loginItem: loginItem
                )
            )
            size = NSSize(width: 520, height: 620)
        } else {
            switch sample {
            case "empty":
                model.text = ""
            case "reminder":
                model.text = "r 买牛奶 明天 18:00 @购物 !!"
            case "note":
                model.text = "n 读书笔记 #Swift\n并发章节：actor 与 Sendable"
            case "success":
                model.text = ""
                model.setFeedbackForPreview(.success(
                    message: "已加入日历「工作」",
                    detail: "明天 14:00–15:00 · 已写入「个人」"
                ))
            case "error":
                model.text = "c 产品评审 明天 14:00"
                model.setFeedbackForPreview(.failure(
                    message: "没有日历权限，无法写入日程",
                    hint: "请在系统设置 › 隐私与安全性中允许「一行」访问。",
                    privacyTarget: .calendars
                ))
            default:
                model.text = "c 产品评审 明天 14:00-15:00 @工作 #评审"
            }

            rootView = AnyView(
                CapturePanelView(
                    model: model,
                    settings: settings,
                    onClose: {},
                    onOpenPrivacy: { _ in }
                )
            )
            size = NSSize(width: 460, height: 312)
        }

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return 2 }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return 3 }

        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            NSLog("OneLine snapshot failed: \(error)")
            return 4
        }
        return 0
    }
}
