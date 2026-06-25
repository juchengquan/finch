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
    public var ledgerId: String?
    public var currency: String?
    public var nativeAmount: Double?
    public var time: String?
    public var kind: String?
    public var transferGroupId: String?
    public var counterpartyId: String?
    public var splits: [TxSplit]?
    public var tags: [String]?
    public var note: String?
    public var sourceTemplateId: String?
    public var refundedTransactionId: String?
    public var clearedAt: String?
    public var appliedRuleIds: [String]?
    public var reviewedAt: String?

    public init(id: String, merchant: String, category: String? = nil, amount: Double,
                account: String, date: String, pending: Bool? = nil, ledgerId: String? = nil,
                currency: String? = nil, nativeAmount: Double? = nil, time: String? = nil,
                kind: String? = nil, transferGroupId: String? = nil, counterpartyId: String? = nil,
                splits: [TxSplit]? = nil, tags: [String]? = nil, note: String? = nil,
                sourceTemplateId: String? = nil, refundedTransactionId: String? = nil,
                clearedAt: String? = nil, appliedRuleIds: [String]? = nil, reviewedAt: String? = nil) {
        self.id = id; self.merchant = merchant; self.category = category; self.amount = amount
        self.account = account; self.date = date; self.pending = pending; self.ledgerId = ledgerId
        self.currency = currency; self.nativeAmount = nativeAmount; self.time = time; self.kind = kind
        self.transferGroupId = transferGroupId; self.counterpartyId = counterpartyId; self.splits = splits
        self.tags = tags; self.note = note; self.sourceTemplateId = sourceTemplateId
        self.refundedTransactionId = refundedTransactionId; self.clearedAt = clearedAt
        self.appliedRuleIds = appliedRuleIds; self.reviewedAt = reviewedAt
    }
}

public struct TxSplit: Codable, Equatable, Sendable {
    public var id: String?
    public var categoryId: String?
    public var amount: Double
    public var amountBase: Double
    public var description: String?
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
    public var lastReconciledAt: String?
    public var lastReconciledBalance: Double?

    public init(id: String, balance: Double, ledgerId: String? = nil, currency: String? = nil,
                includeInNetWorth: Int? = nil, isActive: Bool? = nil, name: String? = nil,
                type: String? = nil, groupId: String? = nil, groupName: String? = nil,
                sortOrder: Int? = nil, openingBalanceBase: Double? = nil,
                lastReconciledAt: String? = nil, lastReconciledBalance: Double? = nil) {
        self.id = id; self.balance = balance; self.ledgerId = ledgerId; self.currency = currency
        self.includeInNetWorth = includeInNetWorth; self.isActive = isActive; self.name = name
        self.type = type; self.groupId = groupId; self.groupName = groupName
        self.sortOrder = sortOrder; self.openingBalanceBase = openingBalanceBase
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

public struct AnomalyScore: Codable, Equatable, Sendable {
    public var zScore: Double
    public var mean: Double
    public var count: Int
    public var isAnomaly: Bool
}

public struct CycleWindow: Codable, Equatable, Sendable {
    public var from: String
    public var to: String
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

/// A named group (id + name) — for group pickers + group admin UI (accounts + budgets).
public struct GroupRow: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}
public typealias AccountGroupRow = GroupRow
