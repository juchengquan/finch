import XCTest
import GRDB
@testable import FinchCore

/// The account forecast counts what has already happened to a scheduled item, not
/// just the template. It used to walk templates forward from tomorrow and nothing
/// else, so:
///
/// - **A2** — a bill paid early was counted again on its due day: the balance had
///   already dropped, the forecast dropped it a second time, and the low-balance
///   alert fired for an overdraft that would never happen.
/// - **A3** — on a bill's due day the forecast lost it. The pending row auto-post
///   added is not in the balance, and the occurrence is not after today, so neither
///   side counted it: the card and its warning vanished. An overdue bill was lost
///   the same way.
/// - **A4** — a scheduled transfer between currencies credited the receiving
///   account with the SENDING amount: $100 into a JPY account forecast +¥100, and
///   ¥150,000 into a USD account +$150,000, enough to hide an overdraft.
///
/// `ForecastActivity` carries what the template walk cannot see. Without it the
/// selector is the web's `accountForecast`, which the parity fixtures pin.
final class AccountForecastActivityTests: XCTestCase {

    private func account(_ balance: Double, currency: String = "USD") -> AccountRow {
        AccountRow(id: "a1", balance: balance, ledgerId: "l1", currency: currency)
    }

    /// Rent of 900 on the 25th, from May — no history before the window.
    private func rent(start: String = "2026-05-01", skipped: [String]? = nil,
                      installmentTotal: Int? = nil) -> ScheduledTemplate {
        ScheduledTemplate(id: "rent", name: "Rent", type: "expense", amount: 900, frequency: "monthly",
                          dayOfMonth: 25, accountId: "a1", startDate: start, nextRun: "",
                          installmentTotal: installmentTotal, skippedDates: skipped)
    }

    /// A row a scheduled item posted, as the projection hands it over.
    private func posted(_ occurrence: String, date: String? = nil, pending: Bool,
                        amount: Double = -900, template: String = "rent") -> Tx {
        Tx(id: "p-\(template)-\(occurrence)", merchant: "Rent", amount: amount, account: "a1",
           date: date ?? occurrence, pending: pending, ledgerId: "l1", currency: "USD",
           nativeAmount: amount, kind: "expense", sourceTemplateId: template, occurrenceDate: occurrence)
    }

    private func forecast(_ balance: Double, _ scheduled: [ScheduledTemplate], today: String,
                          txns: [Tx] = [], currency: String = "USD",
                          currencies: [String: String] = [:],
                          convert: @escaping (Double, String, String, String) -> Double? = { _, _, _, _ in nil })
        -> AccountForecast {
        Selectors.accountForecast(account(balance, currency: currency), scheduled, today, 30,
                                  activity: ForecastActivity(txns: txns, accountCurrencies: currencies,
                                                             convert: convert))
    }

    /// The day the balance first goes below zero, as the low-balance alert reads it.
    private func firstNegativeDay(_ f: AccountForecast) -> String? {
        f.series.first { $0.balance < 0 }?.date
    }

    // MARK: A2 — a bill paid early is not counted twice

    func test_A2_aBillPaidEarlyIsNotCountedAgainOnItsDueDay() {
        // 1000, rent 900 paid on the 15th for the 25th: the balance is already 100.
        let f = forecast(100, [rent()], today: "2026-05-15",
                         txns: [posted("2026-05-25", date: "2026-05-15", pending: false)])
        XCTAssertEqual(f.events, [], "the occurrence is posted — the balance already has it")
        XCTAssertEqual(f.endingBalance, 100)
        XCTAssertNil(firstNegativeDay(f), "no false low-balance alert")
    }

    func test_A2_theOccurrencesNotYetPaidStillCount() {
        // Paid May's early; June's, inside a 60-day look, is still ahead.
        let f = Selectors.accountForecast(account(100), [rent()], "2026-05-15", 60, activity: ForecastActivity(
            txns: [posted("2026-05-25", date: "2026-05-15", pending: false)]))
        XCTAssertEqual(f.events.map(\.date), ["2026-06-25"])
    }

    func test_A2_withoutActivityTheSelectorIsStillTheWebs() {
        // The parity contract: no activity, no posted map — every future occurrence.
        let f = Selectors.accountForecast(account(100), [rent()], "2026-05-15", 30)
        XCTAssertEqual(f.events.map(\.date), ["2026-05-25"])
    }

    // MARK: A3 — pending and due rows land today

