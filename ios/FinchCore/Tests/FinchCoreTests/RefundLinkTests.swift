import XCTest
import GRDB
@testable import FinchCore

/// A refund added via `addTransaction` with `refundedTransactionId` must persist
/// the linkage in `entries.refunded_entry_id` on INSERT (regression: the iOS
/// insert path decoded the field but never forwarded it, so all natively-created
/// refunds were unlinked).
final class RefundLinkTests: XCTestCase {
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

    func test_refund_insert_persists_refundedEntryId() throws {
        let q = try seeded()
        // Original expense.
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-20),
            "merchant": .string("Shop"), "categoryId": .string("c1"),
            "date": .string("2026-05-01"), "time": .string("09:00"), "skipRules": .bool(true)]))
        // The refund link is to the original ENTRY id (the FK target), matching
        // the web add path (refundedTransactionId carries an entry id).
        let origEntryId = try q.read { db in
            try String.fetchOne(db, sql: "SELECT id FROM entries WHERE description = 'Shop'")
        }
        XCTAssertNotNil(origEntryId)

        // Refund linked to the original.
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(20),
            "merchant": .string("Shop refund"), "categoryId": .string("c1"), "kind": .string("refund"),
            "date": .string("2026-05-02"), "time": .string("09:00"), "skipRules": .bool(true),
            "refundedTransactionId": .string(origEntryId!)]))

        let linked = try q.read { db in
            try String.fetchOne(db, sql: "SELECT refunded_entry_id FROM entries WHERE refunded_entry_id IS NOT NULL")
        }
        XCTAssertEqual(linked, origEntryId, "refund insert must persist refunded_entry_id")
    }
}
