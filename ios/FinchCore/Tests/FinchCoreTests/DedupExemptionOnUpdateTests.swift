import XCTest
import GRDB
@testable import FinchCore

/// Editing an entry must not invent a dedup hash the INSERT deliberately withheld.
///
/// `insertEntry` stores NULL for two kinds of entry — one the user explicitly allowed as a
/// duplicate, and one posted from a scheduled template:
///
///     (e.allowDuplicate || e.sourceTemplateId != nil) ? nil : dedupHash(...)
///
/// `rebuildEntry` re-stamps the hash from the entry's effective content with no such
/// carve-out, so the first edit of an exempt entry gives it a hash — which collides with
/// the identical entry it was allowed to duplicate.
///
/// It surfaces as a RAW SQLite error because the reported route — the row's status
/// toggle — goes through the `updateTransaction` action, which was not wrapped in
/// `Dedup.wrap` the way `addTransaction` and `saveTransaction` already were. The add/edit
/// SHEETS go through `saveTransaction` instead, which was wrapped, so the same collision
/// there always did read as a friendly duplicate message.
final class DedupExemptionOnUpdateTests: XCTestCase {

    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','Cash','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('c1','l1',NULL,'Food','expense',0,datetime('now'),datetime('now'))")
        }
        return q
    }

    private func addCoffee(_ q: DatabaseQueue, allowDuplicate: Bool = false) throws -> String {
        var args: [String: JSONValue] = [
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-4.50),
            "merchant": .string("Blue Bottle"), "categoryId": .string("c1"),
            "date": .string("2026-05-01"), "time": .string("08:30"), "skipRules": .bool(true),
        ]
        if allowDuplicate { args["allowDuplicate"] = .bool(true) }
        return try XCTUnwrap(Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args(args)))
    }

    /// The reported failure: two identical coffees exist because the second was
    /// explicitly allowed, then editing the second — e.g. marking it pending —
    /// stamps it with the first one's hash.
    func test_editingAnAllowedDuplicateDoesNotInventAHash() throws {
        let q = try seeded()
        _ = try addCoffee(q)
        let dupId = try addCoffee(q, allowDuplicate: true)

        try q.read { db in
            let h = try String.fetchOne(db, sql: "SELECT dedup_hash FROM entries WHERE id = ?", arguments: [dupId])
            XCTAssertNil(h, "the insert exempts an allowed duplicate — it stores NULL")
        }

        // Marking it pending touches nothing the hash is made of (date, time,
        // description, account legs). It must not resurrect the hash.
        XCTAssertNoThrow(try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
            "id": .string(dupId), "patch": .object(["status": .string("pending")]),
        ])))

        try q.read { db in
            let h = try String.fetchOne(db, sql: "SELECT dedup_hash FROM entries WHERE id = ?", arguments: [dupId])
            XCTAssertNil(h, "the exemption must survive an edit, or the entry can never be edited again")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries"), 2)
        }
    }

    /// The same hole reached the other way: entries posted from a scheduled template are
    /// exempt because the template legitimately produces identical rows month after month.
    func test_editingAScheduledPostingDoesNotInventAHash() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO scheduled_templates (id,ledger_id,name,description,kind,amount,account_id,category_id,frequency,day_of_month,start_date,next_run,is_active,created_at,updated_at)
                VALUES ('t1','l1','Netflix','Netflix','expense',-9.99,'a1','c1','monthly',1,'2026-05-01','2026-05-01',1,datetime('now'),datetime('now'))
                """)
        }
        // Two postings of the same template on the same date/time are legitimate.
        try q.write { db in
            for _ in 0..<2 {
                try Entries.postSimple(db, .init(ledgerId: "l1", accountId: "a1", amount: -9.99,
                    date: "2026-05-01", description: "Netflix", categoryId: "c1", kind: .expense,
                    time: "00:00", sourceTemplateId: "t1"))
            }
        }
        let ids: [String] = try q.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM entries WHERE source_template_id = 't1' ORDER BY created_at")
        }
        XCTAssertEqual(ids.count, 2, "two postings of the same template are legitimate")
        try q.read { db in
            for id in ids {
                XCTAssertNil(try String.fetchOne(db, sql: "SELECT dedup_hash FROM entries WHERE id = ?", arguments: [id]),
                             "template postings are exempt at insert")
            }
        }
        XCTAssertNoThrow(try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
            "id": .string(ids[1]), "patch": .object(["status": .string("pending")]),
        ])))
        // Editing ONE of the two does not collide (the other is still NULL), so the
        // symptom hides — but the exemption is gone, and editing the second one then
        // fails. Assert the invariant, not just the absence of a throw.
        try q.read { db in
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT dedup_hash FROM entries WHERE id = ?", arguments: [ids[1]]),
                         "a template posting must stay exempt after an edit")
        }
        XCTAssertNoThrow(try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
            "id": .string(ids[0]), "patch": .object(["status": .string("pending")]),
        ])), "editing the second posting must not collide with the first")
    }

    /// The exemption must not become a blanket "never hash on update": an ordinary
    /// entry still gets its hash re-stamped when the edit changes what the hash is
    /// made of, which is what keeps the duplicate guard working after an edit.
    func test_anOrdinaryEntryStillRestampsItsHash() throws {
        let q = try seeded()
        let id = try addCoffee(q)
        let before = try q.read { db in
            try String.fetchOne(db, sql: "SELECT dedup_hash FROM entries WHERE id = ?", arguments: [id])
        }
        XCTAssertNotNil(before)

        try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
            "id": .string(id), "patch": .object(["merchant": .string("Kopi")]),
        ]))
        let after = try q.read { db in
            try String.fetchOne(db, sql: "SELECT dedup_hash FROM entries WHERE id = ?", arguments: [id])
        }
        XCTAssertNotNil(after)
        XCTAssertNotEqual(before, after, "changing the description must change the hash")
    }

    /// And a real collision still has to be reported — as the friendly localized error,
    /// not a raw SQLite string, which is the second half of what the user saw.
    func test_aRealCollisionOnUpdateIsAFriendlyError() throws {
        let q = try seeded()
        _ = try addCoffee(q)
        let other = try XCTUnwrap(Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-4.50),
            "merchant": .string("Kopi"), "categoryId": .string("c1"),
            "date": .string("2026-05-01"), "time": .string("08:30"), "skipRules": .bool(true),
        ])))
        // Renaming it onto the first one's identity is a genuine duplicate.
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
            "id": .string(other), "patch": .object(["merchant": .string("Blue Bottle")]),
        ]))) { err in
            guard let e = err as? I18nError else {
                return XCTFail("expected a localized duplicate error, got raw: \(err)")
            }
            XCTAssertEqual(e.code, "error.duplicate.txn")
        }
    }
}
