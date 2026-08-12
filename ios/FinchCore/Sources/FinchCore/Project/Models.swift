import Foundation

// The client-projected value types the selectors operate on. Field names are
// camelCase to match the web `Tx`/`AccountRow`/`BudgetRow` JSON verbatim (the
// parity fixtures decode straight into these). Extra JSON keys are ignored.

public struct Tx: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var merchant: String
    public var category: String?
    public var amount: Double
    public var account: String
    public var date: String
    public var pending: Bool?
    /// Which kind of pending: "upcoming" (dated after today) or "due". nil when the
    /// entry is confirmed. A CACHE of a date rule, refreshed by the store — anything
    /// that must be right THIS INSTANT should use `Selectors.pendingSplit`, which
    /// recomputes against the day it is given.
    public var pendingKind: String?
    public var ledgerId: String?
    public var currency: String?
    public var nativeAmount: Double?
    public var time: String?
    public var kind: String?
    public var transferGroupId: String?
    /// Number of account legs on this Tx's entry (>= 1). A split purchase has
    /// several — the projection already computes this for `transferGroupId`;
    /// exposed so callers (e.g. the delete-confirmation dialog) don't have to
    /// re-query it. See Projection.enrichLegTxs.
    public var accountLegCount: Int?
    /// The `entries.id` this posting belongs to — stamped on EVERY row, so
    /// grouping by it always reconstructs the purchase. `Tx.id` is the POSTING
    /// id, so a purchase paid from several accounts is several rows, and
    /// anything counting rows counts it more than once.
    ///
    /// Optional only because the parity fixtures decode `[Tx]` from JSON written
    /// before this field existed. NOTHING persists `Tx`, so there is no
    /// migration to write. Prefer `purchaseKey` over reading this directly.
    public var entryId: String?
    /// Links this row to the other transactions of one grid purchase — a purchase
    /// split by card AND by category, stored as one entry per card. NULL for
    /// everything else. Optional for the same reason as `entryId`: the parity
    /// fixtures decode `[Tx]` from JSON written before the field existed.
    public var groupId: String?
    public var counterpartyId: String?
    public var splits: [TxSplit]?
    public var tags: [String]?
    public var note: String?
    public var sourceTemplateId: String?
    /// The scheduled occurrence this posting fulfils (`entries.occurrence_date`).
    /// NULL on rows written before this column existed, and on any entry that
    /// isn't linked to a schedule — `Selectors.scheduledPostedMap` falls back
    /// to `date` in that case, so no backfill is required.
    public var occurrenceDate: String?
    public var refundedTransactionId: String?
    public var clearedAt: String?
    public var appliedRuleIds: [String]?
    public var reviewedAt: String?

    public init(id: String, merchant: String, category: String? = nil, amount: Double,
                account: String, date: String, pending: Bool? = nil, pendingKind: String? = nil,
                ledgerId: String? = nil,
                currency: String? = nil, nativeAmount: Double? = nil, time: String? = nil,
                kind: String? = nil, transferGroupId: String? = nil, accountLegCount: Int? = nil,
                entryId: String? = nil, groupId: String? = nil, counterpartyId: String? = nil,
                splits: [TxSplit]? = nil, tags: [String]? = nil, note: String? = nil,
                sourceTemplateId: String? = nil, occurrenceDate: String? = nil,
                refundedTransactionId: String? = nil,
                clearedAt: String? = nil, appliedRuleIds: [String]? = nil, reviewedAt: String? = nil) {
        self.id = id; self.merchant = merchant; self.category = category; self.amount = amount
        self.account = account; self.date = date; self.pending = pending
        self.pendingKind = pendingKind; self.ledgerId = ledgerId
        self.currency = currency; self.nativeAmount = nativeAmount; self.time = time; self.kind = kind
        self.transferGroupId = transferGroupId; self.accountLegCount = accountLegCount
        self.entryId = entryId; self.groupId = groupId
        self.counterpartyId = counterpartyId; self.splits = splits
        self.tags = tags; self.note = note; self.sourceTemplateId = sourceTemplateId
        self.occurrenceDate = occurrenceDate
        self.refundedTransactionId = refundedTransactionId; self.clearedAt = clearedAt
        self.appliedRuleIds = appliedRuleIds; self.reviewedAt = reviewedAt
    }
}

