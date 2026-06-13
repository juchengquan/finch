import Foundation

/// Phase 4 — a lightweight projection of a `rules` row for the rules-manager
/// list (name / priority / active). The full condition + actions live in the
/// engine's `Rule` type; the manager edits via create/delete + the isActive
/// toggle, so it doesn't need the parsed blobs here.
public struct RuleSummary: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let priority: Int
    public let isActive: Bool
    public init(id: String, name: String, priority: Int, isActive: Bool) {
        self.id = id; self.name = name; self.priority = priority; self.isActive = isActive
    }
}
