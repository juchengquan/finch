import XCTest
import GRDB
@testable import FinchCore

/// Functional tests for the posting engine (Phase 2). The write-side *parity*
/// suite (Task 17, vs the web oracle) comes later; here we verify the engine
/// produces a balanced, sealed entry and that the balance trigger fires.
final class EntriesTests: XCTestCase {
    private func seededDB() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','Cash','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('c1','l1',NULL,'Food','expense',0,datetime('now'),datetime('now'))")
        }
        return q
    }

    func test_postSimpleCreatesBalancedSealedEntry() throws {
        let q = try seededDB()
        try q.write { db in
            let id = try Entries.postSimple(db, .init(
                ledgerId: "l1", accountId: "a1", amount: -25, date: "2026-05-01",
                description: "Coffee", categoryId: "c1", skipRules: true))

            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE entry_id = ?", arguments: [id]), 2)
            // sealed + confirmed
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT sealed FROM entries WHERE id = ?", arguments: [id]), 1)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT kind FROM entries WHERE id = ?", arguments: [id]), "expense")
            // balanced to the cent
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT ROUND(SUM(amount_base),2) FROM postings WHERE entry_id = ?", arguments: [id]) ?? -1, 0, accuracy: 0.001)
            // tr_post_balance moved the cached balance (account currency).
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id = 'a1'") ?? -1, -25, accuracy: 0.001)
        }
    }

    func test_postSimpleIncomeBySign() throws {
        let q = try seededDB()
        try q.write { db in
            let id = try Entries.postSimple(db, .init(
                ledgerId: "l1", accountId: "a1", amount: 100, date: "2026-05-02",
                description: "Pay", categoryId: "c1", skipRules: true))
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT kind FROM entries WHERE id = ?", arguments: [id]), "income")
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id = 'a1'") ?? -1, 100, accuracy: 0.001)
        }
    }
}