public extension Tx {
    /// Groups this row with every other row of the same purchase.
    ///
    /// Three levels, most-specific first, and the order is load-bearing:
    /// - `groupId` — a purchase split by card AND by category is several
    ///   TRANSACTIONS, one per card. Without this they count several times over,
    ///   which is the very bug the counting work fixed, reintroduced for the
    ///   shape the grid adds.
    /// - `entryId` — a purchase paid from several cards is one transaction with
    ///   several payment legs, and `Tx.id` is the POSTING id.
    /// - `id` — the fallback for a row decoded from a fixture written before
    ///   these fields existed. It reproduces the pre-fix behaviour of counting
    ///   each row separately, rather than collapsing every such row together
    ///   under one shared nil key.
    var purchaseKey: String { groupId ?? entryId ?? id }
}

public struct TxSplit: Codable, Equatable, Sendable {
    public var id: String?
    public var categoryId: String?
    public var amount: Double
    public var amountBase: Double
    public var description: String?
    /// What the user typed for THIS cell, when the purchase was entered in a
    /// currency other than the ledger base — and the currency they typed it in.
    ///
    /// `amount` and `amountBase` both remain the LEDGER BASE figure. This is a
    /// separate field rather than a redefinition of `amount` deliberately:
    /// `Selectors.categoryShares`, the split-sum guard in `Transactions.swift`
    /// and the Edit sheet's split seeding all read `amount` today, and all three
    /// want base.
    ///
    /// **iOS-only, by decision.** The web's projection
    /// (`frontend/lib/db/queries/transactions.ts`) does not read the column, so
    /// it never populates this. Nothing breaks — the web has no grid and no
    /// `saveTransaction` — but the two stacks do not agree about it, and the
    /// parity oracle cannot catch that: its fixture contains no split at all
    /// (3 entries × one account leg + one category leg). If you are adding the
    /// web side, add a split to the fixture at the same time.
    public var origAmount: Double?
    public var origCurrency: String?

    /// Explicit and public, like `Tx`'s and `AccountRow`'s. A public struct's
    /// MEMBERWISE init is internal, so without this the app module cannot build
    /// one — and the error it gets is a confusing "missing argument for
    /// parameter 'from'", Swift having fallen back to the Codable initialiser.
    public init(id: String? = nil, categoryId: String? = nil, amount: Double,
                amountBase: Double, description: String? = nil,
                origAmount: Double? = nil, origCurrency: String? = nil) {
        self.id = id; self.categoryId = categoryId
        self.amount = amount; self.amountBase = amountBase; self.description = description
        self.origAmount = origAmount; self.origCurrency = origCurrency
    }
}

