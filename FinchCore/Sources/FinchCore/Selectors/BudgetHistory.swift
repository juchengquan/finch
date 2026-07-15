import Foundation

// Budget cycle history — spent vs budget across the trailing cycles, for the
// budget detail page's History chart ("do I chronically bust this budget?").
// iOS-original (no web counterpart yet).
extension Selectors {
    public struct BudgetCyclePoint: Equatable, Sendable {
        /// Cycle bounds (YYYY-MM-DD, inclusive).
        public let from: String
        public let to: String
        /// Budget-matched activity in the cycle (same predicate as budgetProgress).
        public let used: Double
        /// The cap the cycle is judged against. Past cycles use the plain budget
        /// amount — historical carry-forward isn't stored and can't be
        /// reconstructed; the current cycle includes carryForward so it agrees
        /// with budgetProgress and the page header.
        public let base: Double
        public let over: Bool
        public let isCurrent: Bool
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
        var windows: [(from: String, to: String)] = []
        var s = start, guardI = 0
        while s <= now && guardI < 5000 {
            let e = advance(s, budget.frequency)
            windows.append((ymd(s), ymd(addDays(e, -1))))
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
            let used = r2(usedInWindow(budget, txns, matchSet, accountSet, from: w.from, to: w.to))
            return BudgetCyclePoint(from: w.from, to: w.to, used: used, base: base,
                                    over: isExpense && used > base, isCurrent: isCurrent)
        }
    }
}
