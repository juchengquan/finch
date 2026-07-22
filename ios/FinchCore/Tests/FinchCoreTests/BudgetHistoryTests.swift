import XCTest
@testable import FinchCore

final class BudgetHistoryTests: XCTestCase {
    private func budget(amount: Double = 100, frequency: String = "monthly",
                        startDate: String = "2026-03-01", isRecurring: Int = 1,
                        carryForward: Double = 0, accountIds: [String] = [],
                        type: String = "expense") -> BudgetRow {
        BudgetRow(id: "b1", ledgerId: "l1", groupId: nil, name: "Food", type: type,
                  amount: amount, saved: 0, carryForward: carryForward, frequency: frequency,
                  startDate: startDate, endDate: nil, isRecurring: isRecurring, rollover: 0,
                  rolloverLimit: nil, pendingAmount: nil, lastRolledPeriod: nil,
                  accountIds: accountIds, categoryIds: ["food"], warningPct: 80)
    }
    private func tx(_ id: String, _ amount: Double, _ date: String,
                    cat: String = "food", acct: String = "a1") -> Tx {
        Tx(id: id, merchant: "m", category: cat, amount: amount, account: acct, date: date,
           pending: false, ledgerId: "l1", kind: "expense")
    }

    func test_monthlyWalk_orderUsedOverAndCurrent() {
        let txns = [
            tx("1", -50, "2026-03-10"),    // cycle 1: 50 (under)
            tx("2", -120, "2026-04-05"),   // cycle 2: 120 (over)
            tx("3", -10, "2026-05-02"),    // cycle 3 (current): 10
        ]
        let pts = Selectors.budgetCycleHistory(budget(), txns, "2026-05-15")
        XCTAssertEqual(pts.count, 3)
        XCTAssertEqual(pts.map(\.from), ["2026-03-01", "2026-04-01", "2026-05-01"])
        XCTAssertEqual(pts.map(\.used), [50, 120, 10])
        XCTAssertEqual(pts.map(\.over), [false, true, false])
        XCTAssertEqual(pts.map(\.isCurrent), [false, false, true])
        XCTAssertEqual(pts[0].to, "2026-03-31")
    }

    func test_weeklyWindowsStepBySevenDays() {
        let pts = Selectors.budgetCycleHistory(
            budget(frequency: "weekly", startDate: "2026-06-01"), [tx("1", -5, "2026-06-02")], "2026-06-16")
        XCTAssertEqual(pts.map(\.from), ["2026-06-01", "2026-06-08", "2026-06-15"])
        XCTAssertEqual(pts[0].to, "2026-06-07")
        XCTAssertEqual(pts.map(\.used), [5, 0, 0])
    }

    func test_capsAtCyclesKeepingLatest() {
        let pts = Selectors.budgetCycleHistory(budget(startDate: "2025-01-01"), [], "2026-05-15", cycles: 6)
        XCTAssertEqual(pts.count, 6)
        XCTAssertEqual(pts.last!.from, "2026-05-01")   // newest kept, oldest dropped
        XCTAssertEqual(pts.first!.from, "2025-12-01")
    }

    func test_accountFilterRespected() {
        let b = budget(accountIds: ["a1"])
        let txns = [tx("1", -40, "2026-03-05", acct: "a1"), tx("2", -99, "2026-03-06", acct: "a2")]
        let pts = Selectors.budgetCycleHistory(b, txns, "2026-03-20")
        XCTAssertEqual(pts.map(\.used), [40])   // a2 txn excluded
    }

    func test_oneShotAndFutureStartReturnEmpty() {
        XCTAssertTrue(Selectors.budgetCycleHistory(budget(isRecurring: 0), [], "2026-05-15").isEmpty)
        XCTAssertTrue(Selectors.budgetCycleHistory(budget(startDate: "2026-09-01"), [], "2026-05-15").isEmpty)
    }

    func test_currentBaseIncludesCarryForward_pastIsPlainAmount() {
        let pts = Selectors.budgetCycleHistory(budget(carryForward: 25), [], "2026-04-10")
        XCTAssertEqual(pts.count, 2)
        XCTAssertEqual(pts[0].base, 100)    // past: plain amount
        XCTAssertEqual(pts[1].base, 125)    // current: amount + carryForward (expense)
    }
    func test_windowedMatchedTransactions_pastCycle() {
        let txns = [
            tx("1", -50, "2026-03-10"),
            tx("2", -120, "2026-04-05"),
            tx("3", -10, "2026-05-02"),
        ]
        // Explicit window pulls the past cycle's transactions...
        XCTAssertEqual(Selectors.budgetMatchedTransactions(budget(), txns, from: "2026-04-01", to: "2026-04-30").map(\.id), ["2"])
        // ...while the today-based variant (which now delegates to it) still
        // returns only the current cycle.
        XCTAssertEqual(Selectors.budgetMatchedTransactions(budget(), txns, "2026-05-15").map(\.id), ["3"])
    }
}
