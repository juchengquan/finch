import Foundation

/// Phase 4 — a projection of a `rules` row for the rules-manager list
/// (name / priority / active) plus the raw `condition`/`actions` JSON and
/// `runOnEdit`, so the manager can edit a rule (parsed via `RuleParse`) and
/// show its match count — not just toggle it.
public struct RuleSummary: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let priority: Int
    public let isActive: Bool
    public let conditionJSON: String
    public let actionsJSON: String
    public let runOnEdit: Bool
    public init(id: String, name: String, priority: Int, isActive: Bool,
                conditionJSON: String = "", actionsJSON: String = "[]", runOnEdit: Bool = false) {
        self.id = id; self.name = name; self.priority = priority; self.isActive = isActive
        self.conditionJSON = conditionJSON; self.actionsJSON = actionsJSON; self.runOnEdit = runOnEdit
    }
}
