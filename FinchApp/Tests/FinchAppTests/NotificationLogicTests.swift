import XCTest
@testable import FinchApp
import FinchCore

/// Regression cover for four notification-logic bugs fixed together.
final class NotificationLogicTests: XCTestCase {
    private let money: (Double) -> String = { String(format: "%.2f", $0) }
    private let all = Set(NotificationKind.allCases)

    private func template(_ id: String, nextRun: String) -> ScheduledTemplate {
        ScheduledTemplate(id: id, name: "Rent", type: "expense", amount: 100,
                          frequency: "monthly", dayOfMonth: 1, accountId: "a1", nextRun: nextRun)
    }
    private func plan(today: String, wallToday: String, scheduled: [ScheduledTemplate]) -> [PlannedNotification] {
        NotificationPlanner.plan(budgets: [], txns: [], scheduled: scheduled, categories: [],
                                 today: today, wallToday: wallToday, ledgerId: "l1",
                                 enabled: all, money: money)
    }

    // MARK: 1 — due-ness follows the WALL clock, not the last transaction

    /// The bug: `today` is data-anchored (max tx date). A reminder due today never
    /// fired until the user recorded a transaction dated on/after it — so the alert
    /// meant to PROMPT the recording only arrived once it was already done.
    func test_dueUsesWallClock_notTheLastTransactionDate() {
        // last recorded transaction was a week ago; the item is due today
        let out = plan(today: "2026-05-08", wallToday: "2026-05-15",
                       scheduled: [template("s1", nextRun: "2026-05-15")])
        XCTAssertEqual(out.map(\.id), ["scheduled:s1"], "due today must fire even with stale data")
    }

    /// …and the converse still holds: not yet due stays quiet even if the data
    /// anchor has run ahead.
    func test_notYetDueStaysQuiet() {
        let out = plan(today: "2026-05-20", wallToday: "2026-05-15",
                       scheduled: [template("s1", nextRun: "2026-05-18")])
        XCTAssertTrue(out.isEmpty)
    }

    // MARK: 2 — dismissing an alert keeps it dismissed

    func test_alreadyFiredIsNotRescheduledAfterDismissal() {
        let p = PlannedNotification(id: "budget:b1", kind: .budgetWarning, title: "t", body: "b",
                                    tab: .budgets, focusId: "b1")
        // dismissed => gone from BOTH pending and delivered; only `fired` remembers it
        let out = NotificationPlanner.toSchedule(planned: [p], existing: [], fired: ["budget:b1"],
                                                 snoozedUntil: [:], now: Date())
        XCTAssertTrue(out.isEmpty, "a dismissed alert must not come back on the next write")
    }

    /// But once the condition resolves the memory is dropped, so a later
    /// recurrence alerts again rather than being silenced forever.
    func test_firedIsForgottenWhenConditionResolves() {
        let stillPlanned = NotificationPlanner.retainedFired(["budget:b1", "budget:b2"],
                                                             planned: [])
        XCTAssertTrue(stillPlanned.isEmpty)
    }

    // MARK: 3 — snooze actually suppresses for its window

    func test_snoozeSuppressesUntilDeadlineThenReturns() {
        let p = PlannedNotification(id: "scheduled:s1", kind: .scheduledDue, title: "t", body: "b",
                                    tab: .scheduled, focusId: "s1")
        let now = Date()
        let deadline = now.addingTimeInterval(NotificationService.snoozeInterval)

        let during = NotificationPlanner.toSchedule(planned: [p], existing: [], fired: [],
                                                    snoozedUntil: ["scheduled:s1": deadline], now: now)
        XCTAssertTrue(during.isEmpty, "must stay quiet inside the snooze window")

        let after = NotificationPlanner.toSchedule(planned: [p], existing: [], fired: [],
                                                   snoozedUntil: ["scheduled:s1": deadline],
                                                   now: deadline.addingTimeInterval(1))
        XCTAssertEqual(after.map(\.id), ["scheduled:s1"], "must return once the hour is up")
    }

    func test_snoozeIsAFullHour() {
        XCTAssertEqual(NotificationService.snoozeInterval, 3600, "the button says 1 hour")
    }

    // MARK: 4 — pending/delivered suppression still applies

    func test_pendingOrDeliveredIsNotDoubleScheduled() {
        let p = PlannedNotification(id: "anomaly:t1", kind: .anomaly, title: "t", body: "b",
                                    tab: .activity, focusId: "t1")
        XCTAssertTrue(NotificationPlanner.toSchedule(planned: [p], existing: ["anomaly:t1"],
                                                     fired: [], snoozedUntil: [:], now: Date()).isEmpty)
    }
}
