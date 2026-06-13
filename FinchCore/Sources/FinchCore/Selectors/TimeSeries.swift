import Foundation

// Phase 1.5 time-series / delta selectors (mirror of lib/select.ts). Return
// types' field names match the web JSON verbatim — the parity fixtures decode
// straight into these.

public struct MonthlyPoint: Equatable, Sendable, Codable {
    public let m: String      // 3-letter month label ("Jan"…"Dec")
    public let v: Double
}
public struct DailyPoint: Equatable, Sendable, Codable {
    public let date: String   // YYYY-MM-DD
    public let value: Double
}
public struct CashflowPoint: Equatable, Sendable, Codable {
    public let m: String      // 3-letter month label
    public let inc: Double
    public let exp: Double
}
public struct CategoryDelta: Equatable, Sendable, Codable {
    public let name: String
    public let a: Double      // previous month spend
    public let b: Double      // current month spend
    public let d: Int         // percent change (Math.round)
}
/// `{ id, name }` — the minimal category input some selectors take.
public struct CategoryRef: Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

extension Selectors {

    static let monthLabels = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// absolute-month-index (year*12 + month0) → "YYYY-MM". Floor division so it
    /// matches JS `new Date(y, m-1±k, 1)` year rollover.
    private static func monthKey(_ idx: Int) -> String {
        let y = Int((Double(idx) / 12).rounded(.down))
        let m = idx - y * 12 + 1
        return String(format: "%04d-%02d", y, m)
    }
    private static func monthIndex(_ ym: String) -> Int {
        let p = ym.split(separator: "-").map { Int($0) ?? 0 }
        let y = p.count > 0 ? p[0] : 0, m = p.count > 1 ? p[1] : 1
        return y * 12 + (m - 1)
    }

    /// The calendar month before `month` (YYYY-MM).
    public static func prevMonth(_ month: String) -> String {
        monthKey(monthIndex(month) - 1)
    }

    /// YYYY-MM keys for the N months ending at (and including) endMonth, oldest first.
    static func monthsBack(_ endMonth: String, _ n: Int) -> [String] {
        if endMonth.isEmpty { return [] }
        let base = monthIndex(endMonth)
        return stride(from: n - 1, through: 0, by: -1).map { monthKey(base - $0) }
    }

    private static func label(_ ym: String) -> String {
        monthLabels[(Int(ym.suffix(2)) ?? 1) - 1]
    }

    /// The latest transaction month (YYYY-MM) in the (optionally ledger-scoped) set.
    public static func currentMonth(_ txns: [Tx], _ ledgerId: String? = nil) -> String {
        var maxDate = ""
        for t in txns {
            if let ledgerId, ledgerOf(t) != ledgerId { continue }
            if t.date > maxDate { maxDate = t.date }
        }
        return String(maxDate.prefix(7))
    }

    /// Monthly expense totals (positive magnitude), oldest first.
    public static func monthlySpending(_ txns: [Tx], _ ledgerId: String,
                                       _ endMonth: String, _ n: Int) -> [MonthlyPoint] {
        let months = monthsBack(endMonth, n)
        var by = Dictionary(uniqueKeysWithValues: months.map { ($0, 0.0) })
        for t in txns {
            if ledgerOf(t) != ledgerId { continue }
            if (t.pending ?? false) || !isSpend(t) { continue }
            let mo = String(t.date.prefix(7))
            if by[mo] == nil { continue }
            by[mo]! += -t.amount
        }
        return months.map { MonthlyPoint(m: label($0), v: r2(by[$0] ?? 0)) }
    }

    /// Daily expense totals (positive) for the N days ending at endDate, oldest
    /// first. UTC day math (matches the web's `T00:00:00Z` parsing).
    public static func dailySpending(_ txns: [Tx], _ ledgerId: String,
                                     _ endDate: String, _ n: Int) -> [DailyPoint] {
        if endDate.isEmpty { return [] }
        let end = date(endDate)
        var keys: [String] = []
        var by: [String: Double] = [:]
        for i in stride(from: n - 1, through: 0, by: -1) {
            let key = ymd(addDays(end, -i))
            by[key] = 0
            keys.append(key)
        }
        for t in txns {
            if ledgerOf(t) != ledgerId { continue }
            if (t.pending ?? false) || !isSpend(t) { continue }
            if by[t.date] == nil { continue }
            by[t.date]! += -t.amount
        }
        return keys.map { DailyPoint(date: $0, value: r2(by[$0] ?? 0)) }
    }

    /// Income / expense totals per month (both positive). Refund nets into expense.
    public static func monthlyCashflow(_ txns: [Tx], _ ledgerId: String,
                                       _ endMonth: String, _ n: Int) -> [CashflowPoint] {
        let months = monthsBack(endMonth, n)
        var inc = Dictionary(uniqueKeysWithValues: months.map { ($0, 0.0) })
        var exp = inc
        for t in txns {
            if ledgerOf(t) != ledgerId { continue }
            let k = kindOf(t)
            if (t.pending ?? false) || k == "transfer" || k == "adjustment" { continue }
            let mo = String(t.date.prefix(7))
            if inc[mo] == nil { continue }
            if k == "income" { inc[mo]! += t.amount } else { exp[mo]! += -t.amount }
        }
        return months.map { CashflowPoint(m: label($0), inc: r2(inc[$0] ?? 0), exp: r2(exp[$0] ?? 0)) }
    }

    /// Top categories by absolute month-over-month spend delta. `a` = prev month,
    /// `b` = current month, `d` = percent change.
    public static func topCategoryDeltas(_ txns: [Tx], _ ledgerId: String,
                                         _ curMonth: String, _ categories: [CategoryRef],
                                         _ count: Int = 5) -> [CategoryDelta] {
        if curMonth.isEmpty { return [] }
        let cur = categorySpend(txns, ledgerId, curMonth)
        let prv = categorySpend(txns, ledgerId, prevMonth(curMonth))
        let nameById = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        var seen = Set(cur.keys); seen.formUnion(prv.keys)
        let deltas = seen.map { id -> CategoryDelta in
            let a = r2(prv[id] ?? 0)
            let b = r2(cur[id] ?? 0)
            let d = a > 0 ? Int(((b - a) / a * 100).rounded()) : (b > 0 ? 100 : 0)
            return CategoryDelta(name: nameById[id] ?? id, a: a, b: b, d: d)
        }
        return Array(deltas
            .filter { $0.a > 0 || $0.b > 0 }
            .sorted { abs($0.b - $0.a) > abs($1.b - $1.a) }
            .prefix(count))
    }
}
