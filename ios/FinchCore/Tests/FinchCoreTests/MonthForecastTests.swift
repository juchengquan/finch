import XCTest
@testable import FinchCore

/// The month forecast's "upcoming scheduled" term: the bills still to come this
/// month, in the ledger's base. Four ways it used to be wrong, one test each.
final class MonthForecastTests: XCTestCase {
    private func bill(id: String = "rent", amount: Double = 900, day: Int = 25, account: String = "a1",
                      frequency: String = "monthly") -> ScheduledTemplate {
        ScheduledTemplate(id: id, name: id, type: "expense", amount: amount, frequency: frequency,
                          dayOfMonth: day, accountId: account, startDate: "2026-01-01", nextRun: "")
    }
    private func row(_ template: String, occurrence: String, date: String, pending: Bool, amount: Double = -900) -> Tx {
        Tx(id: "r-\(template)-\(occurrence)", merchant: template, amount: amount, account: "a1", date: date,
           pending: pending, ledgerId: "l1", currency: "USD", kind: "expense",
           sourceTemplateId: template, occurrenceDate: occurrence)
    }
    private func rest(_ txns: [Tx], _ scheduled: [ScheduledTemplate], month: String = "2026-06",
                      today: String = "2026-06-10", activity: ForecastActivity? = nil) throws -> Double {
        try XCTUnwrap(Selectors.monthForecast(txns, scheduled, "l1", month, today, activity: activity)).scheduledRest
    }

    /// Paid on the 5th for the 25th: it is in "spent so far", not still to come.
    func test_aBillPaidEarlyIsNotCountedTwice() throws {
        let paid = row("rent", occurrence: "2026-06-25", date: "2026-06-05", pending: false)
        let f = try XCTUnwrap(Selectors.monthForecast([paid], [bill()], "l1", "2026-06", "2026-06-10"))
        XCTAssertEqual(f.mtdSpent, 900)
        XCTAssertEqual(f.scheduledRest, 0, "it was 900 as well: the bill counted twice")
    }

    /// Auto-post books a bill pending on its day. It is not in "spent so far"
    /// (confirmed only) and its day has passed, so it fell out of both.
    func test_aPendingBillIsStillOwed() throws {
        let waiting = row("rent", occurrence: "2026-06-05", date: "2026-06-05", pending: true)
        XCTAssertEqual(try rest([waiting], [bill(day: 5)]), 900)
    }

    /// A bill on the 31st falls on June 30th, as posting books it.
    func test_aDay31BillFallsOnTheLastDayOfAShortMonth() throws {
        XCTAssertEqual(try rest([], [bill(day: 31)]), 900)
    }

    /// Weekly bills count too, each occurrence left: 12th, 19th and 26th of June 2026
    /// are Fridays.
    func test_everyFrequencyCounts() throws {
        let weekly = ScheduledTemplate(id: "gym", name: "gym", type: "expense", amount: 10, frequency: "weekly",
                                   dayOfMonth: 1, weekDay: 5, accountId: "a1", startDate: "2026-01-01", nextRun: "")
        XCTAssertEqual(try rest([], [weekly]), 30)
    }

    /// A ¥15,000 bill on a yen card is about $100 in a USD ledger, at the rate posting
    /// would use; with no rate it is left out rather than counted as $15,000.
    func test_aForeignCurrencyBillIsInBase() throws {
        let yen = bill(id: "phone", amount: 15000, account: "jp")
        func activity(_ rate: Double?) -> ForecastActivity {
            ForecastActivity(txns: [], accountCurrencies: ["jp": "JPY", "a1": "USD"], baseCurrency: "USD") { amount, from, to, _ in
                from == "JPY" && to == "USD" ? rate.map { amount * $0 } : nil
            }
        }
        XCTAssertEqual(try rest([], [yen], activity: activity(1.0 / 150)), 100, accuracy: 0.001)
        XCTAssertEqual(try rest([], [yen], activity: activity(nil)), 0)
        XCTAssertEqual(try rest([], [bill()], activity: activity(nil)), 900, "a base-currency bill needs no rate")
    }
}
