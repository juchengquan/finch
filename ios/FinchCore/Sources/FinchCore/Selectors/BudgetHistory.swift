import Foundation

// Budget cycle history — spent vs budget across the trailing cycles, for the
// budget detail page's History chart ("do I chronically bust this budget?").
// iOS-original (no web counterpart yet).
extension Selectors {
    public struct BudgetCyclePoint: Equatable, Sendable {
        /// Cycle bounds (YYYY-MM-DD). Inclusive when the budget has no turnover
        /// time; with one, `to` is the day the cycle STOPS on and `toTime` is the
        /// moment within it, exclusive — the same convention as `CycleWindow`.
        public let from: String
        public let to: String
        public let fromTime: String?
        public let toTime: String?
        /// Budget-matched activity in the cycle (same predicate as budgetProgress).
        public let used: Double
        /// The cap the cycle is judged against. Past cycles use the plain budget
        /// amount — historical carry-forward isn't stored and can't be
        /// reconstructed; the current cycle includes carryForward so it agrees
        /// with budgetProgress and the page header.
        public let base: Double
        public let over: Bool
        public let isCurrent: Bool

        public init(from: String, to: String, fromTime: String? = nil, toTime: String? = nil,
                    used: Double, base: Double, over: Bool, isCurrent: Bool) {
            self.from = from; self.to = to; self.fromTime = fromTime; self.toTime = toTime
            self.used = used; self.base = base; self.over = over; self.isCurrent = isCurrent
        }
    }

    /// The budget's last `cycles` cycle windows (oldest first, ending with the
    /// cycle containing `today`). Empty for one-shot budgets (no cycles) and
    /// when `today` precedes the start date.
    public static func budgetCycleHistory(_ budget: BudgetRow, _ txns: [Tx], _ today: String,
                                          _ categories: [CategoryNode] = [],
                                          cycles: Int = 6) -> [BudgetCyclePoint] {
        guard budget.isRecurring != 0 else { return [] }
        let start = date(budget.startDate), now = date(today)
        guard now >= start else { return [] }

        // Enumerate windows from startDate through the one containing today,
        // keeping only the trailing `cycles` (same guard bound as cycleWindow).
        //
        // A turnover time shifts every boundary in the chart by the same amount it
        // shifts the header's — otherwise the History bars and the current-cycle
        // figure above them are computed from two different rules and disagree.
        // "00:00" reads as untimed, exactly as in `cycleWindow`.
        let turnover: String? = {
            guard let t = budget.startTime, !t.isEmpty, t != "00:00" else { return nil }
            return t
        }()
        var windows: [(from: String, to: String)] = []
        var s = start, guardI = 0
        while s <= now && guardI < 5000 {
            let e = advance(s, budget.frequency)
            windows.append((ymd(s), turnover == nil ? ymd(addDays(e, -1)) : ymd(e)))
            if windows.count > cycles { windows.removeFirst() }
            s = e
            guardI += 1
        }

        let accountSet = budget.accountIds.isEmpty ? nil : Set(budget.accountIds)
        let matchSet = categories.isEmpty ? Set(budget.categoryIds) : expandDescendants(budget.categoryIds, categories)
        let isExpense = budget.type == "expense"

        return windows.enumerated().map { i, w in
            let isCurrent = i == windows.count - 1
            let base = r2(budget.amount + (isCurrent && isExpense ? budget.carryForward : 0))
            let used = r2(usedInWindow(budget, txns, matchSet, accountSet, from: w.from, to: w.to,
                                       fromTime: turnover, toTime: turnover))
            return BudgetCyclePoint(from: w.from, to: w.to, fromTime: turnover, toTime: turnover,
                                    used: used, base: base,
                                    over: isExpense && used > base, isCurrent: isCurrent)
        }
    }
}