public struct AccountRow: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var balance: Double
    public var ledgerId: String?
    public var currency: String?
    public var includeInNetWorth: Int?
    public var isActive: Bool?
    public var name: String?
    public var type: String?
    public var groupId: String?
    public var groupName: String?
    public var sortOrder: Int?
    public var openingBalanceBase: Double?   // for unrealizedFx cost basis
    public var openingBalance: Double?       // account-currency amount (the Edit sheet's field)
    /// Date of the `open-<id>` entry — when the opening figure applies FROM.
    /// nil when the account has no opening entry at all.
    public var openingDate: String?
    public var lastReconciledAt: String?
    public var lastReconciledBalance: Double?
    /// Curated icon name; nil = derive from `type`, which is what every account
    /// did before the column existed.
    public var icon: String?
    public var notes: String?
    /// Credit-card cycle days, 1-31. Meaningful only on `credit_card`; nil
    /// elsewhere and nil when unset.
    public var statementDay: Int?
    public var dueDay: Int?
    /// Account-currency credit limit. nil = unknown, which is NOT zero.
    public var creditLimit: Double?
    /// Who holds the account ("DBS", "Amex") and the last four digits — both
    /// descriptive only; nothing matches on them.
    public var institution: String?
    public var accountLast4: String?

    public init(id: String, balance: Double, ledgerId: String? = nil, currency: String? = nil,
                includeInNetWorth: Int? = nil, isActive: Bool? = nil, name: String? = nil,
                type: String? = nil, groupId: String? = nil, groupName: String? = nil,
                sortOrder: Int? = nil,
                icon: String? = nil, notes: String? = nil,
                statementDay: Int? = nil, dueDay: Int? = nil, creditLimit: Double? = nil,
                institution: String? = nil, accountLast4: String? = nil,
                openingBalanceBase: Double? = nil, openingBalance: Double? = nil,
                openingDate: String? = nil,
                lastReconciledAt: String? = nil, lastReconciledBalance: Double? = nil) {
        self.id = id; self.balance = balance; self.ledgerId = ledgerId; self.currency = currency
        self.includeInNetWorth = includeInNetWorth; self.isActive = isActive; self.name = name
        self.type = type; self.groupId = groupId; self.groupName = groupName
        self.sortOrder = sortOrder; self.openingBalanceBase = openingBalanceBase
        self.openingBalance = openingBalance; self.openingDate = openingDate
        self.icon = icon; self.notes = notes
        self.statementDay = statementDay; self.dueDay = dueDay; self.creditLimit = creditLimit
        self.institution = institution; self.accountLast4 = accountLast4
        self.lastReconciledAt = lastReconciledAt; self.lastReconciledBalance = lastReconciledBalance
    }
}

// `BudgetRow` lives in Project/Budget.swift (the full web-matching projection
// row consumed by both `Selectors.budgetProgress` and the Budgets tab).

public struct ListOptions: Equatable, Sendable {
    public var ledgerId: String
    public var direction: String?
    public var query: String?
    public var accountId: String?
    public var categoryId: String?
    public var status: String?
    public var from: String?
    public var to: String?
    public var minAmount: Double?
    public var maxAmount: Double?
    public var limit: Int?
    public var offset: Int?
    public var tagIds: [String]?
    public var tagsMatchAll: Bool
    public init(ledgerId: String, direction: String? = nil, query: String? = nil,
                accountId: String? = nil, categoryId: String? = nil, status: String? = nil,
                from: String? = nil, to: String? = nil, minAmount: Double? = nil,
                maxAmount: Double? = nil, limit: Int? = nil, offset: Int? = nil,
                tagIds: [String]? = nil, tagsMatchAll: Bool = false) {
        self.ledgerId = ledgerId; self.direction = direction; self.query = query
        self.accountId = accountId; self.categoryId = categoryId; self.status = status
        self.from = from; self.to = to; self.minAmount = minAmount; self.maxAmount = maxAmount
        self.limit = limit; self.offset = offset; self.tagIds = tagIds; self.tagsMatchAll = tagsMatchAll
    }
}

extension ListOptions: Codable {
    enum CodingKeys: String, CodingKey {
        case ledgerId, direction, query, accountId, categoryId, status, from, to
        case minAmount, maxAmount, limit, offset, tagIds, tagsMatchAll
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ledgerId, forKey: .ledgerId)
        try container.encodeIfPresent(direction, forKey: .direction)
        try container.encodeIfPresent(query, forKey: .query)
        try container.encodeIfPresent(accountId, forKey: .accountId)
        try container.encodeIfPresent(categoryId, forKey: .categoryId)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(from, forKey: .from)
        try container.encodeIfPresent(to, forKey: .to)
        try container.encodeIfPresent(minAmount, forKey: .minAmount)
        try container.encodeIfPresent(maxAmount, forKey: .maxAmount)
        try container.encodeIfPresent(limit, forKey: .limit)
        try container.encodeIfPresent(offset, forKey: .offset)
        try container.encodeIfPresent(tagIds, forKey: .tagIds)
        try container.encode(tagsMatchAll, forKey: .tagsMatchAll)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ledgerId = try container.decode(String.self, forKey: .ledgerId)
        direction = try container.decodeIfPresent(String.self, forKey: .direction)
        query = try container.decodeIfPresent(String.self, forKey: .query)
        accountId = try container.decodeIfPresent(String.self, forKey: .accountId)
        categoryId = try container.decodeIfPresent(String.self, forKey: .categoryId)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        from = try container.decodeIfPresent(String.self, forKey: .from)
        to = try container.decodeIfPresent(String.self, forKey: .to)
        minAmount = try container.decodeIfPresent(Double.self, forKey: .minAmount)
        maxAmount = try container.decodeIfPresent(Double.self, forKey: .maxAmount)
        limit = try container.decodeIfPresent(Int.self, forKey: .limit)
        offset = try container.decodeIfPresent(Int.self, forKey: .offset)
        tagIds = try container.decodeIfPresent([String].self, forKey: .tagIds)
        tagsMatchAll = try container.decodeIfPresent(Bool.self, forKey: .tagsMatchAll) ?? false
    }
}

