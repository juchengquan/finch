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
        // createBudget is a real action but its domain handler isn't ported yet.
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "createBudget", args: Args([:]))) { err in
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
}
