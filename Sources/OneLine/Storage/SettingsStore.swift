import Combine
import Foundation
import OneLineCore

@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let defaultKind = "oneline.defaultKind"
        static let defaultCalendarID = "oneline.defaultCalendarID"
        static let defaultReminderListID = "oneline.defaultReminderListID"
        static let notesFolder = "oneline.notesFolder"
        static let hotKeyPreset = "oneline.hotKeyPreset"
    }

    private let defaults: UserDefaults

    @Published var defaultKind: CaptureKind {
        didSet { defaults.set(defaultKind.rawValue, forKey: Key.defaultKind) }
    }

    @Published var defaultCalendarID: String {
        didSet { defaults.set(defaultCalendarID, forKey: Key.defaultCalendarID) }
    }

    @Published var defaultReminderListID: String {
        didSet { defaults.set(defaultReminderListID, forKey: Key.defaultReminderListID) }
    }

    @Published var notesFolder: String {
        didSet { defaults.set(notesFolder, forKey: Key.notesFolder) }
    }

    @Published var hotKeyPreset: HotKeyPreset {
        didSet {
            defaults.set(hotKeyPreset.rawValue, forKey: Key.hotKeyPreset)
            NotificationCenter.default.post(name: .oneLineHotKeyChanged, object: nil)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultKind = CaptureKind(rawValue: defaults.string(forKey: Key.defaultKind) ?? "") ?? .reminder
        defaultCalendarID = defaults.string(forKey: Key.defaultCalendarID) ?? ""
        defaultReminderListID = defaults.string(forKey: Key.defaultReminderListID) ?? ""
        notesFolder = defaults.string(forKey: Key.notesFolder) ?? ""
        hotKeyPreset = HotKeyPreset(rawValue: defaults.string(forKey: Key.hotKeyPreset) ?? "") ?? .controlOptionSpace
    }

    var captureDefaults: CaptureDefaults {
        CaptureDefaults(
            calendarID: defaultCalendarID.isEmpty ? nil : defaultCalendarID,
            reminderListID: defaultReminderListID.isEmpty ? nil : defaultReminderListID,
            notesFolder: notesFolder.isEmpty ? nil : notesFolder
        )
    }
}
