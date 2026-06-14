import XCTest
import GRDB
@testable import FinchCore

/// setTransactionTags + setTransactionSplits behavior backing the EditTransaction
/// tag picker + split editor. (Both are also byte-verified in the parity oracle.)
final class TagsSplitsTests: XCTestCase {
    private func seeded() throws -> DatabaseQueue {
        let q = try TestSeed.base()   // l1 / a1 / c1
        try q.write { db in
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('c2','l1',NULL,'Fun','expense',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO tags (id,ledger_id,name,created_at,updated_at) VALUES ('t1','l1','work',datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO tags (id,ledger_id,name,created_at,updated_at) VALUES ('t2','l1','fun',datetime('now'),datetime('now'))")
        }
        return q
    }

    private func addExpense(_ q: DatabaseQueue) throws -> String {
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-100),
            "merchant": .string("Shop"), "categoryId": .string("c1"), "date": .string("2026-05-01"), "skipRules": .bool(true)]))
        return try q.read { db in try String.fetchOne(db, sql: "SELECT id FROM postings WHERE account_id='a1'") }!
    }

    func test_setTransactionTags_replacesSet() throws {
        let q = try seeded()
        let pid = try addExpense(q)
        try Apply.apply(dbQueue: q, action: "setTransactionTags", args: Args(["id": .string(pid), "tagIds": .array([.string("t1"), .string("t2")])]))
        try q.read { db in XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entry_tags"), 2) }
        // Replacing with one tag drops the other.
        try Apply.apply(dbQueue: q, action: "setTransactionTags", args: Args(["id": .string(pid), "tagIds": .array([.string("t1")])]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entry_tags"), 1)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT tag_id FROM entry_tags"), "t1")
        }
    }

    func test_setTransactionSplits_thenRemove() throws {
        let q = try seeded()
        let pid = try addExpense(q)
        let splits: JSONValue = .array([
            .object(["categoryId": .string("c1"), "amount": .double(60)]),
            .object(["categoryId": .string("c2"), "amount": .double(40)]),
        ])
        try Apply.apply(dbQueue: q, action: "setTransactionSplits", args: Args(["id": .string(pid), "splits": splits]))
        try q.read { db in
            // Two real category legs, each positive (balancing the -100 account),
            // and NO fx residue — the split is balanced (the fixed last-leg sign).
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings p JOIN categories c ON c.id=p.category_id WHERE c.kind != 'equity'"), 2)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings p JOIN categories c ON c.id=p.category_id WHERE c.kind = 'equity'"), 0, "no fx residue")
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount_base FROM postings WHERE category_id='c1'") ?? 0, 60, accuracy: 0.001)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount_base FROM postings WHERE category_id='c2'") ?? 0, 40, accuracy: 0.001)
        }
        // Removing splits collapses to a single uncategorized category leg.
        try Apply.apply(dbQueue: q, action: "setTransactionSplits", args: Args(["id": .string(pid), "splits": .array([])]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE account_id IS NULL"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE account_id IS NULL AND category_id IS NOT NULL"), 0)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='a1'") ?? 0, -100, accuracy: 0.001)
        }
    }
}
