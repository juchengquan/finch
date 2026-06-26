import XCTest
import GRDB
@testable import FinchCore

final class AccountsDomainTests: XCTestCase {
    private func ledgerDB() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('c1','l1',NULL,'Food','expense',0,datetime('now'),datetime('now'))")
        }
        return q
    }

    func test_createAccountWithOpeningBalance() throws {
        let q = try ledgerDB()
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "id": .string("a1"), "ledgerId": .string("l1"), "name": .string("Cash"),
            "type": .string("cash"), "currency": .string("USD"), "openingBalance": .double(500),
        ]))
        try q.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='a1'") ?? -1, 500, accuracy: 0.001)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE id='open-a1' AND kind='opening'"), 1)
            // credit_card defaults include_in_net_worth=1 (counts toward net worth / liabilities)
        }
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args(["id": .string("cc"), "ledgerId": .string("l1"), "name": .string("Visa"), "type": .string("credit_card")]))
        XCTAssertEqual(try q.read { db in try Int.fetchOne(db, sql: "SELECT include_in_net_worth FROM accounts WHERE id='cc'") }, 1)
        // unknown type rejected
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "createAccount", args: Args(["name": .string("X"), "type": .string("checking")]))) {
            XCTAssertEqual(($0 as? I18nError)?.code, "error.account.unknownType")
        }
    }

    func test_updateArchiveDelete() throws {
        let q = try ledgerDB()
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args(["id": .string("a1"), "ledgerId": .string("l1"), "name": .string("Cash"), "type": .string("cash")]))
        try Apply.apply(dbQueue: q, action: "updateAccount", args: Args(["id": .string("a1"), "patch": .object(["name": .string("Wallet")])]))
        try Apply.apply(dbQueue: q, action: "archiveAccount", args: Args(["id": .string("a1")]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT name FROM accounts WHERE id='a1'"), "Wallet")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT is_active FROM accounts WHERE id='a1'"), 0)
            XCTAssertNotNil(try String.fetchOne(db, sql: "SELECT archived_at FROM accounts WHERE id='a1'") ?? nil)
        }
        try Apply.apply(dbQueue: q, action: "deleteAccount", args: Args(["id": .string("a1")]))
        XCTAssertEqual(try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM accounts") }, 0)
    }

    func test_deleteAccountWithTransactionsRejected() throws {
        let q = try ledgerDB()
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args(["id": .string("a1"), "ledgerId": .string("l1"), "name": .string("Cash"), "type": .string("cash")]))
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args(["ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-25), "merchant": .string("Coffee"), "categoryId": .string("c1"), "date": .string("2026-05-01"), "skipRules": .bool(true)]))
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "deleteAccount", args: Args(["id": .string("a1")]))) {
            XCTAssertEqual(($0 as? I18nError)?.code, "error.account.hasTransactions")
        }
    }
}
