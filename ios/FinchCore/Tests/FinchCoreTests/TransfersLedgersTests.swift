import XCTest
import GRDB
@testable import FinchCore

final class TransfersLedgersTests: XCTestCase {
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

    func test_createTransfer() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createTransfer", args: Args([
            "fromAccountId": .string("a1"), "toAccountId": .string("a2"), "fromAmount": .double(100), "date": .string("2026-05-01"),
        ]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE kind='transfer'"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE account_id IS NOT NULL"), 2)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='a1'") ?? 0, 900, accuracy: 0.001)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='a2'") ?? 0, 100, accuracy: 0.001)
        }
        // same account rejected
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "createTransfer", args: Args(["fromAccountId": .string("a1"), "toAccountId": .string("a1"), "fromAmount": .double(10), "date": .string("2026-05-01")]))) {
            XCTAssertEqual(($0 as? I18nError)?.code, "error.transfer.sameAccount")
        }
    }

    func test_ledgerCrud() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createLedger", args: Args(["id": .string("biz"), "name": .string("Business"), "base": .string("eur")]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT base_currency FROM ledgers WHERE id='biz'"), "EUR")
            // createLedger seeds the 3 equity system categories
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE ledger_id='biz' AND kind='equity'"), 3)
        }
        try Apply.apply(dbQueue: q, action: "setDefaultLedger", args: Args(["id": .string("biz")]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT is_default FROM ledgers WHERE id='biz'"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT is_default FROM ledgers WHERE id='l1'"), 0)
        }
        try Apply.apply(dbQueue: q, action: "updateLedger", args: Args(["id": .string("biz"), "patch": .object(["name": .string("Biz Co")])]))
        XCTAssertEqual(try q.read { db in try String.fetchOne(db, sql: "SELECT name FROM ledgers WHERE id='biz'") }, "Biz Co")
        // delete biz (was default) → l1 becomes default again
        try Apply.apply(dbQueue: q, action: "deleteLedger", args: Args(["id": .string("biz")]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ledgers WHERE id='biz'"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT is_default FROM ledgers WHERE id='l1'"), 1)
        }
        // can't delete the last ledger
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "deleteLedger", args: Args(["id": .string("l1")]))) {
            XCTAssertEqual(($0 as? I18nError)?.code, "error.ledger.lastLedger")
        }
    }
}
