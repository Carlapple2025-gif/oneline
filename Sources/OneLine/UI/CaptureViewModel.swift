import Combine
import Foundation
import OneLineCore

enum CapturePreview {
    case empty
    case invalid(String)
    case ready(ParsedCapture)
}

enum CaptureFeedback {
    case success(message: String, detail: String?)
    case failure(message: String, hint: String?, privacyTarget: PrivacyTarget?)
}

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            feedback = nil
            refreshPreview()
        }
    }

    @Published private(set) var preview: CapturePreview = .empty
    @Published private(set) var feedback: CaptureFeedback?
    @Published private(set) var isSaving = false
    @Published private(set) var focusToken = 0

    let settings: SettingsStore
    private let service: CaptureService
    private let history: HistoryStore

    var onOpenPrivacy: ((PrivacyTarget) -> Void)?
    var onOpenSettings: (() -> Void)?

    init(settings: SettingsStore, service: CaptureService, history: HistoryStore) {
        self.settings = settings
        self.service = service
        self.history = history
        refreshPreview()
    }

    var recentEntries: [HistoryEntry] {
        Array(history.entries.prefix(3))
    }

    var canSubmit: Bool {
        if isSaving { return false }
        if case .ready = preview { return true }
        return false
    }

    func refreshPreview() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            preview = .empty
            return
        }

        let parser = CaptureParser()
        switch parser.parse(text, defaultKind: settings.defaultKind) {
        case .success(let capture):
            preview = .ready(capture)
        case .failure(let error):
            preview = .invalid(error.localizedDescription)
        }
    }

    func submit() async {
        guard case .ready(let capture) = preview, !isSaving else { return }
        let rawInput = text
        isSaving = true
        feedback = nil

        do {
            let receipt = try await service.capture(capture, defaults: settings.captureDefaults)
            history.recordSuccess(rawInput: rawInput, receipt: receipt)
            if text == rawInput {
                text = ""
                focusToken += 1
            }
            feedback = .success(message: successMessage(for: receipt), detail: successDetail(for: receipt))
        } catch {
            let writeError = error as? CaptureWriteError
            let message = writeError?.errorDescription ?? error.localizedDescription
            let hint = writeError?.failureReason
            feedback = .failure(
                message: message,
                hint: hint,
                privacyTarget: writeError?.privacyTarget
            )
        }

        isSaving = false
        refreshPreview()
    }

    func fill(with rawInput: String) {
        text = rawInput
        focusToken += 1
    }

    func clearFeedback() {
        feedback = nil
    }

    func requestFocus() {
        focusToken += 1
    }

    /// 仅用于离屏预览截图，不参与正常业务流程。
    func setFeedbackForPreview(_ feedback: CaptureFeedback) {
        self.feedback = feedback
    }

    func openSettings() {
        onOpenSettings?()
    }

    private func successMessage(for receipt: CaptureReceipt) -> String {
        switch receipt.kind {
        case .event:
            return "已加入日历「\(receipt.destination)」"
        case .reminder:
            return "已加入清单「\(receipt.destination)」"
        case .note:
            return "已保存到「\(receipt.destination)」"
        }
    }

    private func successDetail(for receipt: CaptureReceipt) -> String? {
        var parts: [String] = []
        if let timing = receipt.timing {
            parts.append(
                CaptureFormatting.timingLine(
                    kind: receipt.kind,
                    timing: timing,
                    recurrence: receipt.recurrence
                )
            )
        }
        if !receipt.warnings.isEmpty {
            parts.append(receipt.warnings.joined(separator: "；"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
