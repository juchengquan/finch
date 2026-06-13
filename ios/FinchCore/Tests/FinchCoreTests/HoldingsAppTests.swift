import XCTest
import GRDB
@testable import FinchCore

final class HoldingsAppTests: XCTestCase {
    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('inv','l1','Brokerage','investment','USD',0,0,1,1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('cash','l1','Cash','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
        }
        return q
    }

    func test_holdingCrud() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createHolding", args: Args(["id": .string("h1"), "accountId": .string("inv"), "symbol": .string("aapl"), "shares": .double(10), "costBasis": .double(1000)]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT symbol FROM holdings WHERE id='h1'"), "AAPL")  // uppercased
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT shares FROM holdings WHERE id='h1'") ?? 0, 10, accuracy: 0.001)
        }
        try Apply.apply(dbQueue: q, action: "setHoldingPrice", args: Args(["id": .string("h1"), "price": .double(150), "date": .string("2026-05-01")]))
        XCTAssertEqual(try q.read { db in try Double.fetchOne(db, sql: "SELECT last_price FROM holdings WHERE id='h1'") ?? 0 }, 150, accuracy: 0.001)
        try Apply.apply(dbQueue: q, action: "updateHolding", args: Args(["id": .string("h1"), "patch": .object(["shares": .double(12)])]))
        XCTAssertEqual(try q.read { db in try Double.fetchOne(db, sql: "SELECT shares FROM holdings WHERE id='h1'") ?? 0 }, 12, accuracy: 0.001)
        // non-investment account rejected
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "createHolding", args: Args(["accountId": .string("cash"), "symbol": .string("X"), "shares": .double(1), "costBasis": .double(1)]))) {
            XCTAssertEqual(($0 as? I18nError)?.code, "error.holding.notInvestment")
        }
    }

    func test_exchangeRate() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "setExchangeRate", args: Args(["date": .string("2026-05-01"), "currency": .string("eur"), "rate": .double(1.1)]))
        XCTAssertEqual(try q.read { db in try Double.fetchOne(db, sql: "SELECT rate FROM exchange_rates WHERE currency='EUR'") ?? 0 }, 1.1, accuracy: 0.0001)
        // USD hub rejected
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "setExchangeRate", args: Args(["date": .string("2026-05-01"), "currency": .string("USD"), "rate": .double(1)]))) {
            XCTAssertEqual(($0 as? I18nError)?.code, "error.fx.usdHub")
        }
        try Apply.apply(dbQueue: q, action: "deleteExchangeRate", args: Args(["date": .string("2026-05-01"), "currency": .string("EUR")]))
        XCTAssertEqual(try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exchange_rates") }, 0)
    }

    func test_appState() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "setDisplayCurrency", args: Args(["ledgerId": .string("l1"), "currency": .string("EUR")]))
        try Apply.apply(dbQueue: q, action: "setMobileTabIds", args: Args(["ids": .array([.string("accounts"), .string("budgets")])]))
        try Apply.apply(dbQueue: q, action: "setBackupRetention", args: Args(["retention": .double(30)]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT value FROM app_state WHERE key='displayCurrencyByLedger'"), "{\"l1\":\"EUR\"}")
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT value FROM app_state WHERE key='mobileTabs'"), "[\"accounts\",\"budgets\"]")
            let backup = try String.fetchOne(db, sql: "SELECT value FROM app_state WHERE key='backupConfig'") ?? ""
            XCTAssertTrue(backup.contains("\"retention\":30"), backup)
        }
    }
}
