import XCTest
import FinchCore
@testable import FinchApp

/// The account-screen forecast model, shared by both account screens and the
/// low-balance alert. The projection itself is `Selectors.accountForecast`, parity-
/// tested in FinchCore; these cover what the app layer decides ON TOP of it — when the
/// panel shows, when it warns, and which day the alert is about.
final class AccountForecastPanelTests: XCTestCase {

    private func account(_ balance: Double, type: String = "cash") -> AccountRow {
        AccountRow(id: "a1", balance: balance, currency: "USD", name: "Checking", type: type)
    }
    private func monthly(_ id: String, _ type: String, _ amount: Double, day: Int,
                         account: String = "a1", from: String? = nil) -> ScheduledTemplate {
        ScheduledTemplate(id: id, name: id, type: type, amount: amount, frequency: "monthly",
                          dayOfMonth: day, accountId: account, fromAccountId: from,
                          startDate: "2026-05-15", nextRun: "2026-05-\(String(format: "%02d", day))")
    }
    /// The panel over no posted or pending rows. The items start today, so none has an
    /// occurrence already behind it that would read as missed.
    private func make(account: AccountRow, scheduled: [ScheduledTemplate], today: String,
                      txns: [Tx] = []) -> AccountForecastPanel? {
        AccountForecastPanel.make(account: account, scheduled: scheduled, today: today,
                                  activity: AccountForecastPanel.activity(txns: txns, accounts: [account], convert: nil))
    }

    // MARK: visibility

    func testHiddenWhenNothingScheduledTouchesTheAccount() {
        // A bill on ANOTHER account is not this account's forecast.
        let other = monthly("rent", "expense", 900, day: 20, account: "a2")
        XCTAssertNil(make(account: account(500), scheduled: [other], today: "2026-05-15"))
        XCTAssertNil(make(account: account(500), scheduled: [], today: "2026-05-15"))
    }

    func testHiddenForAVariableAmountItem() {
        // No amount, nothing to project — the selector skips it, so there is no line.
        let variable = ScheduledTemplate(id: "v", name: "Power", type: "expense", amount: nil,
                                         frequency: "monthly", dayOfMonth: 20, accountId: "a1",
                                         startDate: "2026-05-15", nextRun: "2026-05-20")
        XCTAssertNil(make(account: account(500), scheduled: [variable], today: "2026-05-15"))
    }

    func testShownForTheSourceLegOfATransfer() {
        let out = monthly("save", "transfer", 200, day: 20, account: "a2", from: "a1")
        let panel = make(account: account(500), scheduled: [out], today: "2026-05-15")
        XCTAssertEqual(panel?.endingBalance, 300)
    }

    // MARK: warning

    func testCrossingBelowZeroWarnsAndNamesTheFirstNegativeDay() throws {
        // 500 → rent 900 on the 20th (−400) → pay 1000 on the 1st (+600). The low point
        // and the crossing are the same day here; the line recovers after it.
        let panel = try XCTUnwrap(make(
            account: account(500),
            scheduled: [monthly("rent", "expense", 900, day: 20), monthly("pay", "income", 1000, day: 1)],
            today: "2026-05-15"))
        XCTAssertTrue(panel.warns)
        XCTAssertTrue(panel.dips)
        XCTAssertEqual(panel.crossesBelowZeroOn, "2026-05-20")
        XCTAssertEqual(panel.low.date, "2026-05-20")
        XCTAssertEqual(panel.low.balance, -400)
        XCTAssertEqual(panel.endingBalance, 600)
    }

    func testTheCrossingIsEarlierThanTheLowPointWhenTheBalanceKeepsFalling() throws {
        // Below zero on the 20th, lower still on the 25th — the alert is about the 20th.
        let panel = try XCTUnwrap(make(
            account: account(100),
            scheduled: [monthly("gym", "expense", 150, day: 20), monthly("rent", "expense", 300, day: 25)],
            today: "2026-05-15"))
        XCTAssertEqual(panel.crossesBelowZeroOn, "2026-05-20")
        XCTAssertEqual(panel.low.date, "2026-05-25")
    }

