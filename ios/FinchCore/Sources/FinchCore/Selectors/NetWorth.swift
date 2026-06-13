import Foundation

// Phase 1.5 batch 3a — account / net-worth selectors (mirror of lib/select.ts).
// They take the projected AccountRow[] and an optional `ToBase` conversion (so
// mixed-currency balances sum in one currency); the parity fixtures use the
// default identity (single-currency), which closures-can't-serialize forces.

/// Re-express an amount in some currency into the ledger base. Defaults to
/// identity (no-op when every account is already in the ledger base).
public typealias ToBase = (Double, String?) -> Double

public struct NetWorthExplained: Equatable, Sendable, Codable {
    public let m: String          // YYYY-MM key (NOT a label, unlike netWorthByMonth)
    public let income: Double
    public let expense: Double
    public let adjustment: Double
    public let fx: Double
    public let net: Double
}
public struct AccountTypeBalance: Equatable, Sendable, Codable {
    public let type: String
    public let balance: Double
}
public struct Transfer: Equatable, Sendable, Codable {
    public let id: String
    public let date: String
    public let time: String?
    public let amount: Double          // native (from-leg)
    public let toAmount: Double        // native (to-leg)
    public let fromCurrency: String
    public let toCurrency: String
    public let fromAccountId: String?
    public let toAccountId: String?
    public let fromName: String?
    public let toName: String?
    public let note: String?
}

extension Selectors {

    static func byDateAsc(_ a: Tx, _ b: Tx) -> Bool {
        if a.date != b.date { return a.date < b.date }
        return (a.time ?? "") < (b.time ?? "")
    }

    /// Reconstruct the running-balance curve from a tx set whose final value is
    /// `endValue`: opening = end − Σamounts, then accumulate. NOT rounded (the
    /// web returns raw doubles; identical accumulation order → identical FP).
    static func runningSeries(_ txns: [Tx], _ endValue: Double,
                              _ amountOf: (Tx) -> Double = { $0.amount }) -> [Double] {
        let rows = txns.sorted(by: byDateAsc)
        let opening = endValue - rows.reduce(0.0) { $0 + amountOf($1) }
        var out = [opening]
        var bal = opening
        for t in rows { bal += amountOf(t); out.append(bal) }
        return out
    }

    /// Accounts counting toward net worth for a ledger (active + included).
    private static func netWorthAccounts(_ accounts: [AccountRow], _ ledgerId: String) -> [AccountRow] {
        accounts.filter { $0.ledgerId == ledgerId && ($0.includeInNetWorth ?? 1) != 0 && ($0.isActive ?? true) }
    }

    // MARK: netWorthByMonth

    public static func netWorthByMonth(_ txns: [Tx], _ accounts: [AccountRow], _ ledgerId: String,
                                       _ endMonth: String, _ n: Int,
                                       _ toBase: ToBase = { a, _ in a }) -> [MonthlyPoint] {
        if endMonth.isEmpty { return [] }
        let months = monthsBack(endMonth, n)
        let total = netWorthAccounts(accounts, ledgerId).reduce(0.0) { $0 + toBase($1.balance, $1.currency) }
        let ledgerTxns = txns.filter { ledgerOf($0) == ledgerId && !($0.pending ?? false) }
        let sorted = ledgerTxns.sorted(by: byDateAsc)
        let opening = total - sorted.reduce(0.0) { $0 + $1.amount }
        var bal = opening
        var i = 0
        return months.map { mo in
            while i < sorted.count && String(sorted[i].date.prefix(7)) <= mo { bal += sorted[i].amount; i += 1 }
            return MonthlyPoint(m: monthLabels[(Int(mo.suffix(2)) ?? 1) - 1], v: r2(bal))
        }
    }

    // MARK: netWorthExplained

