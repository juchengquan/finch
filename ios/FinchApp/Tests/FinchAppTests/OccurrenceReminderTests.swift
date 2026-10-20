import XCTest
@testable import FinchApp
import FinchCore

/// A scheduled reminder is about ONE occurrence, over many refreshes.
///
/// The id used to be `scheduled:<templateId>`, the same for every occurrence. A
/// re-plan never replaces a pending request whose id it still plans, and `fired`
/// only forgot ids that left the plan, which a recurring item never does. So the
/// first reminder was the last, and a reminder planned for a skipped or early-paid
/// occurrence still fired. These drive the planner through the same bookkeeping
/// `NotificationService.refresh` does, against a fake notification centre.
final class OccurrenceReminderTests: XCTestCase {
    private let money: (Double) -> String = { String(format: "%.2f", $0) }
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }

    /// Monthly on the 15th from 2026-09-15.
    private func gym(skipped: [String]? = nil) -> ScheduledTemplate {
        ScheduledTemplate(id: "gym", name: "Gym", type: "expense", amount: 40, frequency: "monthly",
                          dayOfMonth: 15, accountId: "a1", startDate: "2026-09-15", nextRun: "",
                          skippedDates: skipped)
    }
    private func paid(_ occurrences: [String]) -> [Tx] {
        occurrences.enumerated().map { i, d in
            Tx(id: "t\(i)", merchant: "Gym", amount: -40, account: "a1", date: d, pending: false,
               ledgerId: "l1", currency: "USD", kind: "expense", sourceTemplateId: "gym", occurrenceDate: d)
        }
    }

    /// The notification centre and the durable records, as `refresh` leaves them.
    private struct Device {
        var pending: [String: Date?] = [:]   // id → deliverOn (nil: "now")
        var delivered: Set<String> = []
        var fired: Set<String> = []
        var shown: [String] = []             // every delivery, in order
    }

    /// One `NotificationService.refresh`, then iOS delivering whatever is due by `wallToday`.
    private func refresh(_ d: inout Device, _ t: ScheduledTemplate?, txns: [Tx], wallToday: String) {
        let planned = NotificationPlanner.plan(
            budgets: [], txns: txns, scheduled: t.map { [$0] } ?? [], categories: [],
            today: wallToday, wallToday: wallToday, ledgerId: "l1",
            enabled: [.scheduledDue], money: money, calendar: utc)
        let decision = NotificationPlanner.reconcile(
            planned: planned, pending: Set(d.pending.keys), delivered: d.delivered,
            fired: d.fired, snoozedUntil: [:], now: Date.distantPast,
            templateIds: Set(t.map { [$0.id] } ?? []), wallToday: wallToday)
        for id in decision.cancelPending { d.pending[id] = nil }
        d.delivered.subtract(decision.cancelDelivered)
        d.fired = decision.fired
        for p in decision.schedule {
            d.pending[p.id] = p.deliverOn
            d.fired.insert(p.id)
        }
        // iOS hands over whatever has come due.
        let end = NotificationPlanner.deliverAt(wallToday, hour: 23, utc)!
        for (id, at) in d.pending where (at ?? .distantPast) <= end {
            d.pending[id] = nil
            d.delivered.insert(id)
            d.shown.append(id)
        }
    }

    // MARK: every occurrence is reminded, once

    func test_eachOccurrenceIsReminded_onceEach() {
        var d = Device()
        refresh(&d, gym(), txns: paid(["2026-09-15"]), wallToday: "2026-10-01")
        XCTAssertEqual(Array(d.pending.keys), ["scheduled:gym:2026-10-15"], "October's, dated")
        refresh(&d, gym(), txns: paid(["2026-09-15"]), wallToday: "2026-10-15")
        XCTAssertEqual(d.shown, ["scheduled:gym:2026-10-15"])
        // Re-planned all day, it is not shown again.
        refresh(&d, gym(), txns: paid(["2026-09-15"]), wallToday: "2026-10-15")
        XCTAssertEqual(d.shown.count, 1)
        // …nor once dismissed: `fired` remembers it.
        d.delivered = []
        refresh(&d, gym(), txns: paid(["2026-09-15"]), wallToday: "2026-10-16")
        XCTAssertEqual(d.shown.count, 1, "dismissing an overdue reminder must not revive it")

        // Paid: November's is planned — the bug was that it never was.
        refresh(&d, gym(), txns: paid(["2026-09-15", "2026-10-15"]), wallToday: "2026-10-16")
        XCTAssertEqual(Array(d.pending.keys), ["scheduled:gym:2026-11-15"])
        refresh(&d, gym(), txns: paid(["2026-09-15", "2026-10-15"]), wallToday: "2026-11-15")
        XCTAssertEqual(d.shown, ["scheduled:gym:2026-10-15", "scheduled:gym:2026-11-15"])
    }

    // MARK: the pending request follows the occurrence

    func test_skippingTheOccurrence_movesTheReminderToTheNextOne() {
        var d = Device()
        refresh(&d, gym(), txns: paid(["2026-09-15", "2026-10-15"]), wallToday: "2026-11-01")
        XCTAssertEqual(Array(d.pending.keys), ["scheduled:gym:2026-11-15"])
        refresh(&d, gym(skipped: ["2026-11-15"]), txns: paid(["2026-09-15", "2026-10-15"]), wallToday: "2026-11-02")
        XCTAssertEqual(Array(d.pending.keys), ["scheduled:gym:2026-12-15"], "November's request is withdrawn")
        refresh(&d, gym(skipped: ["2026-11-15"]), txns: paid(["2026-09-15", "2026-10-15"]), wallToday: "2026-11-15")
        XCTAssertTrue(d.shown.isEmpty, "nothing fires for a skipped occurrence")
        // Un-skipped, it is reminded after all — its earlier scheduling is forgotten.
        refresh(&d, gym(), txns: paid(["2026-09-15", "2026-10-15"]), wallToday: "2026-11-15")
        XCTAssertEqual(d.shown, ["scheduled:gym:2026-11-15"])
    }

    func test_payingEarly_withdrawsThatReminder() {
        var d = Device()
        refresh(&d, gym(), txns: paid(["2026-09-15", "2026-10-15"]), wallToday: "2026-11-01")
        let early = paid(["2026-09-15", "2026-10-15", "2026-11-15"])
        refresh(&d, gym(), txns: early, wallToday: "2026-11-10")
        XCTAssertEqual(Array(d.pending.keys), ["scheduled:gym:2026-12-15"])
        refresh(&d, gym(), txns: early, wallToday: "2026-11-15")
        XCTAssertTrue(d.shown.isEmpty, "the paid occurrence's reminder must not still fire")
    }

    func test_movingTheDay_movesTheReminder() {
        var d = Device()
        refresh(&d, gym(), txns: paid(["2026-09-15", "2026-10-15"]), wallToday: "2026-11-01")
        // Edited to the 20th from November on.
        let moved = ScheduledTemplate(id: "gym", name: "Gym", type: "expense", amount: 40, frequency: "monthly",
                                      dayOfMonth: 20, accountId: "a1", startDate: "2026-11-01", nextRun: "")
        refresh(&d, moved, txns: paid(["2026-09-15", "2026-10-15"]), wallToday: "2026-11-02")
        XCTAssertEqual(Array(d.pending.keys), ["scheduled:gym:2026-11-20"])
    }

    func test_deletingTheTemplate_withdrawsItsReminder_andForgetsIt() {
        var d = Device()
        refresh(&d, gym(), txns: paid(["2026-09-15"]), wallToday: "2026-10-15")
        XCTAssertFalse(d.fired.isEmpty)
        refresh(&d, nil, txns: [], wallToday: "2026-10-16")
        XCTAssertTrue(d.pending.isEmpty)
        XCTAssertTrue(d.delivered.isEmpty, "the delivered one leaves Notification Center too")
        XCTAssertTrue(d.fired.isEmpty)
    }

    // MARK: undo, and the size of `fired`

    /// Paid, then undone: that occurrence is due again, but the user has already been
    /// told about it — it must not fire a second time seconds after the undo.
    func test_undoingAPayment_doesNotRefireItsReminder() {
        var d = Device()
        refresh(&d, gym(), txns: paid(["2026-09-15"]), wallToday: "2026-10-15")
        refresh(&d, gym(), txns: paid(["2026-09-15", "2026-10-15"]), wallToday: "2026-10-15")
        refresh(&d, gym(), txns: paid(["2026-09-15"]), wallToday: "2026-10-15")
        XCTAssertEqual(d.shown, ["scheduled:gym:2026-10-15"])
    }

    /// A year of monthly reminders leaves at most the last one shown and the one planned.
    func test_firedStaysBounded() {
        var d = Device()
        var dates = ["2026-09-15"]
        for month in 10...12 {
            let day = "2026-\(month)-15"
            refresh(&d, gym(), txns: paid(dates), wallToday: day)
            dates.append(day)
        }
        refresh(&d, gym(), txns: paid(dates), wallToday: "2026-12-16")
        XCTAssertEqual(d.shown.count, 3)
        XCTAssertEqual(d.fired, ["scheduled:gym:2026-12-15", "scheduled:gym:2027-01-15"])
    }

    // MARK: migration

    /// A reminder scheduled by the previous build has no date. The first refresh
    /// withdraws it — pending or delivered — and forgets it.
    func test_anUndatedReminder_isWithdrawnOnTheFirstRefresh() {
        var d = Device()
        d.pending = ["scheduled:gym": NotificationPlanner.deliverAt("2026-11-15", hour: 9, utc)]
        d.delivered = ["scheduled:other"]
        d.fired = ["scheduled:gym", "scheduled:other"]
        refresh(&d, gym(), txns: paid(["2026-09-15", "2026-10-15"]), wallToday: "2026-11-01")
        XCTAssertEqual(Array(d.pending.keys), ["scheduled:gym:2026-11-15"])
        XCTAssertTrue(d.delivered.isEmpty)
        XCTAssertEqual(d.fired, ["scheduled:gym:2026-11-15"])
    }

    // MARK: the reminder names its occurrence

    func test_theReminderCarriesItsOccurrence() {
        let out = NotificationPlanner.plan(
            budgets: [], txns: paid(["2026-09-15"]), scheduled: [gym()], categories: [],
            today: "2026-10-20", wallToday: "2026-10-20", ledgerId: "l1",
            enabled: [.scheduledDue], money: money, calendar: utc)
        XCTAssertEqual(out.first?.occurrence, "2026-10-15")
        XCTAssertNil(out.first?.deliverOn, "past due is due now")
        XCTAssertEqual(NotificationPlanner.scheduledOccurrence(fromId: "scheduled:gym:2026-10-15")?.templateId, "gym")
        XCTAssertNil(NotificationPlanner.scheduledOccurrence(fromId: "scheduled:gym"), "the undated legacy id")
        XCTAssertNil(NotificationPlanner.scheduledOccurrence(fromId: "lowBalance:a1:2026-10-15"))
    }
}
