import Foundation

// The client-projected value types the selectors operate on. Field names are
// camelCase to match the web `Tx`/`AccountRow`/`BudgetRow` JSON verbatim (the
// parity fixtures decode straight into these). Extra JSON keys are ignored.

public struct Tx: Codable, Equatable, Sendable {
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
}

public struct TxSplit: Codable, Equatable, Sendable {
    public var id: String?
    public var categoryId: String?
    public var amount: Double
    public var amountBase: Double
    public var description: String?
}

public struct AccountRow: Codable, Equatable, Sendable {
    public var id: String
    public var balance: Double
    public var ledgerId: String?
    public var currency: String?
    public var includeInNetWorth: Int?
    public var isActive: Bool?
    public var name: String?
    public var type: String?
}

public struct BudgetRow: Codable, Equatable, Sendable {
    public var id: String
    public var ledgerId: String
    public var name: String
    public var type: String
    public var amount: Double
    public var saved: Double
    public var carryForward: Double
    public var frequency: String
    public var startDate: String
    public var endDate: String?
    public var isRecurring: Int
    public var accountIds: [String]
    public var categoryIds: [String]
}

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
