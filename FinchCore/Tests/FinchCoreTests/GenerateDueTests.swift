import XCTest
import GRDB
@testable import FinchCore

final class GenerateDueTests: XCTestCase {
    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','Cash','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
        }
        return q
    }

    /// A monthly template posts each due occurrence as a pending entry; re-running
    /// generates nothing new (deduped via source_template_id).
    func test_generateDueScheduled() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createScheduled", args: Args([
            "id": .string("s1"), "ledgerId": .string("l1"), "name": .string("Rent"), "type": .string("expense"),
            "amount": .double(100), "frequency": .string("monthly"), "dayOfMonth": .int(15),
            "accountId": .string("a1"), "startDate": .string("2026-01-15"),
        ]))
        try Apply.apply(dbQueue: q, action: "generateDueScheduled", args: Args(["today": .string("2026-03-20")]))
        try q.read { db in
            // 2026-01-15, 02-15, 03-15 → 3 pending entries linked to the template
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE source_template_id='s1'"), 3)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE status='pending'"), 3)
            // pending → cached balance untouched
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='a1'") ?? -1, 0, accuracy: 0.001)
        }
        // idempotent re-run: no new entries
        try Apply.apply(dbQueue: q, action: "generateDueScheduled", args: Args(["today": .string("2026-03-20")]))
        XCTAssertEqual(try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE source_template_id='s1'") }, 3)
    }

    /// An occurrence posted under a different transaction date (e.g. paid
    /// late) must be recognised as already-posted via occurrence_date, not
    /// regenerated as a duplicate. Resolution keys on occurrenceDate ?? date,
    /// so the "already posted" set must key on the same coalesce.
    func test_generateDueScheduled_doesNotRegenerateOccurrencePostedUnderDifferentDate() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createScheduled", args: Args([
            "id": .string("s1"), "ledgerId": .string("l1"), "name": .string("Rent"), "type": .string("expense"),
            "amount": .double(100), "frequency": .string("monthly"), "dayOfMonth": .int(15),
            "accountId": .string("a1"), "startDate": .string("2026-01-15"),
        ]))
        // Post the 2026-03-15 occurrence late, dated 2026-03-18.
        try Apply.apply(dbQueue: q, action: "postScheduled", args: Args([
            "templateId": .string("s1"), "date": .string("2026-03-18"), "occurrenceDate": .string("2026-03-15"),
        ]))
        try Apply.apply(dbQueue: q, action: "generateDueScheduled", args: Args(["today": .string("2026-03-20")]))
        try q.read { db in
            // 2026-01-15, 02-15 generated fresh; 03-15 must NOT be regenerated
            // because it was already posted (late) — 3 entries total, not 4.
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE source_template_id='s1'"), 3)
            let dates = try String.fetchAll(db, sql: "SELECT date FROM entries WHERE source_template_id='s1' ORDER BY date")
            XCTAssertEqual(dates, ["2026-01-15", "2026-02-15", "2026-03-18"])
        }
    }

    func test_removeAttachment() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createScheduled", args: Args(["id": .string("s1"), "ledgerId": .string("l1"), "name": .string("X"), "type": .string("expense"), "amount": .double(10), "accountId": .string("a1"), "startDate": .string("2026-01-01")]))
        try Apply.apply(dbQueue: q, action: "generateDueScheduled", args: Args(["today": .string("2026-01-02")]))
        let entryId = try q.read { db in try String.fetchOne(db, sql: "SELECT id FROM entries LIMIT 1")! }
        try q.write { db in
            try db.execute(sql: "INSERT INTO entry_attachments (id,ledger_id,entry_id,kind,rel_path,mime_type,byte_size,sha256,created_at,updated_at) VALUES ('att1','l1',?,'image','attachments/x.jpg','image/jpeg',1,'abc',datetime('now'),datetime('now'))", arguments: [entryId])
        }
        try Apply.apply(dbQueue: q, action: "removeAttachment", args: Args(["id": .string("att1")]))
        XCTAssertEqual(try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entry_attachments") }, 0)
    }
}