    func test_A3_thePendingRowAutoPostAddedCountsOnItsDueDay() {
        // The 25th: auto-post added rent as a pending row. It is not in the balance.
        let f = forecast(500, [rent()], today: "2026-05-25",
                         txns: [posted("2026-05-25", pending: true)])
        XCTAssertEqual(f.events.map(\.amount), [-900])
        XCTAssertEqual(f.series.first?.balance, -400, "pending money leaves today")
        XCTAssertEqual(f.trough.balance, -400)
        XCTAssertEqual(firstNegativeDay(f), "2026-05-25", "the warning does not vanish on the due day")
    }

    func test_A3_aPendingRowIsNotCountedTwice() {
        // The pending row stands for its occurrence; the occurrence is not added again.
        let f = forecast(5000, [rent()], today: "2026-05-25",
                         txns: [posted("2026-05-25", pending: true)])
        XCTAssertEqual(f.endingBalance, 4100)
    }

    func test_A3_aConfirmedRowIsInTheBalanceAlready() {
        let f = forecast(500, [rent()], today: "2026-05-25",
                         txns: [posted("2026-05-25", pending: false)])
        XCTAssertEqual(f.events, [])
        XCTAssertEqual(f.series.first?.balance, 500)
    }

    func test_A3_anUnpostedOccurrenceDueTodayCounts() {
        // Posted by hand, not yet: due today, so it leaves today.
        let f = forecast(500, [rent()], today: "2026-05-25")
        XCTAssertEqual(f.events.map(\.date), ["2026-05-25"])
        XCTAssertEqual(f.series.first?.balance, -400)
        XCTAssertEqual(firstNegativeDay(f), "2026-05-25")
    }

    func test_A3_anOverdueOccurrenceCountsToday_byTheEnginesMissedRule() {
        // Paid in April; May's is overdue on the 27th. It is still owed, and Post
        // would book it — so it lands today, with its own date on the event.
        let f = forecast(500, [rent(start: "2026-04-01")], today: "2026-05-27",
                         txns: [posted("2026-04-25", pending: false)])
        XCTAssertEqual(f.events.map(\.date), ["2026-05-25", "2026-06-25"])
        XCTAssertEqual(f.series.first?.balance, -400)
        XCTAssertEqual(firstNegativeDay(f), "2026-05-27")
    }

    func test_A3_occurrencesTheEngineDoesNotCallMissedAreNotCounted() {
        // History posted to April; the template's recurrence reaches back to January
        // (its day changed). `missedFloor` says Jan–Mar were never owed — nor are they here.
        let f = forecast(500, [rent(start: "2026-01-01")], today: "2026-05-20",
                         txns: [posted("2026-04-25", pending: false)])
        XCTAssertEqual(f.events.map(\.date), ["2026-05-25"])
        XCTAssertEqual(f.series.first?.balance, 500)
    }

    func test_A3_aSkippedOccurrenceIsNotCounted() {
        let f = forecast(500, [rent(skipped: ["2026-05-25"])], today: "2026-05-25")
        XCTAssertEqual(f.events, [])
    }

    func test_A3_installmentsCountPendingRowsAsPaid() {
        // A 2-payment plan: April confirmed, May pending. Nothing is left to forecast
        // after the pending row — not a third payment in June.
        let f = Selectors.accountForecast(account(5000), [rent(start: "2026-04-01", installmentTotal: 2)],
                                          "2026-05-25", 60, activity: ForecastActivity(txns: [
                                            posted("2026-04-25", pending: false),
                                            posted("2026-05-25", pending: true)]))
        XCTAssertEqual(f.events.map(\.date), ["2026-05-25"], "the pending row only")
        XCTAssertEqual(f.endingBalance, 4100)
    }

    // MARK: A4 — a transfer between currencies is converted

    private func transfer(_ amount: Double) -> ScheduledTemplate {
        ScheduledTemplate(id: "xfer", name: "Savings", type: "transfer", amount: amount, frequency: "monthly",
                          dayOfMonth: 20, accountId: "a1", fromAccountId: "a2",
                          startDate: "2026-05-01", nextRun: "")
    }

    /// USD per unit, the hub the engine prices through; to the cent, as `FxConvert` rounds.
    private let usdPer: [String: Double] = ["USD": 1, "JPY": 1.0 / 150]
    private func rates(_ amount: Double, _ from: String, _ to: String, _ date: String) -> Double? {
        guard let f = usdPer[from], let t = usdPer[to] else { return nil }
        return (amount * f / t * 100).rounded() / 100
    }

