import XCTest
import FinchCore
@testable import FinchApp

/// The low-balance alert's planning: which accounts raise one, the day it is
/// announced, and the id that keeps re-planning idempotent. Timing (quiet hours) and
/// the burst cap are `NotificationPolicy`'s and apply to it unchanged.
final class LowBalanceAlertTests: XCTestCase {
    private let money: (Double) -> String = { String(format: "%.2f", $0) }
    private let all = Set(NotificationKind.allCases)
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func account(_ id: String, _ balance: Double, type: String = "cash",
                         active: Bool? = nil) -> AccountRow {
        AccountRow(id: id, balance: balance, currency: "USD", isActive: active, name: "Checking", type: type)
    }
    private func bill(_ amount: Double, day: Int, account: String = "a1") -> ScheduledTemplate {
        ScheduledTemplate(id: "bill-\(account)-\(day)", name: "Rent", type: "expense", amount: amount,
                          frequency: "monthly", dayOfMonth: day, accountId: account,
                          startDate: "2026-05-15", nextRun: "2026-05-\(String(format: "%02d", day))")
    }
    /// A row the bill posted, for its occurrence on `day` of May.
    private func posted(day: Int, on date: String? = nil, pending: Bool, account: String = "a1") -> Tx {
        let occurrence = "2026-05-\(String(format: "%02d", day))"
        return Tx(id: "p-\(day)", merchant: "Rent", amount: -900, account: account, date: date ?? occurrence,
                  pending: pending, currency: "USD", nativeAmount: -900, kind: "expense",
                  sourceTemplateId: "bill-\(account)-\(day)", occurrenceDate: occurrence)
    }

    /// The bills start on the 15th, so none has an occurrence behind it that would
    /// read as missed and land on today.
    private func plan(_ accounts: [AccountRow], _ scheduled: [ScheduledTemplate],
                      wallToday: String = "2026-05-15", txns: [Tx] = [],
                      enabled: Set<NotificationKind>? = nil) -> [PlannedNotification] {
        NotificationPlanner.plan(
            budgets: [], txns: txns, scheduled: scheduled, categories: [], today: wallToday,
            wallToday: wallToday, ledgerId: "l1", enabled: enabled ?? all, money: money,
            calendar: utc, accounts: accounts)
            .filter { $0.kind == .lowBalance }
    }

    func testAFutureDipBelowZeroIsAnnouncedThreeDaysAhead() throws {
        // Below zero on the 25th → announced on the 22nd, at the delivery hour.
        let p = try XCTUnwrap(plan([account("a1", 500)], [bill(900, day: 25)]).first)
        XCTAssertEqual(p.id, "lowBalance:a1:2026-05-25")
        XCTAssertEqual(p.focusId, "a1")
        XCTAssertEqual(p.tab, .accounts)
        let at = try XCTUnwrap(p.deliverOn)
        let c = utc.dateComponents([.year, .month, .day, .hour], from: at)
        XCTAssertEqual([c.year, c.month, c.day, c.hour], [2026, 5, 22, 9])
    }

    func testADipInsideTheLeadIsTrueNow() throws {
        // Below zero on the 17th — the 14th has passed, so it goes as soon as policy
        // allows, carrying no date, like a past-due reminder.
        let p = try XCTUnwrap(plan([account("a1", 500)], [bill(900, day: 17)]).first)
        XCTAssertNil(p.deliverOn)
    }

    func testTheIdFollowsTheCrossingDay() {
        // A bill that pulls the crossing earlier must REPLACE the pending alert, which
        // only a new id does — `toSchedule` never re-adds an id already pending.
        let later = plan([account("a1", 500)], [bill(900, day: 25)]).map(\.id)
        let earlier = plan([account("a1", 500)], [bill(900, day: 25), bill(600, day: 20)]).map(\.id)
        XCTAssertEqual(later, ["lowBalance:a1:2026-05-25"])
        XCTAssertEqual(earlier, ["lowBalance:a1:2026-05-20"])
        XCTAssertEqual(NotificationPlanner.cancelIDs(planned: plan([account("a1", 500)],
                                                                   [bill(900, day: 25), bill(600, day: 20)]),
                                                     existing: Set(later)),
                       later, "the too-late alert is cancelled")
    }

