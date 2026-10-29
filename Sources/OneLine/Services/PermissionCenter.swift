import AppKit
import Combine
import Foundation
import OneLineCore

@MainActor
final class PermissionCenter: ObservableObject {
    @Published private(set) var events: EventAccessState = .notDetermined
    @Published private(set) var reminders: EventAccessState = .notDetermined

    let eventKit: EventKitService

    init(eventKit: EventKitService) {
        self.eventKit = eventKit
        refresh()
    }

    func refresh() {
        events = eventKit.accessState(for: .event)
        reminders = eventKit.accessState(for: .reminder)
    }

    func state(for kind: CaptureKind) -> EventAccessState {
        switch kind {
        case .event: return events
        case .reminder: return reminders
        case .note: return .granted
        }
    }

    /// 返回是否拥有完整权限；未决定时会弹出系统授权框。
    @discardableResult
    func requestAccess(for kind: CaptureKind) async -> Bool {
        guard kind != .note else { return true }
        let current = state(for: kind)
        if current.isGranted { return true }
        guard current == .notDetermined else {
            refresh()
            return false
        }

        let granted = await eventKit.requestFullAccess(for: kind)
        refresh()
        return granted
    }

    func openPrivacySettings(_ target: PrivacyTarget) {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?\(target.settingsAnchor)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
