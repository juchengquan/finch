import Foundation

/// Phase 4 — named saved searches for the Activity tab. Device-local (a UI
/// convenience, not ledger data), so UserDefaults. The add/remove logic is pure
/// + unit-tested.
public struct SavedSearch: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var query: String
    public var id: String { name }
    public init(name: String, query: String) { self.name = name; self.query = query }
}

public enum SavedSearches {
    private static let key = "finch.savedSearches"

    public static func all() -> [SavedSearch] { decode(UserDefaults.standard.data(forKey: key)) }

    public static func save(name: String, query: String) {
        var list = all()
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        list.removeAll { $0.name == trimmed }                 // upsert by name
        list.append(SavedSearch(name: trimmed, query: query))
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: key)
    }

    public static func remove(name: String) {
        var list = all(); list.removeAll { $0.name == name }
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: key)
    }

    /// Pure helper (the tested core): apply an upsert to a list.
    public static func upsert(_ list: [SavedSearch], name: String, query: String) -> [SavedSearch] {
        var out = list.filter { $0.name != name }
        out.append(SavedSearch(name: name, query: query))
        return out
    }

    private static func decode(_ data: Data?) -> [SavedSearch] {
        guard let data, let list = try? JSONDecoder().decode([SavedSearch].self, from: data) else { return [] }
        return list
    }
}