    func test_A4_dollarsIntoAYenAccountArriveAsYen() {
        let f = forecast(0, [transfer(100)], today: "2026-05-15", currency: "JPY",
                         currencies: ["a1": "JPY", "a2": "USD"], convert: rates)
        XCTAssertEqual(f.events.map(\.amount), [15_000])
    }

    func test_A4_yenIntoADollarAccountArriveAsDollars_andTheOverdraftShows() {
        // $100, then ¥150,000 ($1,000) in on the 20th and a $1,200 bill on the 22nd:
        // below zero. Counted as +$150,000, the bill read as covered.
        let bill = ScheduledTemplate(id: "bill", name: "Bill", type: "expense", amount: 1200,
                                     frequency: "monthly", dayOfMonth: 22, accountId: "a1",
                                     startDate: "2026-05-01", nextRun: "")
        let f = forecast(100, [transfer(150_000), bill], today: "2026-05-15",
                         currencies: ["a1": "USD", "a2": "JPY"], convert: rates)
        XCTAssertEqual(f.events.map(\.amount), [1_000, -1_200])
        XCTAssertEqual(f.endingBalance, -100)
        XCTAssertEqual(firstNegativeDay(f), "2026-05-22")
    }

    func test_A4_theRateIsLookedUpOnTheOccurrenceDay() {
        var asked: [String] = []
        _ = Selectors.accountForecast(account(0, currency: "JPY"), [transfer(100)], "2026-05-15", 60,
                                      activity: ForecastActivity(txns: [], accountCurrencies: ["a1": "JPY", "a2": "USD"],
                                                                 convert: { a, f, t, d in asked.append(d); return self.rates(a, f, t, d) }))
        XCTAssertEqual(asked, ["2026-05-20", "2026-06-20"])
    }

    func test_A4_withNoRateTheReceivingSideIsLeftOut() {
        // Posting it would be refused for want of a rate, so nothing arrives — and
        // guessing 1:1 is what overstated it.
        let f = forecast(0, [transfer(100)], today: "2026-05-15", currency: "JPY",
                         currencies: ["a1": "JPY", "a2": "USD"])
        XCTAssertEqual(f.events, [])
    }

    func test_A4_theSendingSideNeedsNoRate() {
        // The template's amount is in the sending account's currency — exact.
        let out = ScheduledTemplate(id: "xfer", name: "Savings", type: "transfer", amount: 100, frequency: "monthly",
                                    dayOfMonth: 20, accountId: "a2", fromAccountId: "a1",
                                    startDate: "2026-05-01", nextRun: "")
        let f = forecast(500, [out], today: "2026-05-15", currencies: ["a1": "USD", "a2": "JPY"])
        XCTAssertEqual(f.events.map(\.amount), [-100])
    }

    func test_A4_sameCurrencyNeedsNoRate() {
        let f = forecast(0, [transfer(100)], today: "2026-05-15", currencies: ["a1": "USD", "a2": "USD"])
        XCTAssertEqual(f.events.map(\.amount), [100])
    }

    /// `FxConvert` is the lookup posting uses, so the forecast credits what the
    /// transfer will book.
    func test_A4_FxConvertMatchesWhatTheTransferBooks() throws {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            for (id, ccy) in [("a1", "JPY"), ("a2", "USD")] {
                try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES (?,'l1',?,'cash',?,0,0,1,1,datetime('now'),datetime('now'))",
                               arguments: [id, id, ccy])
            }
            try db.execute(sql: "INSERT INTO exchange_rates (date,currency,rate) VALUES ('2026-05-01','JPY',0.0066)")
            try db.execute(sql: "INSERT INTO exchange_rates (date,currency,rate) VALUES ('2026-06-01','JPY',0.0070)")
        }
        let forecastJPY = FxConvert.convert(dbQueue: q, 100, from: "USD", to: "JPY", on: "2026-05-20")
        try q.write { db in
            _ = try Entries.postTransfer(db, fromAccountId: "a2", toAccountId: "a1", fromAmount: 100, date: "2026-05-20")
        }
        let booked = try q.read { try Double.fetchOne($0, sql: "SELECT amount FROM postings WHERE account_id = 'a1'") }
        XCTAssertEqual(forecastJPY, booked)
        XCTAssertNotEqual(FxConvert.convert(dbQueue: q, 100, from: "USD", to: "JPY", on: "2026-06-20"), booked,
                          "the day's own rate")
        XCTAssertNil(FxConvert.convert(dbQueue: q, 100, from: "USD", to: "KRW", on: "2026-05-20"),
                     "no rate: nil, where posting refuses")
    }
}
