import XCTest
import GRDB
@testable import FinchApp
import FinchCore

/// What the row says for a quarterly item saved before #817, before and after the
/// start-day repair (`Migrations.repairQuarterlyStartDays`, FinchCore's
/// "2026-10-19-quarterly-start-day" migration).
///
/// The old sheet stored `day_of_month = 1`, so an item starting 15 Mar ran on 1 Jun
/// and 1 Sep, and those were posted. #817 recurs on the start's day, so without the
/// repair the row reads overdue on 15 Sep — a date nobody ever owed.
final class QuarterlyStartDayCaptionTests: XCTestCase {
    private let today = "2026-10-19"

    private func caption(_ q: DatabaseQueue) throws -> (text: String, overdue: Bool) {
        let t = try XCTUnwrap(try Projection.scheduledTemplates(dbQueue: q, ledgerId: "l1").first)
        let posted = Selectors.scheduledPostedMap(try Projection.run(dbQueue: q, ledgerId: "l1"))
        return ScheduledCaption.cadence(t, posted: posted, today: today)
    }

    @MainActor
    func test_theRowStopsReadingOverdue_onceTheRepairRuns() throws {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','Cash','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
        }
        try Apply.apply(dbQueue: q, action: "createScheduled", args: Args([
            "id": .string("ins"), "ledgerId": .string("l1"), "name": .string("Insurance"), "type": .string("expense"),
            "amount": .double(180), "frequency": .string("quarterly"), "dayOfMonth": .int(1),
            "accountId": .string("a1"), "startDate": .string("2026-03-15"),
        ]))
        for d in ["2026-06-01", "2026-09-01"] {
            try Apply.apply(dbQueue: q, action: "postScheduled", args: Args([
                "templateId": .string("ins"), "date": .string(d), "occurrenceDate": .string(d), "time": .string("09:00"),
            ]))
        }
        XCTAssertEqual(try caption(q).text, "Quarterly · overdue 2026-09-15")

        // A database from before the repair shipped: its bookkeeping lacks the row.
        try q.write { db in
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = '2026-10-19-quarterly-start-day'")
        }
        try Migrations.runAll(on: q)

        let after = try caption(q)
        XCTAssertEqual(after.text, "Quarterly · next 2026-12-01")
        XCTAssertFalse(after.overdue)
    }
}
