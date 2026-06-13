import Foundation

/// A category. `parentId` drives recursive budget matching (a budget scoped to a
/// parent category also matches its descendants). `kind` is "expense" | "income"
/// | "equity" | … — the projection excludes equity legs (opening balances).
/// Named `CategoryRow` (not `Category`) for consistency with `AccountRow`/
/// `BudgetRow` and to avoid an ambiguity with an SDK `Category` type.
public struct CategoryRow: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let ledgerId: String
    public let name: String
    public let parentId: String?
    public let kind: String?

    public init(id: String, ledgerId: String, name: String, parentId: String?, kind: String?) {
        self.id = id; self.ledgerId = ledgerId; self.name = name; self.parentId = parentId; self.kind = kind
    }
}
