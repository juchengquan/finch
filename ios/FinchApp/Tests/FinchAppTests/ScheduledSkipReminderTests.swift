import XCTest
@testable import FinchApp
import FinchCore

/// Reminders and row captions for skipped and ended scheduled items.
///
/// The planner used to date a reminder from the stored `next_run`, which nothing
/// writes — so it could not know about a skip or an end date. It now dates it from
/// the occurrence the reminder's own Confirm would post, and these pin what that
/// means for each case.
final class ScheduledSkipReminderTests: XCTestCase {
    private let money: (Double) -> String = { String(format: "%.2f", $0) }

    /// Monthly on the 15th from 2026-01-15; Jan–Mar are posted unless a test says otherwise.
    private func gym(skipped: [String]? = nil, endDate: String? = nil,
                     installmentTotal: Int? = nil, installmentPaid: Int? = nil) -> ScheduledTemplate {
        ScheduledTemplate(id: "gym", name: "Gym", type: "expense", amount: 40, frequency: "monthly",
                          dayOfMonth: 15, accountId: "a1", startDate: "2026-01-15", endDate: endDate,
                          nextRun: "", installmentTotal: installmentTotal, installmentPaid: installmentPaid,
                          skippedDates: skipped)
    }
    private func posted(_ dates: [String]) -> [Tx] {
        dates.enumerated().map { i, d in
            Tx(id: "t\(i)", merchant: "Gym", amount: -40, account: "a1", date: d, pending: false,
               ledgerId: "l1", currency: "USD", kind: "expense", sourceTemplateId: "gym", occurrenceDate: d)
        }
    }
    private let paidThroughMarch = ["2026-01-15", "2026-02-15", "2026-03-15"]

    private func reminders(_ t: ScheduledTemplate, txns: [Tx], wallToday: String) -> [PlannedNotification] {
        NotificationPlanner.plan(budgets: [], txns: txns, scheduled: [t], categories: [],
                                 today: wallToday, wallToday: wallToday, ledgerId: "l1",
                                 enabled: [.scheduledDue], money: money, calendar: utc)
            .filter { $0.kind == .scheduledDue }
    }
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func day(_ d: Date?) -> String? {
        d.map { String(format: "%04d-%02d-%02d", utc.component(.year, from: $0),
                       utc.component(.month, from: $0), utc.component(.day, from: $0)) }
    }

    // MARK: reminders

    func test_theReminderIsDatedFromTheRecurrence_notTheStoredNextRun() {
        let out = reminders(gym(), txns: posted(paidThroughMarch), wallToday: "2026-04-01")
        XCTAssertEqual(out.map(\.id), ["scheduled:gym:2026-04-15"],
                       "nextRun is empty, as for every template made in the app — it must still be reminded")
        XCTAssertEqual(day(out.first?.deliverOn), "2026-04-15")
    }

    func test_aSkippedOccurrenceIsNotReminded_theNextOneIs() {
        let out = reminders(gym(skipped: ["2026-04-15"]), txns: posted(paidThroughMarch), wallToday: "2026-04-01")
        XCTAssertEqual(day(out.first?.deliverOn), "2026-05-15", "April is skipped, so the reminder moves to May")
    }

    func test_aSkippedMissedOccurrenceIsNotDueNow() {
        // March was never posted and is past: due now. Skipped, it isn't.
        let missed = reminders(gym(), txns: posted(["2026-01-15", "2026-02-15"]), wallToday: "2026-04-01")
        XCTAssertNil(missed.first?.deliverOn, "a missed occurrence is due now")
        let skipped = reminders(gym(skipped: ["2026-03-15"]), txns: posted(["2026-01-15", "2026-02-15"]),
                                wallToday: "2026-04-01")
        XCTAssertEqual(day(skipped.first?.deliverOn), "2026-04-15")
    }

    func test_anEndedTemplateIsNotReminded() {
        XCTAssertTrue(reminders(gym(endDate: "2026-03-31"), txns: posted(paidThroughMarch), wallToday: "2026-04-01").isEmpty)
        // …nor one whose only remaining occurrence is skipped.
        XCTAssertTrue(reminders(gym(skipped: ["2026-04-15"], endDate: "2026-04-30"),
                                txns: posted(paidThroughMarch), wallToday: "2026-04-01").isEmpty)
    }

    func test_aPaidOffInstallmentPlanIsNotReminded() {
        XCTAssertTrue(reminders(gym(installmentTotal: 3, installmentPaid: 3),
                                txns: posted(paidThroughMarch), wallToday: "2026-04-01").isEmpty)
        XCTAssertEqual(reminders(gym(installmentTotal: 4, installmentPaid: 3),
                                 txns: posted(paidThroughMarch), wallToday: "2026-04-01").count, 1)
    }

    // MARK: captions

