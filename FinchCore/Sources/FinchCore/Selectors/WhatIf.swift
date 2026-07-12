import Foundation

// What-if baseline — average monthly spend per category over the trailing
// complete months, plus average income/spend totals (port of the web's
// whatIfBaseline, #411 / FEATURE_IDEAS §3.3). The Insights what-if card runs
// interactive hypotheticals ("cut dining 30%") against this baseline; the
// slider math itself is trivial and lives in the card.
extension Selectors {
    public struct WhatIfBaseline: Equatable, Sendable {
        public struct Category: Equatable, Sendable {
            public let categoryId: String
            public let avgMonthly: Double
            public init(categoryId: String, avgMonthly: Double) {
                self.categoryId = categoryId; self.avgMonthly = avgMonthly
            }
        }
        /// Months (YYYY-MM) the averages cover, oldest first.
        public let months: [String]
        /// Top categories by average monthly spend, descending (positive amounts).
        public let categories: [Category]
        /// Average monthly confirmed income over the window.
        public let avgIncome: Double
        /// Average total monthly spend over the window (all categories, not just top-N).
        public let avgSpend: Double
    }

    /// Baseline for the what-if sliders: category spend averaged over up to
    /// `windowMonths` complete months before `anchorMonth` (the current, likely
    /// partial, month). Months with no confirmed spend are dropped so a fresh
    /// ledger isn't diluted toward zero; when no complete month has data the
    /// anchor month itself is the (1-month) window. Returns nil when there's no
    /// spend anywhere to build a baseline from.
    public static func whatIfBaseline(_ txns: [Tx], _ ledgerId: String, _ anchorMonth: String,
                                      windowMonths: Int = 3, topN: Int = 5) -> WhatIfBaseline? {
        if anchorMonth.isEmpty { return nil }
        func hasSpend(_ by: [String: Double]) -> Bool { by.values.contains { $0 > 0 } }

        // Trailing complete months with data; fall back to the anchor month.
        let candidates = monthsBack(prevMonth(anchorMonth), windowMonths)
        var window: [(m: String, by: [String: Double])] = candidates
            .map { ($0, categorySpend(txns, ledgerId, $0)) }
            .filter { hasSpend($0.by) }
        if window.isEmpty {
            let by = categorySpend(txns, ledgerId, anchorMonth)
            if !hasSpend(by) { return nil }
            window = [(anchorMonth, by)]
        }

        let n = Double(window.count)
        var totals: [String: Double] = [:]
        for (_, by) in window {
            for (cat, v) in by { totals[cat, default: 0] += v }
        }
        // Web sorts by value desc; ties get a stable id tiebreak here so the
        // result is deterministic (Swift's sort is not guaranteed stable).
        let averaged: [WhatIfBaseline.Category] = totals.map { key, value in
            WhatIfBaseline.Category(categoryId: key, avgMonthly: r2(value / n))
        }
        let positive: [WhatIfBaseline.Category] = averaged.filter { $0.avgMonthly > 0 }
        let sorted: [WhatIfBaseline.Category] = positive.sorted { lhs, rhs in
            lhs.avgMonthly == rhs.avgMonthly ? lhs.categoryId < rhs.categoryId
                                             : lhs.avgMonthly > rhs.avgMonthly
        }
        let categories: [WhatIfBaseline.Category] = Array(sorted.prefix(topN))
        if categories.isEmpty { return nil }

        let monthSet = Set(window.map(\.m))
        var incomeSum = 0.0
        var spendSum = 0.0
        for t in txns {
            if ledgerOf(t) != ledgerId || (t.pending ?? false) { continue }
            if !monthSet.contains(String(t.date.prefix(7))) { continue }
            let k = kindOf(t)
            if k == "income" { incomeSum += t.amount }
            else if isSpend(t) { spendSum += -t.amount }
        }

        return WhatIfBaseline(months: window.map(\.m), categories: categories,
                              avgIncome: r2(incomeSum / n), avgSpend: r2(spendSum / n))
    }
}