    public static func netWorthExplained(_ txns: [Tx], _ accounts: [AccountRow], _ ledgerId: String,
                                         _ endMonth: String, _ n: Int,
                                         _ toBase: ToBase = { a, _ in a }) -> [NetWorthExplained] {
        if endMonth.isEmpty { return [] }
        let months = monthsBack(endMonth, n)
        let series = netWorthByMonth(txns, accounts, ledgerId, endMonth, n + 1, toBase)
        let extendedMonths = monthsBack(endMonth, n + 1)
        var deltas: [String: Double] = [:]
        var i = 1
        while i < series.count && i < extendedMonths.count {
            deltas[extendedMonths[i]] = series[i].v - series[i - 1].v
            i += 1
        }
        let ledgerTxns = txns.filter { ledgerOf($0) == ledgerId && !($0.pending ?? false) }
        return months.map { m in
            var income = 0.0, expensePositive = 0.0, refundPositive = 0.0, adjustment = 0.0
            for t in ledgerTxns where t.date.hasPrefix(m) {
                switch t.kind {
                case "income": income += t.amount
                case "expense": expensePositive += abs(t.amount)
                case "refund": refundPositive += t.amount
                case "adjustment": adjustment += t.amount
                default: break
                }
            }
            let expense = expensePositive - refundPositive
            let net = deltas[m] ?? 0
            let fx = r2(net - income + expense - adjustment)
            return NetWorthExplained(m: m, income: r2(income), expense: r2(expense),
                                     adjustment: r2(adjustment), fx: fx, net: r2(net))
        }
    }

    // MARK: balanceSeries / netWorthSeries

    /// Balance-over-time for one account (account currency: walks nativeAmount).
    public static func balanceSeries(_ txns: [Tx], _ accountId: String, _ currentBalance: Double) -> [Double] {
        runningSeries(txns.filter { $0.account == accountId && !($0.pending ?? false) },
                      currentBalance, { $0.nativeAmount ?? $0.amount })
    }

    /// Net-worth-over-time for a ledger (ends at the current total).
    public static func netWorthSeries(_ txns: [Tx], _ accounts: [AccountRow], _ ledgerId: String,
                                      _ toBase: ToBase = { a, _ in a }) -> [Double] {
        let total = netWorthAccounts(accounts, ledgerId).reduce(0.0) { $0 + toBase($1.balance, $1.currency) }
        return runningSeries(txns.filter { ledgerOf($0) == ledgerId && !($0.pending ?? false) }, total)
    }

    // MARK: netWorthByAccountType

    public static func netWorthByAccountType(_ accounts: [AccountRow], _ ledgerId: String,
                                             _ toBase: ToBase = { a, _ in a }) -> [AccountTypeBalance] {
        var byType: [String: Double] = [:]
        for a in accounts {
            if a.ledgerId != ledgerId { continue }
            if (a.includeInNetWorth ?? 1) == 0 { continue }
            if !(a.isActive ?? true) { continue }
            byType[a.type ?? "", default: 0] += toBase(a.balance, a.currency)
        }
        let order = ["cash", "savings", "investment", "credit_card", "fx", "virtual"]
        return order.map { AccountTypeBalance(type: $0, balance: r2(byType[$0] ?? 0)) }
    }

    // MARK: selectTransfers

    public static func selectTransfers(_ txns: [Tx], _ accounts: [AccountRow], _ ledgerId: String) -> [Transfer] {
        let ledgerAccounts = accounts.filter { $0.ledgerId == ledgerId }
        let nameById = Dictionary(uniqueKeysWithValues: ledgerAccounts.compactMap { a in a.name.map { (a.id, $0) } })
        let curById = Dictionary(uniqueKeysWithValues: ledgerAccounts.compactMap { a in a.currency.map { (a.id, $0) } })
        var groups: [String: [Tx]] = [:]
        var order: [String] = []
        for t in txns {
            if ledgerOf(t) != ledgerId { continue }
            guard let g = t.transferGroupId else { continue }
            if groups[g] == nil { order.append(g) }
            groups[g, default: []].append(t)
        }
        var out: [Transfer] = []
        for id in order {
            let rows = groups[id]!
            let outLeg = rows.first { $0.amount < 0 }
            let inLeg = rows.first { $0.amount > 0 }
            let date = rows.reduce(rows[0].date) { $1.date > $0 ? $1.date : $0 }
            let fromId = outLeg?.account
            let toId = inLeg?.account
            out.append(Transfer(
                id: id, date: date, time: rows.compactMap { $0.time }.first,
                amount: outLeg.map { abs($0.nativeAmount ?? $0.amount) } ?? 0,
                toAmount: inLeg.map { abs($0.nativeAmount ?? $0.amount) } ?? 0,
                fromCurrency: (fromId.flatMap { curById[$0] }) ?? outLeg?.currency ?? "USD",
                toCurrency: (toId.flatMap { curById[$0] }) ?? inLeg?.currency ?? "USD",
                fromAccountId: fromId, toAccountId: toId,
                fromName: fromId.flatMap { nameById[$0] }, toName: toId.flatMap { nameById[$0] },
                note: rows.compactMap { $0.note }.first))
        }
        return out.sorted { $0.date > $1.date }
    }
}
