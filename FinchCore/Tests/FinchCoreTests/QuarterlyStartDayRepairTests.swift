import XCTest
import GRDB
@testable import FinchCore

/// The repair that carries a quarterly or yearly item on from the day it actually
/// ran (`Migrations.repairQuarterlyStartDays`).
///
/// Before #817 such an item recurred on its stored `day_of_month`, which the iOS sheet
/// left at 1: an item starting 15 Mar came due on 1 Jun and 1 Sep, and those are the
/// dates users posted. #817 moved the recurrence onto the start's day, so that history
/// no longer matches any occurrence — the row reads overdue from 15 Mar and the
/// generator books 15 Mar, 15 Jun and 15 Sep again. Mirrors
/// `frontend/lib/db/core/repair-quarterly-start-day.test.ts`.
final class QuarterlyStartDayRepairTests: XCTestCase {
    private let today = "2026-10-19"

    private func db() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','Cash','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
        }
        return q
    }

    /// A template the way the pre-#817 sheet saved it: no day of month, so 1.
    private func create(_ q: DatabaseQueue, id: String = "ins", frequency: String = "quarterly",
                        start: String = "2026-03-15", extra: [String: JSONValue] = [:]) throws {
        var args: [String: JSONValue] = [
            "id": .string(id), "ledgerId": .string("l1"), "name": .string("Insurance"), "type": .string("expense"),
            "amount": .double(180), "frequency": .string(frequency), "accountId": .string("a1"),
            "startDate": .string(start),
        ]
        args.merge(extra) { $1 }
        try Apply.apply(dbQueue: q, action: "createScheduled", args: Args(args))
    }

    private func post(_ q: DatabaseQueue, _ id: String = "ins", _ dates: String...) throws {
        for d in dates {
            try Apply.apply(dbQueue: q, action: "postScheduled", args: Args([
                "templateId": .string(id), "date": .string(d), "occurrenceDate": .string(d), "time": .string("09:00"),
            ]))
        }
    }

    private func repair(_ q: DatabaseQueue) throws {
        try q.write { try Migrations.repairQuarterlyStartDays($0) }
    }

    private func template(_ q: DatabaseQueue, _ id: String = "ins") throws -> ScheduledTemplate {
        try XCTUnwrap(try Projection.scheduledTemplates(dbQueue: q, ledgerId: "l1").first { $0.id == id })
    }

    private func row(_ q: DatabaseQueue, _ id: String = "ins") throws -> (start: String, day: Int, updated: String) {
        try q.read { db in
            let r = try XCTUnwrap(try Row.fetchOne(db, sql: "SELECT start_date, day_of_month, updated_at FROM scheduled_templates WHERE id = ?", arguments: [id]))
            return (r["start_date"], r["day_of_month"], r["updated_at"])
        }
    }

    private func postedMap(_ q: DatabaseQueue) throws -> [String: Bool] {
        try q.read { db in
            var out: [String: Bool] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT source_template_id AS t, COALESCE(occurrence_date, date) AS d, status FROM entries WHERE source_template_id IS NOT NULL") {
                out["\(r["t"] as String)|\(r["d"] as String)"] = (r["status"] as String) == "pending"
            }
            return out
        }
    }

    private func occurrenceKeys(_ q: DatabaseQueue, _ id: String = "ins") throws -> [String] {
        try q.read { db in
            try String.fetchAll(db, sql: "SELECT COALESCE(occurrence_date, date) FROM entries WHERE source_template_id = ? ORDER BY 1", arguments: [id])
        }
    }

    private func resume(_ q: DatabaseQueue, _ id: String = "ins") throws -> String? {
        Selectors.resumeOccurrence(template: try template(q, id), posted: try postedMap(q), today: today)
    }

    private func generate(_ q: DatabaseQueue, through: String? = nil) throws {
        try Apply.apply(dbQueue: q, action: "generateDueScheduled", args: Args(["today": .string(through ?? today)]))
    }

    // MARK: the repro

    func test_withoutTheRepair_theHistoryMatchesNothing() throws {
        let q = try db()
        try create(q)
        try post(q, "ins", "2026-06-01", "2026-09-01")
        // The row reads overdue, and Post opens, on a date nobody owed: 15 Sep, the
        // first new-rule date after the latest posting (`missedFloor` passes over the
        // older ones). The next real date is 1 Dec.
        XCTAssertEqual(try resume(q), "2026-09-15")
        // The web oracle's load-time generator books the three new dates again.
        try generate(q)
        XCTAssertEqual(try occurrenceKeys(q), ["2026-03-15", "2026-06-01", "2026-06-15", "2026-09-01", "2026-09-15"])
    }

    func test_theRepairMovesTheStartToTheFirstDateItRan() throws {
        let q = try db()
        try create(q)
        try post(q, "ins", "2026-06-01", "2026-09-01")
        try repair(q)

        let r = try row(q)
        XCTAssertEqual(r.start, "2026-06-01")
        XCTAssertEqual(r.day, 1)
        XCTAssertEqual(Selectors.occurrencesUpTo(try template(q), today), ["2026-06-01", "2026-09-01"])
        // Not overdue: the next real date is the next one.
        XCTAssertEqual(try resume(q), "2026-12-01")
        // And the generator finds everything already posted.
        try generate(q)
        XCTAssertEqual(try occurrenceKeys(q), ["2026-06-01", "2026-09-01"])
    }

    func test_theMigrationRunsTheRepair() throws {
        // The repair is registered: a database that lacks its bookkeeping row (a
        // pack from the web, or from before this shipped) gets it on open.
        let q = try db()
        try create(q)
        try post(q, "ins", "2026-06-01")
        try q.write { db in
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = '2026-10-19-quarterly-start-day'")
        }
        try Migrations.runAll(on: q)
        XCTAssertEqual(try row(q).start, "2026-06-01")
    }

    func test_runningItAgainChangesNothing() throws {
        let q = try db()
        try create(q)
        try post(q, "ins", "2026-06-01", "2026-09-01")
        try repair(q)
        let once = try row(q)
        try repair(q)
        let twice = try row(q)
        XCTAssertEqual(twice.start, once.start)
        XCTAssertEqual(twice.day, once.day)
        XCTAssertEqual(twice.updated, once.updated, "the second run must not touch the row at all")
    }

    func test_yearly() throws {
        let q = try db()
        try create(q, frequency: "yearly", start: "2025-03-15")
        try post(q, "ins", "2026-03-01")
        try repair(q)
        XCTAssertEqual(try row(q).start, "2026-03-01")
        XCTAssertEqual(try resume(q), "2027-03-01")
    }

    // MARK: left alone

    func test_aStartOnTheFirstIsLeftAlone() throws {
        let q = try db()
        try create(q, start: "2026-03-01")
        try post(q, "ins", "2026-03-01", "2026-06-01")
        let before = try row(q)
        try repair(q)
        XCTAssertEqual(try row(q).start, before.start)
        XCTAssertEqual(try row(q).updated, before.updated)
    }

    func test_aTemplateWithNoHistoryIsLeftAlone() throws {
        // #817 is right for it: it simply starts on its start date.
        let q = try db()
        try create(q)
        try repair(q)
        XCTAssertEqual(try row(q).start, "2026-03-15")
        XCTAssertEqual(try row(q).day, 1)
    }

    func test_aMonthlyTemplateIsLeftAlone() throws {
        let q = try db()
        try create(q, frequency: "monthly", extra: ["dayOfMonth": .int(1)])
        try post(q, "ins", "2026-04-01")
        try repair(q)
        XCTAssertEqual(try row(q).start, "2026-03-15")
    }

    func test_aTemplateAlreadyUsedUnderTheNewRuleIsLeftAlone() throws {
        // Saved with some other day of month but posted on its start day since #817:
        // its history is on the new series, so moving it would strand it instead.
        let q = try db()
        try create(q)
        try post(q, "ins", "2026-03-15", "2026-06-15")
        try repair(q)
        XCTAssertEqual(try row(q).start, "2026-03-15")
    }

    // MARK: end dates, counts, skips

    func test_anInstallmentPlanKeepsItsRemainingCount_andItsEndDate() throws {
        let q = try db()
        try create(q, extra: ["installmentTotal": .int(4), "endDate": .string("2027-06-30")])
        try post(q, "ins", "2026-06-01", "2026-09-01")
        try repair(q)
        // Two of four paid, so two left — on the old dates — and the end date stays.
        try generate(q, through: "2027-12-31")
        XCTAssertEqual(try occurrenceKeys(q), ["2026-06-01", "2026-09-01", "2026-12-01", "2027-03-01"])
        XCTAssertEqual(try template(q).endDate, "2027-06-30")
    }

    func test_maxExecutionsKeepsItsRemainingCount() throws {
        let q = try db()
        try create(q, extra: ["maxExecutions": .int(3)])
        try post(q, "ins", "2026-06-01")
        try repair(q)
        try generate(q, through: "2027-12-31")
        XCTAssertEqual(try occurrenceKeys(q), ["2026-06-01", "2026-09-01", "2026-12-01"])
    }

    func test_anEndDateBeforeAnyNewOccurrenceStillBoundsTheSeries() throws {
        let q = try db()
        try create(q, extra: ["endDate": .string("2026-10-31")])
        try post(q, "ins", "2026-06-01", "2026-09-01")
        try repair(q)
        XCTAssertEqual(Selectors.occurrencesUpTo(try template(q), "2027-12-31"), ["2026-06-01", "2026-09-01"])
        XCTAssertNil(try resume(q), "nothing left before the end date")
    }

    func test_aSkipCountsAsHistory_andStillApplies() throws {
        // Skipped under the old rule (the new rule refuses 1 Jun, so write it as the
        // old engine did), then posted nothing.
        let q = try db()
        try create(q)
        try q.write { try ScheduledSkips.save($0, ["ins": ["2026-06-01"]]) }
        try repair(q)
        XCTAssertEqual(try row(q).start, "2026-06-01")
        XCTAssertEqual(Selectors.occurrencesUpTo(try template(q), today), ["2026-09-01"])
        XCTAssertEqual(try resume(q), "2026-09-01", "September was owed and is still owed")
    }

    // MARK: a stored day the old rule clamped

    func test_aClampedFirstDateMovesTheStartToTheStoredDayWhenNothingBeforeItIsOwed() throws {
        // Stored 31, starting 10 Apr: the old rule ran 30 Apr, 31 Jul, 31 Oct. A start
        // on 30 Apr would recur on the 30th, so the start goes to 31 Jul instead — 30
        // Apr was posted, so nothing drops out.
        let q = try db()
        try create(q, start: "2026-04-10", extra: ["dayOfMonth": .int(31)])
        try post(q, "ins", "2026-04-30", "2026-07-31")
        try repair(q)
        XCTAssertEqual(try row(q).start, "2026-07-31")
        XCTAssertEqual(try row(q).day, 31)
        XCTAssertEqual(try resume(q), "2026-10-31")
        try generate(q)
        XCTAssertEqual(try occurrenceKeys(q), ["2026-04-30", "2026-07-31"])
    }

    func test_aClampedFirstDateThatIsStillOwedStaysInTheSeries() throws {
        // Nothing was recorded for 30 Apr, so it must not drop out of the series: the
        // start stays on it, accepting the 30th from then on.
        let q = try db()
        try create(q, start: "2026-04-10", extra: ["dayOfMonth": .int(31)])
        try post(q, "ins", "2026-07-31")
        try repair(q)
        XCTAssertEqual(try row(q).start, "2026-04-30")
        XCTAssertEqual(try row(q).day, 30)
        XCTAssertEqual(Selectors.occurrencesUpTo(try template(q), today), ["2026-04-30", "2026-07-30"])
    }

    // MARK: the old rule itself

    func test_legacyOccurrencesMatchThePreFixEngine() {
        XCTAssertEqual(Migrations.legacyMonthStepOccurrences(start: "2026-03-15", day: 1, stepMonths: 3,
                                                             endDate: nil, through: "2026-12-31"),
                       ["2026-06-01", "2026-09-01", "2026-12-01"])
        XCTAssertEqual(Migrations.legacyMonthStepOccurrences(start: "2026-01-10", day: 31, stepMonths: 3,
                                                             endDate: "2026-10-30", through: "2027-01-31"),
                       ["2026-01-31", "2026-04-30", "2026-07-31"])
        XCTAssertEqual(Migrations.legacyMonthStepOccurrences(start: "2027-02-10", day: 29, stepMonths: 12,
                                                             endDate: nil, through: "2029-12-31"),
                       ["2027-02-28", "2028-02-29", "2029-02-28"])
    }
}
