import XCTest
import GRDB
@testable import FinchCore

/// A UNIQUE dedup collision should surface as a friendly localized I18nError
/// rather than a raw SQLite constraint error — port of the web's
/// _shared/with-dedup-message.ts behavior (Dedup.wrap).
final class DedupTests: XCTestCase {
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

    private func addCoffee(_ q: DatabaseQueue) throws {
        // `time` is required for a non-NULL dedup_hash, so an identical second
        // insert collides on idx_entry_dedup.
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-4.50),
            "merchant": .string("Blue Bottle"), "categoryId": .string("c1"),
            "date": .string("2026-05-01"), "time": .string("08:30"), "skipRules": .bool(true),
        ]))
    }

    func test_duplicateTransaction_throwsFriendlyError() throws {
        let q = try seeded()
        try addCoffee(q)
        XCTAssertThrowsError(try addCoffee(q)) { err in
            guard let e = err as? I18nError else { return XCTFail("expected I18nError, got \(err)") }
            XCTAssertEqual(e.code, "error.duplicate.txn")
            XCTAssertTrue(e.message.contains("duplicate"), e.message)
        }
        // The first transaction is still the only one — the dup never landed.
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries"), 1)
        }
    }

    func test_duplicateBudget_throwsFriendlyError() throws {
        let q = try seeded()
        let mk: () throws -> Void = {
            try Apply.apply(dbQueue: q, action: "createBudget", args: Args([
                "ledgerId": .string("l1"), "name": .string("Groceries"), "amount": .double(300),
                "frequency": .string("monthly"), "startDate": .string("2026-05-01"),
            ]))
        }
        try mk()
        XCTAssertThrowsError(try mk()) { err in
            guard let e = err as? I18nError else { return XCTFail("expected I18nError, got \(err)") }
            XCTAssertEqual(e.code, "error.duplicate.budget")
        }
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM budgets"), 1)
        }
    }
}
