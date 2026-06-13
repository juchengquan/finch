import Foundation

// Phase 1.5 batch 4 — holdings / FX selectors (mirror of lib/select.ts).

/// A holding/position (mirror of lib/db/domain/holdings/types.ts::Holding).
public struct Holding: Equatable, Sendable, Codable {
    public let id: String
    public let ledgerId: String
    public let accountId: String
    public let symbol: String
    public let name: String?
    public let shares: Double
    public let costBasis: Double
    public let currency: String
    public let lastPrice: Double?
    public let lastPriceDate: String?
    public let notes: String?
}

extension Selectors {

    /// Holdings for one account.
    public static func holdingsForAccount(_ holdings: [Holding], _ accountId: String) -> [Holding] {
        holdings.filter { $0.accountId == accountId }
    }

    /// Live market value of one position (own currency). Nil when no price logged.
    public static func holdingValue(_ h: Holding) -> Double? {
        guard let price = h.lastPrice else { return nil }
        return r2(h.shares * price)
    }

    /// Unrealized gain/loss on one position (value − costBasis). Nil when no price.
    public static func holdingGainLoss(_ h: Holding) -> Double? {
        guard let v = holdingValue(h) else { return nil }
        return r2(v - h.costBasis)
    }

    /// Sum of holding values for `accountId` (account currency); priced positions
    /// use value, unpriced ones fall back to cost basis.
    public static func holdingsValueForAccount(_ holdings: [Holding], _ accountId: String) -> Double {
        var total = 0.0
        for h in holdings where h.accountId == accountId {
            total += holdingValue(h) ?? h.costBasis
        }
        return r2(total)
    }

    /// Total value of an investment account: cash + holdings value. Non-investment
    /// accounts return the cash balance unchanged (account currency).
    public static func investmentAccountTotal(_ account: AccountRow, _ holdings: [Holding]) -> Double {
        if account.type != "investment" { return account.balance }
        return r2(account.balance + holdingsValueForAccount(holdings, account.id))
    }

    /// Unrealized FX gain/loss on one account, in ledger base.
    ///   cost basis    = openingBalanceBase + Σ amount_base of confirmed txns
    ///   current value = toBase(currentBalance, accountCurrency)
    public static func unrealizedFx(_ account: AccountRow, _ txns: [Tx],
                                    _ toBase: ToBase = { a, _ in a }) -> Double {
        let currentValueBase = toBase(account.balance, account.currency)
        var costBasis = account.openingBalanceBase ?? 0
        for t in txns {
            if ledgerOf(t) != account.ledgerId { continue }
            if t.account != account.id { continue }
            if (t.pending ?? false) { continue }
            costBasis += t.amount
        }
        return r2(currentValueBase - costBasis)
    }
}
