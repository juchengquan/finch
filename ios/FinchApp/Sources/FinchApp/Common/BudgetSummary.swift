import SwiftUI
import FinchCore

/// Ledger-wide budget health, split into spend vs. savings-goal totals. Pure and
/// unit-tested — `progress` is injected (the store passes `Selectors.budgetProgress`)
/// so this has no store/engine dependency. A budget is a GOAL when
/// `type == "income" && isRecurring == 0`; everything else is a SPEND budget.
struct BudgetSummary: Equatable {
    var spentBase: Double        // Σ used over spend budgets
    var budgetBase: Double       // Σ base over spend budgets
    var remainingBase: Double    // budgetBase − spentBase (negative when overspent)
    var overCount: Int           // # spend budgets currently over budget
    var goalSavedBase: Double    // Σ used (= saved) over goal budgets
    var goalTargetBase: Double   // Σ base (= target) over goal budgets
    var hasGoals: Bool
    var hasSpend: Bool

    static func compute(_ budgets: [BudgetRow],
                        progress: (BudgetRow) -> (used: Double, base: Double, over: Bool)) -> BudgetSummary {
        var spent = 0.0, budget = 0.0, overCount = 0
        var goalSaved = 0.0, goalTarget = 0.0
        var hasSpend = false, hasGoals = false
        for b in budgets {
            let p = progress(b)
            if b.type == "income" && b.isRecurring == 0 {      // goal
                hasGoals = true
                goalSaved += p.used
                goalTarget += p.base
            } else {                                           // spend
                hasSpend = true
                spent += p.used
                budget += p.base
                if p.over { overCount += 1 }
            }
        }
        return BudgetSummary(spentBase: spent, budgetBase: budget, remainingBase: budget - spent,
                             overCount: overCount, goalSavedBase: goalSaved, goalTargetBase: goalTarget,
                             hasGoals: hasGoals, hasSpend: hasSpend)
    }
}

/// The 3-color budget banding, shared by the summary bar and the rows so they agree.
/// pct is an INTEGER 0–100 (as `BudgetProgress.pct`): green < 70, yellow 70–90, red > 90.
enum BudgetThreshold {
    static func color(pct: Int) -> Color {
        pct > 90 ? .red : (pct >= 70 ? .yellow : .green)
    }
}