/// A `{ id, parentId }` node — the recursive-budget category-matching input.
public struct CategoryNode: Codable, Equatable, Sendable {
    public var id: String
    public var parentId: String?
    public init(id: String, parentId: String?) {
        self.id = id; self.parentId = parentId
    }
}

// MARK: selector return types

public struct MerchantStats: Codable, Equatable, Sendable {
    public var count: Int
    public var mean: Double
    public var std: Double
}

/// One row of `Selectors.topMerchants` — a merchant's net expense total
/// (refunds netted) in the ledger base currency.
public struct MerchantSpend: Codable, Equatable, Sendable {
    public let name: String
    public let total: Double
    public init(name: String, total: Double) { self.name = name; self.total = total }
}

public struct RecurringCharge: Identifiable, Equatable, Sendable, Codable {
    public let id: String              // = merchantKey
    public let merchantName: String
    public let averageAmount: Double
    public let cadence: String         // weekly | biweekly | monthly | quarterly | yearly
    public let monthlyEstimate: Double
    public let occurrences: Int
    public let lastDate: String
    public let nextEstimatedDate: String
    public let isScheduled: Bool
    public let accountId: String?
    public let categoryId: String?
    public init(id: String, merchantName: String, averageAmount: Double, cadence: String,
                monthlyEstimate: Double, occurrences: Int, lastDate: String,
                nextEstimatedDate: String, isScheduled: Bool,
                accountId: String?, categoryId: String?) {
        self.id = id; self.merchantName = merchantName; self.averageAmount = averageAmount
        self.cadence = cadence; self.monthlyEstimate = monthlyEstimate; self.occurrences = occurrences
        self.lastDate = lastDate; self.nextEstimatedDate = nextEstimatedDate; self.isScheduled = isScheduled
        self.accountId = accountId; self.categoryId = categoryId
    }
}

public struct AnomalyScore: Codable, Equatable, Sendable {
    public var zScore: Double
    public var mean: Double
    public var count: Int
    public var isAnomaly: Bool
}

/// A budget cycle: `[from fromTime, to toTime)`.
///
/// With both times nil — every budget until one is given a turnover time — this is
/// the inclusive whole-day window it has always been, and encodes to exactly the
/// same JSON, so no existing fixture moves.
///
/// With a time, the cycle turns over at that moment: a monthly budget starting
/// 1 Aug 09:30 runs to 1 Sep 09:30, so its last (partial) day is 1 Sep and `toTime`
/// is the moment it stops counting.
public struct CycleWindow: Codable, Equatable, Sendable {
    public var from: String
    public var to: String
    /// Inclusive start time on `from`. Nil = midnight.
    public var fromTime: String?
    /// EXCLUSIVE end time on `to`. Nil = the whole of `to` counts.
    public var toTime: String?

    public init(from: String, to: String, fromTime: String? = nil, toTime: String? = nil) {
        self.from = from; self.to = to; self.fromTime = fromTime; self.toTime = toTime
    }
}

public struct BudgetProgress: Codable, Equatable, Sendable {
    public var from: String
    public var to: String
    public var base: Double
    public var used: Double
    public var remaining: Double
    public var pct: Int
    public var over: Bool
}

/// A named group (id + name + optional color) — for group pickers + group admin UI (accounts + budgets).
public struct GroupRow: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var color: String?
    public init(id: String, name: String, color: String? = nil) { self.id = id; self.name = name; self.color = color }
}
public typealias AccountGroupRow = GroupRow
