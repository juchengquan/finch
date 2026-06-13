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

public struct AccountRow: Identifiable, Codable, Equatable, Sendable {
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
}

// `BudgetRow` lives in Project/Budget.swift (the full web-matching projection
// row consumed by both `Selectors.budgetProgress` and the Budgets tab).

public struct ListOptions: Codable, Equatable, Sendable {
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
