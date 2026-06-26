import Foundation

/// One saved Activity filter, scoped to a ledger.
struct SavedSearch: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    let ledgerId: String
    let filter: TxFilter
}

/// Per-ledger saved filter searches, persisted in UserDefaults (the iOS analogue
/// of the web's localStorage). Not part of the engine/DB.
final class SavedSearchStore: ObservableObject {
    @Published private(set) var searches: [SavedSearch] = []
    private let defaults: UserDefaults
    private let key = "finch.savedSearches"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let arr = try? JSONDecoder().decode([SavedSearch].self, from: data) {
            searches = arr
        }
    }

    func all(ledgerId: String) -> [SavedSearch] { searches.filter { $0.ledgerId == ledgerId } }

    func save(name: String, filter: TxFilter, ledgerId: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searches.append(SavedSearch(id: UUID().uuidString, name: trimmed, ledgerId: ledgerId, filter: filter))
        persist()
    }

    func remove(_ id: String) {
        searches.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(searches) { defaults.set(data, forKey: key) }
    }
}
