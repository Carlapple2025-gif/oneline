import Carbon.HIToolbox
import EventKit
import Foundation

enum SelfCheck {
    static func run() -> Int32 {
        print("OneLine self-check")
        print("bundle: \(Bundle.main.bundlePath)")
        print("identifier: \(Bundle.main.bundleIdentifier ?? "nil")")

        let requiredKeys = [
            "NSCalendarsFullAccessUsageDescription",
            "NSRemindersFullAccessUsageDescription",
            "NSAppleEventsUsageDescription",
            "LSUIElement"
        ]
        var ok = true
        for key in requiredKeys {
            let value = Bundle.main.object(forInfoDictionaryKey: key)
            print("Info.plist \(key): \(value == nil ? "MISSING" : "ok")")
            if value == nil { ok = false }
        }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            EventHotKeyID(signature: 0x53454C46, id: 9),
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        print("hotkey ⌃⌥Space: \(hotKeyStatus == noErr ? "available" : "in use (\(hotKeyStatus))")")

        print("event access: \(EKEventStore.authorizationStatus(for: .event).rawValue)")
        print("reminder access: \(EKEventStore.authorizationStatus(for: .reminder).rawValue)")
        print("bundle identifier present: \(Bundle.main.bundleIdentifier != nil)")
        print(ok ? "RESULT: OK" : "RESULT: FAILED")
        return ok ? 0 : 1
    }
}
