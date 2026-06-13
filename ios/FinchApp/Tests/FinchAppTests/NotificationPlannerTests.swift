import XCTest
@testable import FinchApp
import FinchCore

/// Phase 6.2 — the pure notification planner (the tested decision core; the
/// UNUserNotificationCenter glue is a thin untested shell over it).
final class NotificationPlannerTests: XCTestCase {
    private let money: (Double) -> String = { String(format: "%.2f", $0) }
    private let all = Set(NotificationKind.allCases)

    private func budget(id: String, cat: String, amount: Double, warn: Double = 80) -> BudgetRow {
        BudgetRow(id: id, ledgerId: "l1", groupId: nil, name: "Food", type: "expense",
                  amount: amount, saved: 0, carryForward: 0, frequency: "monthly",
                  startDate: "2026-01-01", endDate: nil, isRecurring: 1, rollover: 0,
                  rolloverLimit: nil, pendingAmount: nil, lastRolledPeriod: nil,
                  accountIds: [], categoryIds: [cat], warningPct: warn)
    }
    private func expense(_ id: String, _ amount: Double, cat: String, date: String, merchant: String = "Shop") -> Tx {
        Tx(id: id, merchant: merchant, category: cat, amount: amount, account: "a1", date: date,
           pending: false, ledgerId: "l1", currency: "USD", nativeAmount: amount, kind: "expense")
    }

    /// A budget past its warning % yields one budgetWarning; under it yields none.
    func test_budgetWarningThreshold() {
        let b = budget(id: "b1", cat: "food", amount: 100, warn: 80)
        let txns = [expense("t1", -90, cat: "food", date: "2026-05-10")]   // 90% > 80%
        let warned = NotificationPlanner.plan(
            budgets: [b], txns: txns, scheduled: [], categories: [], today: "2026-05-15",
            ledgerId: "l1", enabled: all, money: money)
        XCTAssertEqual(warned.filter { $0.kind == .budgetWarning }.map(\.focusId), ["b1"])

        let under = NotificationPlanner.plan(
            budgets: [budget(id: "b1", cat: "food", amount: 100, warn: 95)], txns: txns,
            scheduled: [], categories: [], today: "2026-05-15", ledgerId: "l1", enabled: all, money: money)
        XCTAssertTrue(under.filter { $0.kind == .budgetWarning }.isEmpty)
    }

    /// A scheduled template whose nextRun is today/past is flagged due.
    func test_scheduledDue() {
        let due = ScheduledTemplate(id: "s1", name: "Rent", type: "expense", amount: 1500,
            frequency: "monthly", dayOfMonth: 1, accountId: "a1", nextRun: "2026-05-01")
        let future = ScheduledTemplate(id: "s2", name: "Gym", type: "expense", amount: 30,
            frequency: "monthly", dayOfMonth: 20, accountId: "a1", nextRun: "2026-06-20")
        let planned = NotificationPlanner.plan(
            budgets: [], txns: [], scheduled: [due, future], categories: [], today: "2026-05-15",
            ledgerId: "l1", enabled: all, money: money)
        XCTAssertEqual(planned.filter { $0.kind == .scheduledDue }.map(\.focusId), ["s1"])
    }

    /// Disabling a kind suppresses it.
    func test_enabledFilter() {
        let b = budget(id: "b1", cat: "food", amount: 100)
        let txns = [expense("t1", -95, cat: "food", date: "2026-05-10")]
        let planned = NotificationPlanner.plan(
            budgets: [b], txns: txns, scheduled: [], categories: [], today: "2026-05-15",
            ledgerId: "l1", enabled: [], money: money)
        XCTAssertTrue(planned.isEmpty)
    }

    /// Plan ids are stable + unique (so re-planning replaces, never duplicates).
    func test_stableUniqueIds() {
        let b = budget(id: "b1", cat: "food", amount: 100)
        let txns = [expense("t1", -90, cat: "food", date: "2026-05-10")]
        let a = NotificationPlanner.plan(budgets: [b], txns: txns, scheduled: [], categories: [],
            today: "2026-05-15", ledgerId: "l1", enabled: all, money: money)
        let b2 = NotificationPlanner.plan(budgets: [b], txns: txns, scheduled: [], categories: [],
            today: "2026-05-15", ledgerId: "l1", enabled: all, money: money)
        XCTAssertEqual(a.map(\.id), b2.map(\.id))                       // stable
        XCTAssertEqual(Set(a.map(\.id)).count, a.count)                 // unique
    }
}
