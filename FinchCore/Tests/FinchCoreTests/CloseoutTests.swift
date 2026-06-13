import XCTest
import GRDB
@testable import FinchCore

final class CloseoutTests: XCTestCase {
    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','Cash','cash','USD',1000,0,1,1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a2','l1','Savings','savings','USD',0,0,1,1,datetime('now'),datetime('now'))")
        }
        return q
    }

    func test_reconcileAccountPostsAdjustment() throws {
        let q = try seeded()
        // a1 starts at 1000; no cleared postings → cleared = 0, statement 500 → delta 500 adjustment.
        try Apply.apply(dbQueue: q, action: "reconcileAccount", args: Args([
            "accountId": .string("a1"), "statementBalance": .double(500), "statementDate": .string("2026-05-31"), "postAdjustment": .bool(true),
        ]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE kind='adjustment'"), 1)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT last_reconciled_balance FROM accounts WHERE id='a1'") ?? -1, 500, accuracy: 0.001)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT last_reconciled_at FROM accounts WHERE id='a1'"), "2026-05-31")
            // adjustment leg is marked cleared
            XCTAssertNotNil(try String.fetchOne(db, sql: "SELECT cleared_at FROM postings WHERE account_id='a1' AND cleared_at IS NOT NULL LIMIT 1") ?? nil)
        }
    }

    func test_updateTransferReamounts() throws {
        // Use opening-balance-backed accounts so the full recompute (which sums
        // postings) reflects the 1000 starting balance, not just the transfer leg.
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
        }
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args(["id": .string("a1"), "ledgerId": .string("l1"), "name": .string("Cash"), "type": .string("cash"), "currency": .string("USD"), "openingBalance": .double(1000)]))
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args(["id": .string("a2"), "ledgerId": .string("l1"), "name": .string("Savings"), "type": .string("savings"), "currency": .string("USD")]))
        try Apply.apply(dbQueue: q, action: "createTransfer", args: Args(["fromAccountId": .string("a1"), "toAccountId": .string("a2"), "fromAmount": .double(100), "date": .string("2026-05-01")]))
        let txId = try q.read { db in try String.fetchOne(db, sql: "SELECT p.id FROM postings p JOIN entries e ON e.id=p.entry_id WHERE p.account_id='a1' AND e.kind='transfer'")! }
        // bump the transfer to 150 (same-currency → both legs scale together)
        try Apply.apply(dbQueue: q, action: "updateTransfer", args: Args(["id": .string(txId), "patch": .object(["fromAmount": .double(150)])]))
        try q.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='a1'") ?? 0, 850, accuracy: 0.001)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='a2'") ?? 0, 150, accuracy: 0.001)
            // still a balanced 2-account-leg transfer
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT ROUND(SUM(amount_base),2) FROM postings WHERE entry_id=(SELECT entry_id FROM postings WHERE id=?)", arguments: [txId]) ?? -1, 0, accuracy: 0.001)
        }
    }
}
