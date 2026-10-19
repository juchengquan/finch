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

    /// rateToHub with no stored rate falls back to the static map, and saves no
    /// copy of it: the posting carries the rate it used.
    func test_rateToHubStaticFallback_savesNoCopy() throws {
        let q = try seeded(accountCcy: "EUR", base: "USD")   // no EUR rate seeded
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-10),
            "merchant": .string("Paris"), "categoryId": .string("food"),
            "date": .string("2026-05-09"), "skipRules": .bool(true)]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exchange_rates"), 0)
            // base amount = -10 EUR × 1.087 (static fallback) = -10.87 USD.
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount_base FROM postings WHERE account_id='a1'") ?? 0, -10.87, accuracy: 0.01)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT exchange_rate FROM postings WHERE account_id='a1'") ?? 0, 1.087, accuracy: 1e-6)
        }
    }

    // MARK: - No rate for the pair: refuse, never 1:1

    private func add(_ q: DatabaseQueue, amount: Double = -50000, currency: String? = nil,
                     date: String = "2026-05-09") throws {
        var args: [String: JSONValue] = [
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(amount),
            "merchant": .string("Seoul"), "categoryId": .string("food"),
            "date": .string(date), "skipRules": .bool(true)]
        if let currency { args["currency"] = .string(currency) }
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args(args))
    }

    private func assertNoRate(_ expr: @autoclosure () throws -> Void, from: String, to: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try expr(), file: file, line: line) { err in
            let e = err as? I18nError
            XCTAssertEqual(e?.code, "error.fx.noRate", file: file, line: line)
            XCTAssertEqual(e?.params["from"], from, file: file, line: line)
            XCTAssertEqual(e?.params["to"], to, file: file, line: line)
        }
    }

    /// ₩50,000 on a KRW account in a USD ledger, with no KRW rate anywhere, is
    /// refused — it used to be booked as 50,000 USD. Nothing is written, and no
    /// made-up 1.0 rate is pinned for KRW.
    func test_unratedAccountCurrency_refusesTheWrite() throws {
        let q = try seeded(accountCcy: "KRW", base: "USD")
        assertNoRate(try add(q), from: "KRW", to: "USD")
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exchange_rates"), 0)
        }
    }

    /// The same when it is the ledger's BASE that has no rate.
    func test_unratedBaseCurrency_refusesTheWrite() throws {
        let q = try seeded(accountCcy: "USD", base: "KRW")
        assertNoRate(try add(q, amount: -10), from: "USD", to: "KRW")
    }

    /// A foreign-currency amount typed on a rated account: refused too.
    func test_unratedTypedCurrency_refusesTheWrite() throws {
        let q = try seeded()
        assertNoRate(try add(q, currency: "KRW"), from: "KRW", to: "USD")
    }

    /// Once a real rate exists — even one dated BEFORE the refused attempt — it is
    /// what the write uses. The old write-through pinned 1.0 at the attempt's date,
    /// which then shadowed any earlier real rate for good.
    func test_aRateAddedLater_isUsed() throws {
        let q = try seeded(accountCcy: "KRW", base: "USD")
        XCTAssertThrowsError(try add(q))
        try Apply.apply(dbQueue: q, action: "setExchangeRate", args: Args([
            "date": .string("2026-05-01"), "currency": .string("KRW"), "rate": .double(0.00072)]))
        try add(q)
        try q.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount_base FROM postings WHERE account_id='a1'") ?? 0,
                           -36, accuracy: 0.001)
        }
    }

    /// A rate typed in by hand — the offline user's only way out — unblocks the
    /// refused write, keeps its "manual" tag, and is used as-is: the write reads it
    /// at its own date, so nothing derived is pinned over it.
    func test_aManuallyEnteredRate_unblocksTheRefusedWrite() throws {
        let q = try seeded(accountCcy: "KRW", base: "USD")
        assertNoRate(try add(q), from: "KRW", to: "USD")
        try Apply.apply(dbQueue: q, action: "setExchangeRate", args: Args([
            "date": .string("2026-05-09"), "currency": .string("KRW"), "rate": .double(0.00073),
            "source": .string("manual")]))
        try add(q)
        try q.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount_base FROM postings WHERE account_id='a1'") ?? 0,
                           -36.5, accuracy: 0.001)
            let rows = try Row.fetchAll(db, sql: "SELECT date, rate, source FROM exchange_rates WHERE currency='KRW'")
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows.first?["source"] as String?, "manual")
            XCTAssertEqual(rows.first?["rate"] as Double? ?? 0, 0.00073, accuracy: 1e-12)
        }
    }

    /// The same in a EUR ledger, where the form pivots through the EUR rate: a KRW
    /// rate entered as "1 KRW = 0.0007 EUR" (stored as 0.0007 × 1.10 USD) books
    /// ₩50,000 as €35 on that day.
    func test_aManualRate_inANonUSDLedger_booksAtTheTypedCrossRate() throws {
        let q = try seeded(accountCcy: "KRW", base: "EUR")
        try q.write { db in try db.execute(sql: "INSERT INTO exchange_rates (date,currency,rate,source) VALUES ('2026-05-01','EUR',1.10,'ECB')") }
        assertNoRate(try add(q), from: "KRW", to: "EUR")
        try Apply.apply(dbQueue: q, action: "setExchangeRate", args: Args([
            "date": .string("2026-05-09"), "currency": .string("KRW"), "rate": .double(0.0007 * 1.10),
            "source": .string("manual")]))
        try add(q)
        try q.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount_base FROM postings WHERE account_id='a1'") ?? 0,
                           -35, accuracy: 0.001)
        }
    }

    /// A rate on either side of the date is still found (on-or-after for a backdate).
    func test_aRateDatedAfterTheEntry_isStillUsed() throws {
        let q = try seeded(accountCcy: "KRW", base: "USD")
        try q.write { db in try db.execute(sql: "INSERT INTO exchange_rates (date,currency,rate) VALUES ('2026-06-01','KRW',0.0007)") }
        try add(q)
        try q.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount_base FROM postings WHERE account_id='a1'") ?? 0,
                           -35, accuracy: 0.001)
        }
    }

    /// Same currency needs no rate at all.
    func test_sameCurrency_needsNoRate() throws {
        let q = try seeded(accountCcy: "KRW", base: "KRW")
        try add(q)
        try q.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount_base FROM postings WHERE account_id='a1'") ?? 0,
                           -50000, accuracy: 0.001)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exchange_rates"), 0)
        }
    }

    // MARK: - A rate the user set or fetched always outranks a copy

    private func setRate(_ q: DatabaseQueue, _ date: String, _ rate: Double,
                         _ currency: String = "KRW", source: String = "manual") throws {
        try Apply.apply(dbQueue: q, action: "setExchangeRate", args: Args([
            "date": .string(date), "currency": .string(currency), "rate": .double(rate),
            "source": .string(source)]))
    }

    private func baseOf(_ q: DatabaseQueue, amount: Double, date: String) throws -> Double? {
        try q.read { db in
            try Double.fetchOne(db, sql: """
                SELECT p.amount_base FROM postings p JOIN entries e ON e.id = p.entry_id
                WHERE p.account_id = 'a1' AND p.amount = ? AND e.date = ?
                """, arguments: [amount, date])
        }
    }

    private func rateRows(_ q: DatabaseQueue) throws -> [Row] {
        try q.read { try Row.fetchAll($0, sql: "SELECT date, currency, rate, source FROM exchange_rates ORDER BY date, currency") }
    }

    /// F1: a mistyped manual KRW rate (0.0073 for 0.00073) is corrected. Entries
    /// added after the correction book at it, on the date of an earlier entry and
    /// after it. The earlier entry used to save a copy of 0.0073 under its date,
    /// and that copy outranked the corrected rate: ₩50,000 still booked as $365.
    func test_aCorrectedRate_isWhatLaterEntriesUse() throws {
        let q = try seeded(accountCcy: "KRW", base: "USD")
        try setRate(q, "2026-05-01", 0.0073)                 // mistyped
        try add(q, amount: -50000, date: "2026-05-10")
        XCTAssertEqual(try baseOf(q, amount: -50000, date: "2026-05-10") ?? 0, -365, accuracy: 0.001)
        XCTAssertEqual(try rateRows(q).count, 1, "the conversion saved no copy of the rate")

        try setRate(q, "2026-05-01", 0.00073)                // corrected
        try add(q, amount: -50001, date: "2026-05-10")
        try add(q, amount: -50000, date: "2026-05-12")
        XCTAssertEqual(try baseOf(q, amount: -50001, date: "2026-05-10") ?? 0, -36.5, accuracy: 0.001)
        XCTAssertEqual(try baseOf(q, amount: -50000, date: "2026-05-12") ?? 0, -36.5, accuracy: 0.001)
    }

    /// F1: a manual rate dated between an older rate and a later entry is the
    /// nearest one, so it is what an entry after it uses.
    func test_aBackdatedRate_isWhatLaterEntriesUse() throws {
        let q = try seeded(accountCcy: "KRW", base: "USD")
        try setRate(q, "2026-05-01", 0.00072, source: "ECB")
        try add(q, amount: -50000, date: "2026-05-10")
        XCTAssertEqual(try baseOf(q, amount: -50000, date: "2026-05-10") ?? 0, -36, accuracy: 0.001)

        try setRate(q, "2026-05-05", 0.0008)                 // backdated, by hand
        try add(q, amount: -50001, date: "2026-05-10")
        try add(q, amount: -50000, date: "2026-05-12")
        XCTAssertEqual(try baseOf(q, amount: -50001, date: "2026-05-10") ?? 0, -40, accuracy: 0.001)
        XCTAssertEqual(try baseOf(q, amount: -50000, date: "2026-05-12") ?? 0, -40, accuracy: 0.001)
        // The entry booked before the backdated rate keeps what it was booked at.
        XCTAssertEqual(try baseOf(q, amount: -50000, date: "2026-05-10") ?? 0, -36, accuracy: 0.001)
    }

    /// Copies saved by earlier versions are ignored too, whatever they say: a real
    /// rate is found past them.
    func test_anOldCopy_isIgnored() throws {
        let q = try seeded(accountCcy: "KRW", base: "USD")
        try setRate(q, "2026-05-01", 0.00073)
        try q.write { db in
            try db.execute(sql: "INSERT INTO exchange_rates (date, currency, rate, source) VALUES ('2026-05-08', 'KRW', 0.0073, 'derived')")
        }
        try add(q, amount: -50000, date: "2026-05-08")
        try add(q, amount: -50001, date: "2026-05-10")
        XCTAssertEqual(try baseOf(q, amount: -50000, date: "2026-05-08") ?? 0, -36.5, accuracy: 0.001)
        XCTAssertEqual(try baseOf(q, amount: -50001, date: "2026-05-10") ?? 0, -36.5, accuracy: 0.001)
    }

    /// W1: a 1:1 KRW rate left by pre-#820 code (`'derived'`, exactly 1) does not
    /// book new money. A new ₩10,000 entry is refused like any unrated write —
    /// it used to book silently as $10,000 and save another 1:1 copy dated today.
    func test_aLeftover1to1Rate_doesNotBookNewMoney() throws {
        let q = try seeded(accountCcy: "KRW", base: "USD")
        try q.write { db in
            try db.execute(sql: "INSERT INTO exchange_rates (date, currency, rate, source) VALUES ('2026-05-01', 'KRW', 1, 'derived')")
        }
        assertNoRate(try add(q, amount: -10000, date: "2026-05-09"), from: "KRW", to: "USD")
        assertNoRate(try add(q, amount: -10000, date: "2026-05-01"), from: "KRW", to: "USD")
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exchange_rates"), 1)
        }
        // Once a real rate is entered — the "Enter a rate" path — the write books at it.
        try setRate(q, "2026-05-09", 0.00073)
        try add(q, amount: -10000, date: "2026-05-09")
        XCTAssertEqual(try baseOf(q, amount: -10000, date: "2026-05-09") ?? 0, -7.3, accuracy: 0.001)
    }

    /// An entry booked before a correction keeps its figure until it is edited in
    /// a way that re-values it. A note keeps the booked rate; a new amount or date
    /// looks the rate up again and finds the corrected one (there is no copy of the
    /// old rate under the entry's date to find instead).
    func test_anExistingEntry_keepsItsRateUntilAnEditRevaluesIt() throws {
        let q = try seeded(accountCcy: "KRW", base: "USD")
        try setRate(q, "2026-05-01", 0.0073)                 // mistyped
        try add(q, amount: -50000, date: "2026-05-10")
        try setRate(q, "2026-05-01", 0.00073)                // corrected
        let id = try q.read { db in try String.fetchOne(db, sql: "SELECT id FROM postings WHERE account_id = 'a1'")! }
        func edit(_ patch: [String: JSONValue]) throws {
            try Apply.apply(dbQueue: q, action: "updateTransaction",
                            args: Args(["id": .string(id), "patch": .object(patch)]))
        }

        try edit(["note": .string("dinner")])
        XCTAssertEqual(try baseOf(q, amount: -50000, date: "2026-05-10") ?? 0, -365, accuracy: 0.001,
                       "a header edit keeps the rate the entry was booked at")

        try edit(["date": .string("2026-05-11")])
        XCTAssertEqual(try baseOf(q, amount: -50000, date: "2026-05-11") ?? 0, -36.5, accuracy: 0.001,
                       "a date edit re-values at the rate for the new date")

        try edit(["amount": .double(-60000)])
        XCTAssertEqual(try baseOf(q, amount: -60000, date: "2026-05-11") ?? 0, -43.8, accuracy: 0.001)
        XCTAssertEqual(try rateRows(q).count, 1, "no edit saved a copy of the rate")
        try q.read { db in XCTAssertTrue(try Audit.run(on: db, ledgerId: "l1", checkBalances: true).isEmpty) }
    }
}
