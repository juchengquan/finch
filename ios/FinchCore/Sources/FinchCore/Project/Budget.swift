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
    /// Time-of-day the cycle turns over, "HH:mm". Nil = midnight — the behaviour
    /// every budget had before cycles could carry a time.
    public let startTime: String?
    public let endDate: String?
    public let endTime: String?
    public let isRecurring: Int
    public let rollover: Int
    public let rolloverLimit: Double?
    public let pendingAmount: Double?
    public let lastRolledPeriod: String?
    public let accountIds: [String]
    public let categoryIds: [String]
    public let tagIds: [String]            // extra match dimension (OR-within, AND-across); [] = unconstrained
    public let counterpartyIds: [String]   // ditto — matches by merchant id
    public let warningPct: Double       // default 80 on the web

    public init(
        id: String, ledgerId: String, groupId: String?, name: String, type: String,
        amount: Double, saved: Double, carryForward: Double, frequency: String,
        startDate: String, startTime: String? = nil, endDate: String?, endTime: String? = nil,
        isRecurring: Int, rollover: Int,
        rolloverLimit: Double?, pendingAmount: Double?, lastRolledPeriod: String?,
        accountIds: [String], categoryIds: [String],
        tagIds: [String] = [], counterpartyIds: [String] = [], warningPct: Double
    ) {
        self.id = id; self.ledgerId = ledgerId; self.groupId = groupId; self.name = name
        self.type = type; self.amount = amount; self.saved = saved
        self.carryForward = carryForward; self.frequency = frequency
        self.startDate = startDate; self.startTime = startTime
        self.endDate = endDate; self.endTime = endTime; self.isRecurring = isRecurring
        self.rollover = rollover; self.rolloverLimit = rolloverLimit
        self.pendingAmount = pendingAmount; self.lastRolledPeriod = lastRolledPeriod
        self.accountIds = accountIds; self.categoryIds = categoryIds
        self.tagIds = tagIds; self.counterpartyIds = counterpartyIds; self.warningPct = warningPct
    }

    // Hand-rolled decode so the new `tagIds`/`counterpartyIds` (and the array/
    // warningPct dims) default when a key is absent — the older selector parity
    // fixtures (pre-tag/merchant) omit them. `encode(to:)`/`CodingKeys` stay
    // synthesized. Mirrors the web `BudgetRow`'s `?? []` / `?? 80` fallbacks.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        ledgerId = try c.decode(String.self, forKey: .ledgerId)
        groupId = try c.decodeIfPresent(String.self, forKey: .groupId)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(String.self, forKey: .type)
        amount = try c.decode(Double.self, forKey: .amount)
        saved = try c.decodeIfPresent(Double.self, forKey: .saved) ?? 0
        carryForward = try c.decodeIfPresent(Double.self, forKey: .carryForward) ?? 0
        frequency = try c.decode(String.self, forKey: .frequency)
        startDate = try c.decode(String.self, forKey: .startDate)
        // Absent in every fixture written before cycles could carry a time — nil
        // means midnight, i.e. unchanged behaviour.
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime)
        endDate = try c.decodeIfPresent(String.self, forKey: .endDate)
        endTime = try c.decodeIfPresent(String.self, forKey: .endTime)
        isRecurring = try c.decodeIfPresent(Int.self, forKey: .isRecurring) ?? 1
        rollover = try c.decodeIfPresent(Int.self, forKey: .rollover) ?? 0
        rolloverLimit = try c.decodeIfPresent(Double.self, forKey: .rolloverLimit)
        pendingAmount = try c.decodeIfPresent(Double.self, forKey: .pendingAmount)
        lastRolledPeriod = try c.decodeIfPresent(String.self, forKey: .lastRolledPeriod)
        accountIds = try c.decodeIfPresent([String].self, forKey: .accountIds) ?? []
        categoryIds = try c.decodeIfPresent([String].self, forKey: .categoryIds) ?? []
        tagIds = try c.decodeIfPresent([String].self, forKey: .tagIds) ?? []
        counterpartyIds = try c.decodeIfPresent([String].self, forKey: .counterpartyIds) ?? []
        warningPct = try c.decodeIfPresent(Double.self, forKey: .warningPct) ?? 80
    }
}
