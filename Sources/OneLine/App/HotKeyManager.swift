import Carbon.HIToolbox
import Foundation

extension Notification.Name {
    static let oneLineHotKeyPressed = Notification.Name("oneLineHotKeyPressed")
    static let oneLineHotKeyChanged = Notification.Name("oneLineHotKeyChanged")
}

enum HotKeyPreset: String, CaseIterable, Identifiable {
    case controlOptionSpace
    case controlCommandSpace
    case optionShiftSpace
    case controlShiftSpace
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .controlOptionSpace: return "⌃⌥ Space"
        case .controlCommandSpace: return "⌃⌘ Space"
        case .optionShiftSpace: return "⌥⇧ Space"
        case .controlShiftSpace: return "⌃⇧ Space"
        case .disabled: return "关闭"
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .controlOptionSpace: return UInt32(controlKey | optionKey)
        case .controlCommandSpace: return UInt32(controlKey | cmdKey)
        case .optionShiftSpace: return UInt32(optionKey | shiftKey)
        case .controlShiftSpace: return UInt32(controlKey | shiftKey)
        case .disabled: return 0
        }
    }

    var isEnabled: Bool { self != .disabled }
}

@MainActor
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var currentPreset: HotKeyPreset = .disabled

    private static let signature: OSType = 0x4F4C4E45 // 'OLNE'
    private static let hotKeyID: UInt32 = 1

    init() {
        installHandler()
    }

    deinit {
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func apply(_ preset: HotKeyPreset) {
        guard preset != currentPreset else { return }
        unregister()
        currentPreset = preset

        guard preset.isEnabled else { return }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        let status = RegisterEventHotKey(
            UInt32(kVK_Space),
            preset.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr {
            hotKeyRef = ref
        } else {
            NSLog("OneLine: 注册全局快捷键失败（status \(status)）")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handler: EventHandlerUPP = { _, event, _ in
            guard let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == 0x4F4C4E45 else { return noErr }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .oneLineHotKeyPressed, object: nil)
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &eventHandler
        )
    }
}