    func testADipThatStaysAboveZeroDoesNotWarn() throws {
        let panel = try XCTUnwrap(make(
            account: account(1000), scheduled: [monthly("rent", "expense", 900, day: 20)], today: "2026-05-15"))
        XCTAssertTrue(panel.dips)
        XCTAssertFalse(panel.warns)
        XCTAssertNil(panel.crossesBelowZeroOn)
    }

    func testAnAccountAlreadyBelowZeroWarnsButHasNoCrossing() throws {
        // The warning is honest — it is below zero — but there is no FUTURE day to alert
        // about, or the alert would be keyed on today, every day.
        let panel = try XCTUnwrap(make(
            account: account(-50), scheduled: [monthly("rent", "expense", 100, day: 20)], today: "2026-05-15"))
        XCTAssertTrue(panel.warns)
        XCTAssertNil(panel.crossesBelowZeroOn)
    }

    func testACreditCardNeverWarns() throws {
        // A card's negative balance is the debt it normally carries.
        let panel = try XCTUnwrap(make(
            account: account(0, type: "credit_card"), scheduled: [monthly("gym", "expense", 40, day: 20)],
            today: "2026-05-15"))
        XCTAssertEqual(panel.low.balance, -40)
        XCTAssertFalse(panel.warns)
        XCTAssertNil(panel.crossesBelowZeroOn)
    }

    func testOnlyRisingIsNotADip() throws {
        let panel = try XCTUnwrap(make(
            account: account(100), scheduled: [monthly("pay", "income", 1000, day: 20)], today: "2026-05-15"))
        XCTAssertFalse(panel.dips)
        XCTAssertEqual(panel.low.date, "2026-05-15", "no dip: the low point is today")
    }

    func testTheWindowIsThirtyDaysWithTodayFirst() throws {
        let panel = try XCTUnwrap(make(
            account: account(100), scheduled: [monthly("pay", "income", 10, day: 20)], today: "2026-05-15"))
        XCTAssertEqual(panel.balances.count, AccountForecastPanel.horizonDays + 1)
        XCTAssertEqual(panel.forecast.series.first?.date, "2026-05-15")
        XCTAssertEqual(panel.forecast.series.last?.date, "2026-06-14")
    }

    // MARK: what is owed now

    private func pendingRent(_ occurrence: String) -> Tx {
        Tx(id: "p1", merchant: "Rent", amount: -900, account: "a1", date: occurrence, pending: true,
           currency: "USD", nativeAmount: -900, kind: "expense", sourceTemplateId: "rent", occurrenceDate: occurrence)
    }

    func testAPendingBillDueTodayWarnsToday() throws {
        // The 20th: the bill is a pending row, not in the balance — the card stays.
        let panel = try XCTUnwrap(make(account: account(500), scheduled: [monthly("rent", "expense", 900, day: 20)],
                                       today: "2026-05-20", txns: [pendingRent("2026-05-20")]))
        XCTAssertTrue(panel.warns)
        XCTAssertEqual(panel.crossesBelowZeroOn, "2026-05-20")
        XCTAssertEqual(panel.crossingKey, "2026-05-20")
    }

    func testTheCrossingKeyHoldsWhileTheSameBillIsOwed() throws {
        // Two days on, still pending: it crosses "today" again, but the key is the
        // bill's own date — one alert, not one each morning.
        let panel = try XCTUnwrap(make(account: account(500), scheduled: [monthly("rent", "expense", 900, day: 20)],
                                       today: "2026-05-22", txns: [pendingRent("2026-05-20")]))
        XCTAssertEqual(panel.crossesBelowZeroOn, "2026-05-22")
        XCTAssertEqual(panel.crossingKey, "2026-05-20")
    }

    func testAFutureCrossingIsItsOwnKey() throws {
        let panel = try XCTUnwrap(make(account: account(500), scheduled: [monthly("rent", "expense", 900, day: 20)],
                                       today: "2026-05-15"))
        XCTAssertEqual(panel.crossingKey, panel.crossesBelowZeroOn)
    }
}
