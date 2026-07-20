import XCTest
import FinchCore
@testable import FinchApp

final class BudgetSummaryTests: XCTestCase {
    /// Minimal BudgetRow factory — only `type`/`isRecurring` matter to `compute`.
    private func budget(_ id: String, type: String = "expense", isRecurring: Int = 1) -> BudgetRow {
        BudgetRow(id: id, ledgerId: "L", groupId: nil, name: id, type: type, amount: 0, saved: 0,
                  carryForward: 0, frequency: "monthly", startDate: "2026-01-01", endDate: nil,
                  isRecurring: isRecurring, rollover: 0, rolloverLimit: nil, pendingAmount: nil,
                  lastRolledPeriod: nil, accountIds: [], categoryIds: [], warningPct: 80)
    }

    func test_mixed_spend_and_goal_excludes_goal_from_spend() {
        let budgets = [budget("under"), budget("over"), budget("goal", type: "income", isRecurring: 0)]
        let prog: [String: (used: Double, base: Double, over: Bool)] = [
            "under": (71.20, 600, false),
            "over":  (1850, 1500, true),
            "goal":  (650, 2000, false),
        ]
        let s = BudgetSummary.compute(budgets) { prog[$0.id]! }
        XCTAssertEqual(s.spentBase, 1921.20, accuracy: 0.001)
        XCTAssertEqual(s.budgetBase, 2100, accuracy: 0.001)
        XCTAssertEqual(s.remainingBase, 178.80, accuracy: 0.001)
        XCTAssertEqual(s.overCount, 1)
        XCTAssertEqual(s.goalSavedBase, 650, accuracy: 0.001)
        XCTAssertEqual(s.goalTargetBase, 2000, accuracy: 0.001)
        XCTAssertTrue(s.hasSpend)
        XCTAssertTrue(s.hasGoals)
    }

    func test_recurring_income_is_spend_not_goal() {
        // income + recurring is NOT a goal — counts as spend.
        let s = BudgetSummary.compute([budget("inc", type: "income", isRecurring: 1)]) { _ in (500, 1000, false) }
        XCTAssertEqual(s.spentBase, 500, accuracy: 0.001)
        XCTAssertTrue(s.hasSpend)
        XCTAssertFalse(s.hasGoals)
    }

    func test_goals_only() {
        let s = BudgetSummary.compute([budget("g", type: "income", isRecurring: 0)]) { _ in (650, 2000, false) }
        XCTAssertFalse(s.hasSpend)
        XCTAssertTrue(s.hasGoals)
        XCTAssertEqual(s.budgetBase, 0, accuracy: 0.001)
        XCTAssertEqual(s.overCount, 0)
    }

    func test_empty() {
        let s = BudgetSummary.compute([]) { _ in (0, 0, false) }
        XCTAssertFalse(s.hasSpend)
        XCTAssertFalse(s.hasGoals)
        XCTAssertEqual(s.remainingBase, 0, accuracy: 0.001)
    }

    func test_threshold_bands() {
        XCTAssertEqual(BudgetThreshold.color(pct: 50), .green)
        XCTAssertEqual(BudgetThreshold.color(pct: 69), .green)
        XCTAssertEqual(BudgetThreshold.color(pct: 70), .yellow)
        XCTAssertEqual(BudgetThreshold.color(pct: 90), .yellow)
        XCTAssertEqual(BudgetThreshold.color(pct: 91), .red)
    }
}
