import XCTest
import GRDB
@testable import FinchCore

/// Cross-currency FX port: foreign-currency entries (orig_* + double conversion)
/// and rateToHub's static fallback + write-through (mirrors the web's
/// queries/rates.ts + the JPY system.test.ts case).
final class FxTests: XCTestCase {
    private func seeded(accountCcy: String = "USD", base: String = "USD") throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L',?,1,datetime('now'),datetime('now'))", arguments: [base])
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','Acct','cash',?,0,0,1,1,datetime('now'),datetime('now'))", arguments: [accountCcy])
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('food','l1',NULL,'Food','expense',0,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,system,sort_order,created_at,updated_at) VALUES ('sysfx','l1',NULL,'FX','equity','fx',9002,datetime('now'),datetime('now'))")
        }
        return q
    }

    /// A JPY purchase on a USD account: orig_* carry the JPY figure, amount +
    /// amount_base are the USD conversion, the entry still balances.
    func test_foreignCurrencyTransaction() throws {
        let q = try seeded()
        try q.write { db in try db.execute(sql: "INSERT INTO exchange_rates (date,currency,rate) VALUES ('2026-05-08','JPY',0.0065)") }
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-3820),
            "currency": .string("JPY"), "merchant": .string("Yodobashi"), "categoryId": .string("food"),
            "date": .string("2026-05-08"), "skipRules": .bool(true)]))
        try q.read { db in
            let acct = try Row.fetchOne(db, sql: "SELECT orig_amount, orig_currency, amount, amount_base, exchange_rate FROM postings WHERE account_id='a1'")!
            XCTAssertEqual(acct["orig_amount"] as Double, -3820, accuracy: 0.001)
            XCTAssertEqual(acct["orig_currency"] as String, "JPY")
            XCTAssertEqual(acct["amount"] as Double, -3820 * 0.0065, accuracy: 0.01)        // account-native (USD)
            XCTAssertEqual(acct["amount_base"] as Double, -3820 * 0.0065, accuracy: 0.01)   // base (USD)
            XCTAssertEqual(acct["exchange_rate"] as Double, 1, accuracy: 0.001)             // USD→USD
            // The whole entry balances to the cent.
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT ROUND(SUM(amount_base),2) FROM postings p JOIN entries e ON e.id=p.entry_id WHERE e.kind='expense'") ?? -1, 0, accuracy: 0.001)
        }
    }

    /// rateToHub with no stored rate falls back to the static map AND writes the
    /// resolved rate through as a 'derived' row pinned under the date.
    func test_rateToHubStaticFallbackWriteThrough() throws {
        let q = try seeded(accountCcy: "EUR", base: "USD")   // no EUR rate seeded
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-10),
            "merchant": .string("Paris"), "categoryId": .string("food"),
            "date": .string("2026-05-09"), "skipRules": .bool(true)]))
        try q.read { db in
            // EUR static fallback = 1.087 → a 'derived' row pinned at the txn date.
            let r = try Row.fetchOne(db, sql: "SELECT rate, source FROM exchange_rates WHERE currency='EUR' AND date='2026-05-09'")
            XCTAssertEqual(r?["rate"] as Double?, 1.087)
            XCTAssertEqual(r?["source"] as String?, "derived")
            // base amount = -10 EUR × 1.087 = -10.87 USD.
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount_base FROM postings WHERE account_id='a1'") ?? 0, -10.87, accuracy: 0.01)
        }
    }
}
