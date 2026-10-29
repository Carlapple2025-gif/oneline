import Combine
import Foundation
import OneLineCore

struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let rawInput: String
    let kind: CaptureKind
    let title: String
    let destination: String
    let createdAt: Date
}

@MainActor
final class HistoryStore: ObservableObject {
    private static let key = "oneline.history"
    private static let limit = 20

    @Published private(set) var entries: [HistoryEntry] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func recordSuccess(rawInput: String, receipt: CaptureReceipt) {
        let entry = HistoryEntry(
            id: UUID(),
            rawInput: rawInput,
            kind: receipt.kind,
            title: receipt.title,
            destination: receipt.destination,
            createdAt: Date()
        )
        entries.insert(entry, at: 0)
        if entries.count > Self.limit {
            entries = Array(entries.prefix(Self.limit))
        }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else {
            entries = []
            return
        }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
