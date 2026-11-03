import Foundation
import FinchCore

/// Groups a transaction list into month sections for the Activity feed and the
/// account-detail list. Pure (no store / clock / I/O) so it is unit-tested; both
/// surfaces call it, so the grouping lives in exactly one place.
enum MonthGrouping {
    struct Section: Identifiable {
        let id: String        // "yyyy-MM"
        let txns: [Tx]
    }

    /// A month's inclusive ISO bounds — `(2026-08-01, 2026-08-31)` for any instant
    /// inside August 2026. Civil-calendar components, per the `AppDate` rule.
    static func monthBounds(_ d: Date) -> (start: String, end: String) {
        let y = AppDate.civil.component(.year, from: d)
        let m = AppDate.civil.component(.month, from: d)
        let days = AppDate.civil.range(of: .day, in: .month, for: d)?.count ?? 30
        return (String(format: "%04d-%02d-01", y, m), String(format: "%04d-%02d-%02d", y, m, days))
    }

    /// The month calendar's data window: the month BEFORE `d` through the month
    /// AFTER it.
    ///
    /// `MonthCashCalendar` draws the anchored month and its neighbours, and asks its
    /// caller for each page's totals separately — so a caller that expands only the
    /// anchored month leaves the incoming page drawing bare day numbers under the
    /// finger, with the figures appearing after the swipe settles. This lives here
    /// because that is exactly what happened: `ScheduledCalendarView` had the window
    /// right and the UIKit port re-derived it a month too narrow.
    static func carouselWindow(_ d: Date) -> (start: String, end: String) {
        let prev = AppDate.civil.date(byAdding: .month, value: -1, to: d) ?? d
        let next = AppDate.civil.date(byAdding: .month, value: 1, to: d) ?? d
        return (monthBounds(prev).start, monthBounds(next).end)
    }

    /// Group `txns` into month sections. Sections appear in the order each month's
    /// FIRST transaction appears in the input — the grouping never sorts. A
    /// date-descending caller (e.g. account detail) therefore gets newest-month-first;
    /// other input orderings (e.g. the Activity feed, whose sort menu can be
    /// Oldest/Largest/etc.) get a correspondingly-ordered result. Key is the `yyyy-MM`
    /// prefix of the ISO date string — no calendar math, so it's timezone-independent.
    static func sections(_ txns: [Tx]) -> [Section] {
        var order: [String] = []
        var byMonth: [String: [Tx]] = [:]
        for t in txns {
            let key = String(t.date.prefix(7))        // "yyyy-MM"
            if byMonth[key] == nil { order.append(key) }
            byMonth[key, default: []].append(t)
        }
        return order.map { Section(id: $0, txns: byMonth[$0] ?? []) }
    }

    /// "2026-09" -> "September 2026" (device locale, wide month). Returns the key
    /// unchanged if it doesn't parse.
    static func label(_ key: String) -> String {
        guard let d = AppDate.isoDay.date(from: "\(key)-01") else { return key }
        return d.formatted(.dateTime.month(.wide).year())
    }

    /// Net change of a month's transactions, in ledger-base amount (`Tx.amount` is
    /// base). Callers format with `store.displayMoneyBase`.
    ///
    /// `pairedOver` is every row the screen holds, when `txns` is only some of them:
    /// the Activity feed shows a page at a time, and its edge can fall between a
    /// transfer's two legs. Paired over the whole set (see `counted`), the month's
    /// figures don't move when "Load more" brings in the other leg.
    static func net(_ txns: [Tx], pairedOver scope: [Tx]? = nil) -> Double {
        counted(txns, pairedOver: scope).reduce(0) { $0 + $1.amount }
    }

    /// Inflows (sum of positive amounts) and outflows (magnitude of negative
    /// amounts) — the header's "Income · Spent" line. Split by sign, so refund legs
    /// and one-sided transfer legs count on the side they move money: the identities
    /// `income - expense == net` and header-vs-rows agreement hold on every surface.
    ///
    /// The one carve-out is a transfer between your own accounts with BOTH legs in
    /// the rows (see `counted`). Summed by sign, a $250 Checking → Savings transfer
    /// added $250 to the ledger-wide feed's in AND its out, for money that never
    /// left the ledger. One account's list holds one leg, which still counts.
    static func income(_ txns: [Tx], pairedOver scope: [Tx]? = nil) -> Double {
        counted(txns, pairedOver: scope).reduce(0) { $1.amount > 0 ? $0 + $1.amount : $0 }
    }
    static func expense(_ txns: [Tx], pairedOver scope: [Tx]? = nil) -> Double {
        counted(txns, pairedOver: scope).reduce(0) { $1.amount < 0 ? $0 - $1.amount : $0 }
    }

    /// What a total over `txns` counts, as (date, base amount) pairs.
    ///
    /// A transfer whose every leg is in `scope` (`txns` itself by default) moved money
    /// inside the set, so its legs drop out. What they leave over does not: a
    /// currency exchange's legs rarely cancel in base — $100 out, €90 worth $98 in —
    /// because the engine books the difference to an FX leg the rows never show.
    /// That is what the exchange cost (or gained), so it comes back as one amount on
    /// the transfer's date, once per transfer, whichever of its legs `txns` holds.
    private static func counted(_ txns: [Tx], pairedOver scope: [Tx]? = nil) -> [(date: String, amount: Double)] {
        let scope = scope ?? txns
        let internalLegs = TransferLegs.complete(scope)
        guard !internalLegs.isEmpty else { return txns.map { ($0.date, $0.amount) } }
        var remainder: [String: Double] = [:]
        for t in scope where internalLegs.contains(t.id) {
            remainder[t.transferGroupId ?? t.id, default: 0] += t.amount
        }
        var out: [(date: String, amount: Double)] = []
        var seen = Set<String>()
        for t in txns {
            guard internalLegs.contains(t.id) else { out.append((t.date, t.amount)); continue }
            let group = t.transferGroupId ?? t.id
            guard seen.insert(group).inserted else { continue }
            let left = ((remainder[group] ?? 0) * 100).rounded() / 100
            if left != 0 { out.append((t.date, left)) }
        }
        return out
    }

    /// Per-day inflow/outflow (ledger-base, same sign-split and same transfer
    /// carve-out as the month headers), keyed by the full ISO date — the calendar's
    /// daily "income / expense" cell lines. Days with no transactions are absent.
    static func dailyIncomeExpense(_ txns: [Tx]) -> [String: (income: Double, expense: Double)] {
        var out: [String: (income: Double, expense: Double)] = [:]
        for t in counted(txns) {
            var day = out[t.date] ?? (0, 0)
            if t.amount > 0 { day.income += t.amount } else { day.expense -= t.amount }
            out[t.date] = day
        }
        return out
    }
}
