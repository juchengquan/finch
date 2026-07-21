import XCTest
import GRDB
@testable import FinchCore

final class ScheduledPostTests: XCTestCase {
    private func seeded() throws -> DatabaseQueue {
        let q = try TestSeed.base()   // l1 / a1 / c1
        try Apply.apply(dbQueue: q, action: "createScheduled", args: Args([
            "id": .string("s1"), "ledgerId": .string("l1"), "name": .string("Rent"), "type": .string("expense"),
            "amount": .double(1200), "frequency": .string("monthly"), "dayOfMonth": .int(1),
            "accountId": .string("a1"), "category": .string("c1"),
        ]))
        return q
    }

    func test_post_withExplicitDate_usesItForBothColumns() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "postScheduled", args: Args([
            "templateId": .string("s1"), "date": .string("2026-07-15"),
        ]))
        try q.read { db in
            let r = try Row.fetchOne(db, sql: "SELECT date, occurrence_date FROM entries WHERE source_template_id = 's1'")
            XCTAssertEqual(r?["date"], "2026-07-15")
            XCTAssertEqual(r?["occurrence_date"], "2026-07-15")
        }
    }

    func test_post_withSeparateOccurrenceDate_keepsThemDistinct() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "postScheduled", args: Args([
            "templateId": .string("s1"), "date": .string("2026-07-21"),
            "occurrenceDate": .string("2026-07-15"),
        ]))
        try q.read { db in
            let r = try Row.fetchOne(db, sql: "SELECT date, occurrence_date FROM entries WHERE source_template_id = 's1'")
            XCTAssertEqual(r?["date"], "2026-07-21")
            XCTAssertEqual(r?["occurrence_date"], "2026-07-15")
        }
    }

    /// Parity guard: no date argument must behave exactly as before.
    func test_post_withoutDate_stampsTodayAndSetsOccurrenceToIt() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "postScheduled", args: Args(["templateId": .string("s1")]))
        try q.read { db in
            let r = try Row.fetchOne(db, sql: "SELECT date, occurrence_date FROM entries WHERE source_template_id = 's1'")
            XCTAssertEqual(r?["date"] as String?, r?["occurrence_date"] as String?)
        }
    }
}
