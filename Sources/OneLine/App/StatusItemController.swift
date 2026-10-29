import AppKit
import OneLineCore

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let settings: SettingsStore

    var onToggle: (() -> Void)?
    var onOpenRecent: ((String) -> Void)?
    var onSettings: (() -> Void)?
    var onAbout: (() -> Void)?
    var onQuit: (() -> Void)?
    var onClearRecent: (() -> Void)?
    var recentProvider: (() -> [HistoryEntry])?

    var statusButton: NSStatusBarButton? { statusItem.button }

    init(settings: SettingsStore) {
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        rebuildMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "一行")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = "一行 · 快速记录"
        button.target = self
        button.action = #selector(statusButtonClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusButtonClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            rebuildMenu()
            guard let button = statusItem.button else { return }
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: button.bounds.height + 4),
                in: button
            )
        } else {
            onToggle?()
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let quickItem = NSMenuItem(title: "快速记录…", action: #selector(quickCapture), keyEquivalent: "")
        quickItem.target = self
        if settings.hotKeyPreset.isEnabled {
            quickItem.title = "快速记录…    \(settings.hotKeyPreset.title)"
        }
        menu.addItem(quickItem)

        let recentItem = NSMenuItem(title: "最近记录", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu()
        let entries = recentProvider?().prefix(5) ?? []
        if entries.isEmpty {
            let empty = NSMenuItem(title: "暂无记录", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
        } else {
            for entry in entries {
                let displayTitle = entry.title.count > 26
                    ? String(entry.title.prefix(26)) + "…"
                    : entry.title
                let title = "\(displayTitle)  ·  \(entry.destination)"
                let item = NSMenuItem(title: title, action: #selector(openRecent(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.rawInput
                item.image = NSImage(systemSymbolName: EntryIcon.symbol(for: entry.kind), accessibilityDescription: nil)
                recentMenu.addItem(item)
            }
            recentMenu.addItem(.separator())
            let clearItem = NSMenuItem(title: "清空最近记录", action: #selector(clearRecent), keyEquivalent: "")
            clearItem.target = self
            recentMenu.addItem(clearItem)
        }
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "关于一行", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出一行", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func quickCapture() {
        onToggle?()
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let rawInput = sender.representedObject as? String else { return }
        onOpenRecent?(rawInput)
    }

    @objc private func openSettings() {
        onSettings?()
    }

    @objc private func clearRecent() {
        onClearRecent?()
    }

    @objc private func openAbout() {
        onAbout?()
    }

    @objc private func quit() {
        onQuit?()
    }
}

private enum EntryIcon {
    static func symbol(for kind: CaptureKind) -> String {
        switch kind {
        case .event: return "calendar"
        case .reminder: return "checkmark.circle"
        case .note: return "note.text"
        }
    }
}
