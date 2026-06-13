import XCTest
import GRDB
@testable import FinchCore

final class ConfirmTests: XCTestCase {
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

    /// A pending entry doesn't move the cached balance until confirmed.
    func test_confirmTransaction() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-25), "merchant": .string("Coffee"),
            "categoryId": .string("c1"), "date": .string("2026-05-01"), "status": .string("pending"), "skipRules": .bool(true),
        ]))
        let txId = try q.read { db in try String.fetchOne(db, sql: "SELECT id FROM postings WHERE account_id='a1'")! }
        XCTAssertEqual(try q.read { db in try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='a1'") ?? -1 }, 0, accuracy: 0.001)
        try Apply.apply(dbQueue: q, action: "confirmTransaction", args: Args(["id": .string(txId)]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT status FROM entries"), "confirmed")
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='a1'") ?? -1, -25, accuracy: 0.001)
        }
    }

    func test_confirmPendingWithNewMerchant() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-25), "merchant": .string("UNKNOWN"),
            "categoryId": .string("c1"), "date": .string("2026-05-01"), "status": .string("pending"), "skipRules": .bool(true),
        ]))
        let txId = try q.read { db in try String.fetchOne(db, sql: "SELECT id FROM postings WHERE account_id='a1'")! }
        try Apply.apply(dbQueue: q, action: "confirmPendingWithMerchant", args: Args(["id": .string(txId), "newCounterpartyName": .string("Blue Bottle")]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT status FROM entries"), "confirmed")
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT description FROM entries"), "Blue Bottle")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM counterparties WHERE name='Blue Bottle'"), 1)
            // entry now linked to the new counterparty
            let cpId = try String.fetchOne(db, sql: "SELECT counterparty_id FROM entries")
            XCTAssertNotNil(cpId ?? nil)
        }
    }
}
