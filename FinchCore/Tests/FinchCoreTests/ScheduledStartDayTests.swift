import XCTest
import GRDB
@testable import FinchCore

/// Quarterly and yearly templates recur on their START DATE's day, and the start
/// occurrence itself counts.
///
/// The sheet only offers a day of month for monthly items, and a template saved
/// without one stores `day_of_month = 1`, so a quarterly item starting 15 Mar used to
/// post on 1 Jun, 1 Sep… and skip March. The start date is what pins a quarterly or
/// yearly cadence (it already picks the month), so it picks the day too, whatever
/// `day_of_month` says. Monthly keeps its own day of month. Mirrors
/// `frontend/lib/recurrence.test.ts`.
final class ScheduledStartDayTests: XCTestCase {

    private func template(_ frequency: String, start: String, dayOfMonth: Int = 1,
                          endDate: String? = nil) -> ScheduledTemplate {
        ScheduledTemplate(id: "t", name: "T", type: "expense", amount: 10, frequency: frequency,
                          dayOfMonth: dayOfMonth, accountId: "a1", startDate: start, endDate: endDate,
                          nextRun: "")
    }

    // MARK: recurrence

    func test_quarterlyRecursOnTheStartDay_startingWithTheStartItself() {
        XCTAssertEqual(Selectors.occurrencesUpTo(template("quarterly", start: "2026-03-15"), "2026-12-31"),
                       ["2026-03-15", "2026-06-15", "2026-09-15", "2026-12-15"])
    }

    func test_yearlyRecursOnTheStartDate() {
        XCTAssertEqual(Selectors.occurrencesUpTo(template("yearly", start: "2026-03-15"), "2028-12-31"),
                       ["2026-03-15", "2027-03-15", "2028-03-15"])
    }

    func test_aStoredDayOfMonthDoesNotMoveAQuarterlyOrYearlyItem() {
        // A row saved before the fix, or edited over from monthly, carries some other day.
        XCTAssertEqual(Selectors.occurrencesUpTo(template("quarterly", start: "2026-03-15", dayOfMonth: 20), "2026-09-30"),
                       ["2026-03-15", "2026-06-15", "2026-09-15"])
        XCTAssertEqual(Selectors.occurrencesUpTo(template("yearly", start: "2026-03-15", dayOfMonth: 0), "2027-12-31"),
                       ["2026-03-15", "2027-03-15"])
    }

    func test_aStartOnThe31stClampsToShortMonths_withoutDrifting() {
        XCTAssertEqual(Selectors.occurrencesUpTo(template("quarterly", start: "2026-03-31"), "2027-03-31"),
                       ["2026-03-31", "2026-06-30", "2026-09-30", "2026-12-31", "2027-03-31"])
        XCTAssertEqual(Selectors.occurrencesUpTo(template("yearly", start: "2028-02-29"), "2030-12-31"),
                       ["2028-02-29", "2029-02-28", "2030-02-28"])
    }

    func test_monthlyStillLandsOnItsOwnDayOfMonth() {
        XCTAssertEqual(Selectors.occurrencesUpTo(template("monthly", start: "2026-03-15", dayOfMonth: 1), "2026-05-31"),
                       ["2026-04-01", "2026-05-01"])
    }

    func test_anEndDateStillStopsAQuarterlyItem() {
        XCTAssertEqual(Selectors.occurrencesUpTo(template("quarterly", start: "2026-03-15", endDate: "2026-09-14"), "2026-12-31"),
                       ["2026-03-15", "2026-06-15"])
    }

    // MARK: end to end — a template created the way the sheet creates it

    func test_aQuarterlyItemCreatedWithoutADayOfMonthPostsOnItsStartDay() throws {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','Cash','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
        }
        // No dayOfMonth — the sheet sends one for monthly only.
        try Apply.apply(dbQueue: q, action: "createScheduled", args: Args([
            "id": .string("ins"), "ledgerId": .string("l1"), "name": .string("Insurance"), "type": .string("expense"),
            "amount": .double(180), "frequency": .string("quarterly"),
            "accountId": .string("a1"), "startDate": .string("2026-03-15"),
        ]))
        try Apply.apply(dbQueue: q, action: "generateDueScheduled", args: Args(["today": .string("2026-09-20")]))
        let dates = try q.read { db in
            try String.fetchAll(db, sql: "SELECT COALESCE(occurrence_date, date) FROM entries WHERE source_template_id = 'ins' ORDER BY 1")
        }
        XCTAssertEqual(dates, ["2026-03-15", "2026-06-15", "2026-09-15"])
    }
}
