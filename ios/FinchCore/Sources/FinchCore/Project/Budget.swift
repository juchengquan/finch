import Foundation

/// `BudgetRow` — mirror of `lib/db/domain/budgets/types.ts:8`. This is the type
/// `Selectors.budgetProgress` consumes (NOT a separate `Budget` with a
/// `.spent`/`.currency`); the "spent/limit" the Budgets tab shows comes from
/// `Selectors.budgetProgress(...).used/.base`. All amounts are in the ledger base.
///
/// Field names are camelCase to match the web `BudgetRow` JSON verbatim — the
/// selector parity fixtures (`budgetOf` in `select.fixtures.ts`) decode straight
/// into this. Optional fields (`String?`/`Double?`) tolerate either a present
/// `null` or an absent key.
public struct BudgetRow: Identifiable, Equatable, Hashable, Sendable, Codable {
    public let id: String
    public let ledgerId: String
    public let groupId: String?
    public let name: String
    public let type: String            // BudgetType
    public let amount: Double
    public let saved: Double
    public let carryForward: Double
    public let frequency: String
    public let startDate: String
    public let endDate: String?
    public let isRecurring: Int
    public let rollover: Int
    public let rolloverLimit: Double?
    public let pendingAmount: Double?
    public let lastRolledPeriod: String?
    public let accountIds: [String]
    public let categoryIds: [String]
    public let warningPct: Double       // default 80 on the web

    public init(
        id: String, ledgerId: String, groupId: String?, name: String, type: String,
        amount: Double, saved: Double, carryForward: Double, frequency: String,
        startDate: String, endDate: String?, isRecurring: Int, rollover: Int,
        rolloverLimit: Double?, pendingAmount: Double?, lastRolledPeriod: String?,
        accountIds: [String], categoryIds: [String], warningPct: Double
    ) {
        self.id = id; self.ledgerId = ledgerId; self.groupId = groupId; self.name = name
        self.type = type; self.amount = amount; self.saved = saved
        self.carryForward = carryForward; self.frequency = frequency
        self.startDate = startDate; self.endDate = endDate; self.isRecurring = isRecurring
        self.rollover = rollover; self.rolloverLimit = rolloverLimit
        self.pendingAmount = pendingAmount; self.lastRolledPeriod = lastRolledPeriod
        self.accountIds = accountIds; self.categoryIds = categoryIds; self.warningPct = warningPct
    }
}
