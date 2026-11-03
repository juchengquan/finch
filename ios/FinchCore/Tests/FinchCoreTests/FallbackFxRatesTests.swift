import XCTest
import GRDB
@testable import FinchCore

/// `FallbackFxRates`: the 1.0 rates pre-#820 code pinned for a currency with no
/// rate are flagged, and nothing else is — not a typed, fetched or imported rate,
/// not a derived copy of a real rate, not a dollar peg. The entries it booked at
/// 1:1 are found from their postings, whatever has happened to the rows since.
final class FallbackFxRatesTests: XCTestCase {

    /// A USD ledger `l1` with a KRW account, plus a KRW-based ledger `l2` with a USD
    /// account — the second is the case where the BASE was the unrated side.
    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            for (id, base) in [("l1", "USD"), ("l2", "KRW")] {
                try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES (?,?,?,0,datetime('now'),datetime('now'))", arguments: [id, id, base])
                try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES (?,?,NULL,'Food','expense',0,datetime('now'),datetime('now'))", arguments: ["food-\(id)", id])
                try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,system,sort_order,created_at,updated_at) VALUES (?,?,NULL,'FX','equity','fx',9002,datetime('now'),datetime('now'))", arguments: ["fx-\(id)", id])
            }
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('krw','l1','Won','cash','KRW',0,0,1,1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('usd','l2','Dollars','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
        }
        return q
    }

    /// Exactly the row pre-#820 `rateToHub` wrote when it fell through to `?? 1`.
    private func pinTheOldWay(_ q: DatabaseQueue, _ currency: String, _ date: String) throws {
        try q.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO exchange_rates (date, currency, rate, source) VALUES (?, ?, ?, 'derived')",
                           arguments: [date, currency, 1.0])
        }
    }

    /// The 1.0 rows for `pins`, with whatever `book` writes booked 1:1 against them
    /// the way pre-#820 code booked it. The lookup no longer reads `'derived'` rows,
    /// so the rows stand in as real 1.0 rates while `book` runs and only then take
    /// the `'derived'` tag the old code gave them.
    private func bookTheOldWay(_ q: DatabaseQueue, _ pins: [(currency: String, date: String)],
                               _ book: () throws -> Void) throws {
        for p in pins { try rate(q, p.date, p.currency, 1, "pre-820") }
        try book()
        try q.write { db in
            try db.execute(sql: "UPDATE exchange_rates SET source = 'derived' WHERE source = 'pre-820'")
        }
    }

    private func rate(_ q: DatabaseQueue, _ date: String, _ currency: String, _ rate: Double, _ source: String?) throws {
        try q.write { db in
            try db.execute(sql: "INSERT INTO exchange_rates (date, currency, rate, source) VALUES (?, ?, ?, ?)",
                           arguments: [date, currency, rate, source])
        }
    }

    private func spend(_ q: DatabaseQueue, ledger: String, account: String, amount: Double, date: String) throws {
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string(ledger), "accountId": .string(account), "amount": .double(amount),
            "merchant": .string("Shop"), "categoryId": .string("food-\(ledger)"),
            "date": .string(date), "skipRules": .bool(true)]))
    }

    private func suspects(_ q: DatabaseQueue) throws -> [FallbackFxRates.Suspect] {
        try q.read { try FallbackFxRates.find($0) }
    }

    /// The pre-#820 shape: a missing KRW rate pinned as 1.0, then entries booked
    /// against it at 1:1 — in a USD ledger (KRW leg) and a KRW ledger (USD leg).
    private func seedTheBug(_ q: DatabaseQueue) throws {
        try bookTheOldWay(q, [("KRW", "2026-05-09"), ("KRW", "2026-05-12")]) {
            try spend(q, ledger: "l1", account: "krw", amount: -50000, date: "2026-05-09")
            try spend(q, ledger: "l1", account: "krw", amount: -12000, date: "2026-05-09")
            try spend(q, ledger: "l2", account: "usd", amount: -10, date: "2026-05-12")
        }
        try pinTheOldWay(q, "THB", "2026-05-20")   // pinned, nothing on that date
    }

    /// Rates that are genuine, several of them near or at 1, which must survive.
    private func seedGenuine(_ q: DatabaseQueue) throws {
        try rate(q, "2026-05-01", "KRW", 0.00072, "ECB")     // fetched
        try rate(q, "2026-05-02", "CHF", 1.13, "derived")    // derived copy of a real rate
        try rate(q, "2026-05-03", "EUR", 1, "derived")       // a static-fallback currency
        try rate(q, "2026-05-04", "BMD", 1, "derived")       // pegged 1:1, so 1 was right
        try rate(q, "2026-05-05", "XAU", 1, nil)             // typed, no source
        try rate(q, "2026-05-06", "AUD", 1, "manual")        // typed as 1 on purpose…
        try rate(q, "2026-05-07", "AUD", 1, "derived")       // …so its derived copy is real
        try rate(q, "2026-05-08", "CAD", 1, "er-api")        // fetched at 1
    }

    func test_flagsOnlyTheOldFallbackRows() throws {
        let q = try seeded()
        try seedGenuine(q)
        try seedTheBug(q)
        XCTAssertEqual(try suspects(q), [
            .init(currency: "KRW", date: "2026-05-09", entryCount: 2),
            .init(currency: "KRW", date: "2026-05-12", entryCount: 1),
            .init(currency: "THB", date: "2026-05-20", entryCount: 0),
        ])
    }

    /// A clean database, or one with only genuine rates, has nothing to show.
    func test_nothingToFlag_withoutTheBug() throws {
        let q = try seeded()
        XCTAssertEqual(try suspects(q), [])
        try seedGenuine(q)
        XCTAssertEqual(try suspects(q), [])
    }

    /// The entries were booked 1:1 — the reason the rows matter.
    func test_theSeededEntriesReallyWereBookedOneToOne() throws {
        let q = try seeded()
        try seedTheBug(q)
        try q.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount_base FROM postings WHERE account_id='krw' AND amount=-50000"), -50000)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount_base FROM postings WHERE account_id='usd'"), -10)
        }
    }

    /// Removing the flagged rows through `deleteExchangeRate` (what the app does)
    /// leaves every genuine rate, and the entries already booked keep their figures.
    /// The next KRW write converts at the real rate instead of 1:1.
    func test_removingTheSuspects_keepsGenuineRates_andTheNextWriteUsesTheRealRate() throws {
        let q = try seeded()
        try seedGenuine(q)
        try seedTheBug(q)
        let genuineBefore = try q.read { db in
            try Row.fetchAll(db, sql: "SELECT date, currency, rate, source FROM exchange_rates WHERE NOT (source = 'derived' AND rate = 1 AND currency IN ('KRW','THB')) ORDER BY date, currency")
        }
        for s in try suspects(q) {
            try Apply.apply(dbQueue: q, action: "deleteExchangeRate",
                            args: Args(["date": .string(s.date), "currency": .string(s.currency)]))
        }
        XCTAssertEqual(try suspects(q), [])
        try q.read { db in
            XCTAssertEqual(try Row.fetchAll(db, sql: "SELECT date, currency, rate, source FROM exchange_rates ORDER BY date, currency"),
                           genuineBefore)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount_base FROM postings WHERE account_id='krw' AND amount=-50000"), -50000)
        }
        try spend(q, ledger: "l1", account: "krw", amount: -50000, date: "2026-05-10")
        try q.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount_base FROM postings p JOIN entries e ON e.id = p.entry_id WHERE p.account_id='krw' AND e.date='2026-05-10'") ?? 0,
                           -36, accuracy: 0.001)
        }
    }

    /// The entries `rates` stand for, read from the review as the app reads them.
    private func entryIds(_ q: DatabaseQueue, _ rates: [FallbackFxRates.Suspect]) throws -> Set<String> {
        let r = try review(q)
        return rates.reduce(into: Set<String>()) { $0.formUnion(r.entryIds(for: $1)) }
    }

    /// The list behind a rate is the entries its count counted: the same ids, and
    /// one row each in the ledger they are in.
    func test_theListedEntriesAreTheCountedOnes() throws {
        let q = try seeded()
        try seedGenuine(q)
        try seedTheBug(q)
        let all = try suspects(q)
        for s in all {
            XCTAssertEqual(try entryIds(q, [s]).count, s.entryCount, "\(s.currency) \(s.date)")
        }
        let l1 = try Projection.run(dbQueue: q, ledgerId: "l1")
        let l2 = try Projection.run(dbQueue: q, ledgerId: "l2")
        // KRW on 05-09 converted two purchases in the USD ledger…
        let may9 = try entryIds(q, [all[0]])
        XCTAssertEqual(FallbackFxRates.rows(l1, entryIds: may9).map(\.merchant), ["Shop", "Shop"])
        XCTAssertEqual(Set(FallbackFxRates.rows(l1, entryIds: may9).compactMap(\.entryId)), may9)
        // …and on 05-12 one in the KRW ledger, which the USD ledger cannot show.
        let may12 = try entryIds(q, [all[1]])
        XCTAssertEqual(FallbackFxRates.rows(l2, entryIds: may12).count, 1)
        XCTAssertEqual(FallbackFxRates.rows(l1, entryIds: may12), [])
        // The total spans both ledgers, and the unused THB rate adds nothing.
        XCTAssertEqual(try entryIds(q, all).count, 3)
        XCTAssertEqual(try entryIds(q, [all[2]]), [])
    }

    /// One row per ENTRY however the projection splits it: a transfer is one row
    /// (the side it leaves, not two legs cancelling to zero), and an entry two rates
    /// converted is counted once in the total.
    func test_aTransferIsOneRow_andAnEntryTwoRatesConvertedIsCountedOnce() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('thb','l1','Baht','cash','THB',0,1,1,1,datetime('now'),datetime('now'))")
        }
        try bookTheOldWay(q, [("KRW", "2026-05-09"), ("THB", "2026-05-09")]) {
            try Apply.apply(dbQueue: q, action: "createTransfer", args: Args([
                "fromAccountId": .string("krw"), "toAccountId": .string("thb"),
                "fromAmount": .double(30000), "toAmount": .double(30000), "date": .string("2026-05-09")]))
        }
        let all = try suspects(q)
        XCTAssertEqual(all.map(\.entryCount), [1, 1], "the transfer converted through both rates")
        let ids = try entryIds(q, all)
        XCTAssertEqual(ids.count, 1, "the total counts the transfer once")

        let legs = try Projection.run(dbQueue: q, ledgerId: "l1")
        XCTAssertEqual(legs.count, 2, "the projection has a row per leg")
        let rows = FallbackFxRates.rows(legs, entryIds: ids)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.account, "krw", "the leg the money leaves")
        XCTAssertLessThan(rows.first?.amount ?? 0, 0)
    }

    /// Removing the rates does not lose the entries: they are found from their
    /// postings, so they stay listed until they are corrected.
    func test_theEntriesAreStillFoundAfterTheRatesAreRemoved() throws {
        let q = try seeded()
        try seedTheBug(q)
        let all = try suspects(q)
        let before = try entryIds(q, all)
        for s in all {
            try Apply.apply(dbQueue: q, action: "deleteExchangeRate",
                            args: Args(["date": .string(s.date), "currency": .string(s.currency)]))
        }
        XCTAssertEqual(try suspects(q), [])
        XCTAssertEqual(try entryIds(q, all), before)
    }

    // MARK: Entries found from their postings (F3)

    private func review(_ q: DatabaseQueue) throws -> FallbackFxRates.Review {
        try q.read { try FallbackFxRates.review($0) }
    }

    private func entryId(_ q: DatabaseQueue, account: String, amount: Double) throws -> String {
        try q.read { db in
            try XCTUnwrap(String.fetchOne(db, sql: "SELECT entry_id FROM postings WHERE account_id = ? AND amount = ?",
                                          arguments: [account, amount]))
        }
    }

    /// A refresh on the day of a 1.0 row replaces it (one row per currency per day),
    /// but the entries booked with it earlier that day are still booked 1:1. The
    /// review used to find entries through the rows, so these two dropped out.
    func test_aRefreshThatReplacesTheRowKeepsItsEntries() throws {
        let q = try seeded()
        try seedTheBug(q)
        try Apply.apply(dbQueue: q, action: "setExchangeRate", args: Args([
            "date": .string("2026-05-09"), "currency": .string("KRW"),
            "rate": .double(0.00072), "source": .string("ECB")]))
        let r = try review(q)
        XCTAssertEqual(r.rates.map(\.date), ["2026-05-12", "2026-05-20"], "the replaced row is no longer suspect")
        XCTAssertEqual(r.entryIds, [try entryId(q, account: "krw", amount: -50000),
                                    try entryId(q, account: "krw", amount: -12000),
                                    try entryId(q, account: "usd", amount: -10)],
                       "the two purchases of 05-09 are still booked 1:1")
    }

    /// An entry saved again once the currency has a real rate is booked at that rate,
    /// and leaves the review. It used to be counted for as long as its date matched.
    func test_aCorrectedEntryLeavesTheReview() throws {
        let q = try seeded()
        try seedTheBug(q)
        try rate(q, "2026-05-01", "KRW", 0.00072, "manual")
        let fixed = try entryId(q, account: "krw", amount: -50000)
        try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
            "id": .string(fixed), "patch": .object(["amount": .double(-50000), "date": .string("2026-05-09")])]))
        try q.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount_base FROM postings WHERE account_id='krw' AND amount=-50000") ?? 0,
                           -36, accuracy: 0.001, "the re-save converted at the real rate")
        }
        let r = try review(q)
        XCTAssertFalse(r.entryIds.contains(fixed), "a corrected entry is still counted")
        XCTAssertEqual(r.entryIds.count, 2)
        XCTAssertEqual(r.rates.first { $0.date == "2026-05-09" }?.entryCount, 1)
    }

    /// In a ledger whose base has a real rate, a currency valued at one dollar is
    /// not booked at a rate of 1: ₩50,000 in a CNY ledger came out at ¥362,318.84
    /// (50,000 / 0.138). Found all the same, and still found after a refresh.
    func test_aLedgerWithAnotherBaseIsCovered() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l3','l3','CNY',0,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('food-l3','l3',NULL,'Food','expense',0,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,system,sort_order,created_at,updated_at) VALUES ('fx-l3','l3',NULL,'FX','equity','fx',9002,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('krw3','l3','Won','cash','KRW',0,0,1,1,datetime('now'),datetime('now'))")
        }
        try bookTheOldWay(q, [("KRW", "2026-05-09")]) {
            try spend(q, ledger: "l3", account: "krw3", amount: -50000, date: "2026-05-09")
        }
        try q.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount_base FROM postings WHERE account_id='krw3'") ?? 0,
                           -362_318.84, accuracy: 0.01)
        }
        let booked = try entryId(q, account: "krw3", amount: -50000)
        XCTAssertEqual(try review(q).entryIds, [booked])
        try rate(q, "2026-05-01", "KRW", 0.00072, "ECB")
        try Apply.apply(dbQueue: q, action: "setExchangeRate", args: Args([
            "date": .string("2026-05-09"), "currency": .string("KRW"),
            "rate": .double(0.00072), "source": .string("ECB")]))
        XCTAssertEqual(try review(q).entryIds, [booked], "a refresh hid the entry")
        XCTAssertEqual(try review(q).entries.first?.currencies, ["KRW"], "KRW was the side valued at one dollar")
    }

    /// An amount typed in an unrated currency on an account in another one: the
    /// posting's own figure is in the account's currency, and only `orig_amount`
    /// shows it was converted 1:1.
    func test_anAmountTypedInTheUnratedCurrencyIsFound() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('card','l1','Card','credit_card','USD',0,1,1,1,datetime('now'),datetime('now'))")
        }
        try bookTheOldWay(q, [("KRW", "2026-05-09")]) {
            try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
                "ledgerId": .string("l1"), "accountId": .string("card"), "amount": .double(-50000),
                "currency": .string("KRW"), "merchant": .string("Shop"), "categoryId": .string("food-l1"),
                "date": .string("2026-05-09"), "skipRules": .bool(true)]))
        }
        try rate(q, "2026-05-01", "KRW", 0.00072, "ECB")
        let r = try review(q)
        XCTAssertEqual(r.entryIds, [try entryId(q, account: "card", amount: -50000)])
        XCTAssertEqual(r.rates.map(\.entryCount), [1])
    }

    /// A transfer saved unchanged keeps the values it was booked at (#830) — but not
    /// one booked at 1:1, or "save it again" would leave it in the review for good.
    func test_aTransferBookedOneToOneIsRevaluedWhenSavedAgain() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('bank','l1','Bank','savings','USD',0,1,1,1,datetime('now'),datetime('now'))")
        }
        try bookTheOldWay(q, [("KRW", "2026-05-09")]) {
            try Apply.apply(dbQueue: q, action: "createTransfer", args: Args([
                "fromAccountId": .string("krw"), "toAccountId": .string("bank"),
                "fromAmount": .double(137000), "toAmount": .double(100), "date": .string("2026-05-09")]))
        }
        let leg = try q.read { db in
            try XCTUnwrap(String.fetchOne(db, sql: "SELECT id FROM postings WHERE account_id = 'krw'"))
        }
        let booked = try entryId(q, account: "krw", amount: -137000)
        XCTAssertEqual(try review(q).entryIds, [booked])
        try rate(q, "2026-05-01", "KRW", 0.00073, "ECB")

        // What the Edit sheet sends for a transfer, amounts untouched.
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: Args([
            "id": .string(leg), "ledgerId": .string("l1"), "merchant": .string(""),
            "date": .string("2026-05-09"), "kind": .string("transfer"), "status": .string("confirmed"),
            "cells": .array([
                .object(["accountId": .string("krw"), "categoryId": .null, "amount": .double(-137000)]),
                .object(["accountId": .string("bank"), "categoryId": .null, "amount": .double(100)]),
            ]),
            "tagIds": .array([])]))
        try q.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount_base FROM postings WHERE account_id = 'krw'") ?? 0,
                           -100.01, accuracy: 0.001, "the won leg is valued at the real rate")
        }
        XCTAssertEqual(try review(q).entries, [], "the corrected transfer is still listed")
    }

    /// Conversions at the rate on record are never listed, 1:1 or not: a currency
    /// the user rated at exactly 1, a dollar peg, and ordinary foreign entries.
    func test_entriesBookedAtARealRateAreNotListed() throws {
        let q = try seeded()
        try q.write { db in
            for (id, ccy) in [("aud", "AUD"), ("bmd", "BMD"), ("eur", "EUR")] {
                try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES (?,'l1',?,'cash',?,0,0,1,1,datetime('now'),datetime('now'))",
                               arguments: [id, ccy, ccy])
            }
        }
        try rate(q, "2026-05-01", "KRW", 0.00072, "ECB")
        try rate(q, "2026-05-01", "AUD", 1, "manual")
        try rate(q, "2026-05-01", "BMD", 1, "manual")
        try rate(q, "2026-05-01", "EUR", 1.08, "ECB")
        for (account, amount) in [("krw", -50000.0), ("aud", -20.0), ("bmd", -30.0), ("eur", -40.0)] {
            try spend(q, ledger: "l1", account: account, amount: amount, date: "2026-05-09")
        }
        try spend(q, ledger: "l2", account: "usd", amount: -10, date: "2026-05-09")
        XCTAssertEqual(try review(q), .empty)
    }

    /// Since #820 a write in an unrated currency is refused, so it pins nothing new.
    func test_post820_unratedWritePinsNothingToFlag() throws {
        let q = try seeded()
        XCTAssertThrowsError(try spend(q, ledger: "l1", account: "krw", amount: -50000, date: "2026-05-09"))
        XCTAssertEqual(try suspects(q), [])
    }
}
