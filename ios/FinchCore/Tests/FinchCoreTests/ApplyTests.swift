import XCTest
import GRDB
@testable import FinchCore

final class ApplyTests: XCTestCase {
    private func freshDB() throws -> DatabaseQueue {
        let q = try DatabaseQueue()        // in-memory
        try Migrations.runAll(on: q)
        return q
    }

    func test_unknownActionThrowsI18n() throws {
        let q = try freshDB()
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "nonExistentAction", args: Args([:]))) { err in
            guard let e = err as? I18nError else { return XCTFail("expected I18nError") }
            XCTAssertEqual(e.code, "error.unknownAction")
            XCTAssertEqual(e.params["action"], "nonExistentAction")
        }
    }

    func test_unportedActionThrowsNotImplemented() throws {
        let q = try freshDB()
        // reconcileAccount is a real action but its domain handler isn't ported yet.
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "reconcileAccount", args: Args([:]))) { err in
            guard let e = err as? I18nError else { return XCTFail("expected I18nError") }
            XCTAssertEqual(e.code, "error.notImplemented")
        }
    }

    /// End-to-end: addTransaction through the chokepoint posts a balanced entry
    /// and moves the cached balance.
    func test_applyAddTransactionPostsEntry() throws {
        let q = try freshDB()
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','Cash','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('c1','l1',NULL,'Food','expense',0,datetime('now'),datetime('now'))")
        }
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-25),
            "merchant": .string("Coffee"), "categoryId": .string("c1"), "date": .string("2026-05-01"),
            "skipRules": .bool(true),
        ]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings"), 2)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id = 'a1'") ?? -1, -25, accuracy: 0.001)
        }
    }

    private func seedLedgerAccount(_ q: DatabaseQueue) throws {
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','Cash','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('c1','l1',NULL,'Food','expense',0,datetime('now'),datetime('now'))")
        }
    }

    /// adjustAccountBalance posts a one-leg adjustment that moves the balance to target.
    func test_applyAdjustAccountBalance() throws {
        let q = try freshDB()
        try seedLedgerAccount(q)
        try Apply.apply(dbQueue: q, action: "adjustAccountBalance", args: Args([
            "accountId": .string("a1"), "targetBalance": .double(500), "date": .string("2026-05-01"),
        ]))
        try q.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id = 'a1'") ?? -1, 500, accuracy: 0.001)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE kind = 'adjustment'"), 1)
        }
    }

    /// updateTransaction header edit (merchant + note) goes through rebuildEntry;
    /// balance unchanged; a money edit is refused (deferred).
    func test_applyUpdateTransactionHeader() throws {
        let q = try freshDB()
        try seedLedgerAccount(q)
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-25),
            "merchant": .string("Coffee"), "categoryId": .string("c1"), "date": .string("2026-05-01"), "skipRules": .bool(true),
        ]))
        let txId = try q.read { db in try String.fetchOne(db, sql: "SELECT id FROM postings WHERE account_id = 'a1'")! }
        try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
            "id": .string(txId), "patch": .object(["merchant": .string("Latte"), "note": .string("morning")]),
        ]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT description FROM entries"), "Latte")
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT notes FROM entries"), "morning")
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id = 'a1'") ?? -1, -25, accuracy: 0.001)
        }
        // A money edit is deferred → notImplemented.
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
            "id": .string(txId), "patch": .object(["amount": .double(-99)]),
        ]))) { err in
            XCTAssertEqual((err as? I18nError)?.code, "error.notImplemented.txMoneyEdit")
        }
    }

    /// deleteTransaction (by the Tx id = account-posting id) removes the entry + recomputes.
    func test_applyDeleteTransaction() throws {
        let q = try freshDB()
        try seedLedgerAccount(q)
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-25),
            "merchant": .string("Coffee"), "categoryId": .string("c1"), "date": .string("2026-05-01"), "skipRules": .bool(true),
        ]))
        let txId = try q.read { db in try String.fetchOne(db, sql: "SELECT id FROM postings WHERE account_id = 'a1'")! }
        try Apply.apply(dbQueue: q, action: "deleteTransaction", args: Args(["id": .string(txId)]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries"), 0)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id = 'a1'") ?? -1, 0, accuracy: 0.001)
        }
    }
}