    func testNoAlertWhenTheBalanceStaysAboveZero() {
        XCTAssertTrue(plan([account("a1", 1000)], [bill(900, day: 25)]).isEmpty)
    }

    func testNoAlertForAnAccountAlreadyBelowZero() {
        // The present, not a forecast — and keyed on today it would re-fire every day.
        XCTAssertTrue(plan([account("a1", -10)], [bill(100, day: 25)]).isEmpty)
    }

    func testNoAlertForACreditCard() {
        XCTAssertTrue(plan([account("a1", 0, type: "credit_card")], [bill(40, day: 25)]).isEmpty)
    }

    func testNoAlertForAnArchivedAccount() {
        XCTAssertTrue(plan([account("a1", 500, active: false)], [bill(900, day: 25)]).isEmpty)
    }

    func testTheToggleTurnsItOff() {
        XCTAssertTrue(plan([account("a1", 500)], [bill(900, day: 25)],
                           enabled: all.subtracting([.lowBalance])).isEmpty)
    }

    func testOneAlertPerAccount() {
        let ids = plan([account("a1", 500), account("a2", 500)],
                       [bill(900, day: 25), bill(900, day: 28, account: "a2")]).map(\.id)
        XCTAssertEqual(ids, ["lowBalance:a1:2026-05-25", "lowBalance:a2:2026-05-28"])
    }

    func testTheBodyUsesTheAccountFormatter() throws {
        // `accountMoney` gets the account's currency — the forecast is in it — and is
        // what masks the amount in privacy mode.
        var seen: [String?] = []
        let planned = NotificationPlanner.plan(
            budgets: [], txns: [], scheduled: [bill(900, day: 25)], categories: [], today: "2026-05-15",
            wallToday: "2026-05-15", ledgerId: "l1", enabled: [.lowBalance], money: money, calendar: utc,
            accounts: [account("a1", 500)],
            accountMoney: { _, currency in seen.append(currency); return "••••" })
        let body = try XCTUnwrap(planned.first?.body)
        XCTAssertEqual(seen, ["USD"])
        XCTAssertTrue(body.contains("••••"))
        XCTAssertFalse(body.contains("400"), "no unmasked figure may leak into the body")
    }

    // MARK: what was posted, and what is owed now

    func testABillPaidEarlyRaisesNoAlert() {
        // A2: 1000, rent 900 paid on the 15th for the 25th — the balance is 100 and
        // stays there. Counted again on the 25th, it read as −800.
        XCTAssertTrue(plan([account("a1", 100)], [bill(900, day: 25)],
                           txns: [posted(day: 25, on: "2026-05-15", pending: false)]).isEmpty)
    }

    func testAPendingBillOnItsDueDayStillAlerts() throws {
        // A3: the 25th, auto-post added the rent as a pending row. It is not in the
        // balance; the alert must not vanish with it. True now, so no date.
        let p = try XCTUnwrap(plan([account("a1", 500)], [bill(900, day: 25)], wallToday: "2026-05-25",
                                   txns: [posted(day: 25, pending: true)]).first)
        XCTAssertEqual(p.id, "lowBalance:a1:2026-05-25")
        XCTAssertNil(p.deliverOn)
    }

    func testAnUnpaidBillKeepsOneAlertFromDayToDay() {
        // Still pending two days later: the same id, so it is not raised again.
        let onTheDay = plan([account("a1", 500)], [bill(900, day: 25)], wallToday: "2026-05-25",
                            txns: [posted(day: 25, pending: true)]).map(\.id)
        let later = plan([account("a1", 500)], [bill(900, day: 25)], wallToday: "2026-05-27",
                         txns: [posted(day: 25, pending: true)]).map(\.id)
        // Pinned, not just equal: with no alert on either day, [] == [] passed.
        XCTAssertEqual(onTheDay, ["lowBalance:a1:2026-05-25"])
        XCTAssertEqual(later, onTheDay)
    }

    func testAMissedBillAlertsToday() throws {
        // Posted by hand and not posted: overdue on the 27th, still owed.
        let p = try XCTUnwrap(plan([account("a1", 500)], [bill(900, day: 25)], wallToday: "2026-05-27").first)
        XCTAssertEqual(p.id, "lowBalance:a1:2026-05-25")
    }
}