    /// `scheduledPostedMap` over `dates`, posted (or, `pending`, waiting in To confirm).
    private func postedMap(_ dates: [String], pending: Bool = false) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: dates.map { ("gym|\($0)", pending) })
    }
    private var paidMap: [String: Bool] { postedMap(paidThroughMarch) }

    func test_cadenceCaption() {
        func text(_ t: ScheduledTemplate) -> String { ScheduledCaption.cadence(t, posted: paidMap, today: "2026-04-01").text }
        XCTAssertEqual(text(gym()), "Monthly · next 2026-04-15")
        XCTAssertEqual(text(gym(skipped: ["2026-04-15"])), "Monthly · next 2026-05-15", "next passes over a skip")
        XCTAssertEqual(text(gym(endDate: "2026-12-31")), "Monthly · next 2026-04-15 · ends 2026-12-31")
        XCTAssertEqual(text(gym(endDate: "2026-03-31")), "Monthly · ended 2026-03-31")
        XCTAssertEqual(text(gym(skipped: ["2026-04-15"], endDate: "2026-04-30")),
                       "Monthly · ends 2026-04-30", "nothing left, but the end date is still ahead")
    }

    // MARK: overdue — the row says the date Post opens

    /// The audit's Spotify: a past occurrence nobody posted. Post catches up
    /// oldest-first (`resumeOccurrence`), so the row must name THAT date, not the
    /// next one ahead — "next Apr 15" over a form dated Mar 15 booked a backdated
    /// duplicate the user never meant.
    func test_aMissedOccurrenceReadsOverdue_withTheDatePostOpens() {
        let posted = postedMap(["2026-01-15", "2026-02-15"])
        let caption = ScheduledCaption.cadence(gym(), posted: posted, today: "2026-04-01")
        XCTAssertEqual(caption.text, "Monthly · overdue 2026-03-15")
        XCTAssertTrue(caption.overdue)
        let postOpens = Selectors.resumeOccurrence(template: gym(), posted: posted, today: "2026-04-01")
        XCTAssertEqual(postOpens, "2026-03-15")
        XCTAssertEqual(scheduledNextRun(gym(), posted: posted, today: "2026-04-01"), postOpens,
                       "the list sorts and groups on the date the row prints")
        // Several missed: the OLDEST, because that is the one Post fills in.
        XCTAssertEqual(ScheduledCaption.cadence(gym(), posted: [:], today: "2026-04-01").text,
                       "Monthly · overdue 2026-01-15")
    }

    /// A skipped occurrence was not missed — the user said "not this one".
    func test_aSkippedPastOccurrenceIsNotOverdue() {
        let caption = ScheduledCaption.cadence(gym(skipped: ["2026-03-15"]),
                                               posted: postedMap(["2026-01-15", "2026-02-15"]), today: "2026-04-01")
        XCTAssertEqual(caption.text, "Monthly · next 2026-04-15")
        XCTAssertFalse(caption.overdue)
    }

    /// Auto-post already added it: waiting in To confirm counts as posted, so the
    /// row moves on rather than nagging about a row that already exists.
    func test_anOccurrenceWaitingInToConfirmIsNotOverdue() {
        let posted = paidMap.merging(postedMap(["2026-04-15"], pending: true)) { a, _ in a }
        let caption = ScheduledCaption.cadence(gym(), posted: posted, today: "2026-04-20")
        XCTAssertEqual(caption.text, "Monthly · next 2026-05-15")
        XCTAssertFalse(caption.overdue)
    }

    /// Due today is due, not overdue — and once posted (even early), "next" moves on
    /// to the occurrence Post would open now.
    func test_dueTodayIsNext_andAPostedOneIsPassedOver() {
        XCTAssertEqual(ScheduledCaption.cadence(gym(), posted: paidMap, today: "2026-04-15").text,
                       "Monthly · next 2026-04-15")
        let early = paidMap.merging(postedMap(["2026-04-15"])) { a, _ in a }
        XCTAssertEqual(ScheduledCaption.cadence(gym(), posted: early, today: "2026-04-10").text,
                       "Monthly · next 2026-05-15")
    }

    /// From the current occurrence on: the one just passed (what a bare Skip can
    /// take while it is nearest) shows; anything older is history.
    func test_skipsCaption_fromTheCurrentOccurrence() {
        XCTAssertNil(ScheduledCaption.skips(gym(), today: "2026-04-01"))
        XCTAssertNil(ScheduledCaption.skips(gym(skipped: ["2026-02-15"]), today: "2026-04-01"), "an older skip is history")
        XCTAssertEqual(ScheduledCaption.skips(gym(skipped: ["2026-03-15"]), today: "2026-03-20"), "Skipping 2026-03-15",
                       "five days on, Mar 15th is still the current occurrence")
        XCTAssertNil(ScheduledCaption.skips(gym(skipped: ["2026-03-15"]), today: "2026-04-01"),
                     "by Apr 1st the current occurrence is Apr 15th")
        XCTAssertEqual(ScheduledCaption.skips(gym(skipped: ["2026-05-15", "2026-02-15", "2026-04-15"]), today: "2026-04-01"),
                       "Skipping 2026-04-15, 2026-05-15")
    }

    func test_shortDayNamesTheYearOnlyWhenItDiffers() {
        XCTAssertFalse(ScheduledCaption.shortDay("2026-04-15", today: "2026-04-01").contains("2026"))
        XCTAssertTrue(ScheduledCaption.shortDay("2025-12-15", today: "2026-04-01").contains("2025"))
    }
}
