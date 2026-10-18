import XCTest
import GRDB
@testable import FinchCore

/// A cross-currency transfer where the user typed BOTH amounts states exactly what
/// moved, so the two amounts imply the rate. When one side has no exchange rate it
/// is valued at the other side's base amount instead of refusing the write — the
/// entry balances with no FX leg, and the implied rate is never saved as a rate.
/// Only when NEITHER side can be valued in base is it still `error.fx.noRate`.
final class TransferImpliedRateTests: XCTestCase {

    /// A USD ledger (unless `base` says otherwise) with a1 in `fromCcy` and a2 in
    /// `toCcy`. No exchange rates at all: KRW and VND have no static fallback.
    private func seeded(base: String = "USD", fromCcy: String = "USD", toCcy: String = "KRW") throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L',?,1,datetime('now'),datetime('now'))", arguments: [base])
            for (id, name, ccy, order) in [("a1", "Checking", fromCcy, 0), ("a2", "Seoul", toCcy, 1)] {
                try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES (?,'l1',?,'cash',?,0,?,1,1,datetime('now'),datetime('now'))",
                               arguments: [id, name, ccy, order])
            }
        }
        return q
    }

    private func transfer(_ q: DatabaseQueue, from: Double = 100, to: Double? = 137000) throws {
        var args: [String: JSONValue] = [
            "fromAccountId": .string("a1"), "toAccountId": .string("a2"),
            "fromAmount": .double(from), "date": .string("2026-05-16")]
        if let to { args["toAmount"] = .double(to) }
        try Apply.apply(dbQueue: q, action: "createTransfer", args: Args(args))
    }

    private func assertNoRate(_ expr: @autoclosure () throws -> Void,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try expr(), file: file, line: line) {
            XCTAssertEqual(($0 as? I18nError)?.code, "error.fx.noRate", file: file, line: line)
        }
    }

    /// Both legs, the FX legs, and every saved rate — what each test pins.
    private struct Booked { var from: Row; var to: Row; var fxLegs: Int; var rates: Int; var sum: Double }
    private func booked(_ q: DatabaseQueue) throws -> Booked {
        try q.read { db in
            Booked(
                from: try Row.fetchOne(db, sql: "SELECT amount, amount_base, exchange_rate FROM postings WHERE account_id='a1'")!,
                to: try Row.fetchOne(db, sql: "SELECT amount, amount_base, exchange_rate FROM postings WHERE account_id='a2'")!,
                fxLegs: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE account_id IS NULL") ?? -1,
                rates: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exchange_rates") ?? -1,
                sum: try Double.fetchOne(db, sql: "SELECT ROUND(SUM(amount_base),2) FROM postings") ?? -1)
        }
    }

    /// $100 out of Checking, ₩137,000 into Seoul, and no KRW rate anywhere: it
    /// books. The KRW leg is valued at the $100 that left, so the entry balances
    /// with no FX leg, and no KRW rate is invented in the rates table.
    func test_bothAmountsTyped_unratedReceivingSide_books() throws {
        let q = try seeded()
        try transfer(q)
        let b = try booked(q)
        XCTAssertEqual(b.from["amount_base"] as Double, -100, accuracy: 0.001)
        XCTAssertEqual(b.to["amount"] as Double, 137000, accuracy: 0.001)
        XCTAssertEqual(b.to["amount_base"] as Double, 100, accuracy: 0.001)
        XCTAssertEqual(b.to["exchange_rate"] as Double, 0.00073, accuracy: 1e-9)   // 100 / 137,000, as applied
        XCTAssertEqual(b.sum, 0, accuracy: 0.001)
        XCTAssertEqual(b.fxLegs, 0)
        XCTAssertEqual(b.rates, 0)
        // The account balance is the typed figure, in its own currency.
        XCTAssertEqual(try q.read { try Double.fetchOne($0, sql: "SELECT current_balance FROM accounts WHERE id='a2'") } ?? 0, 137000, accuracy: 0.001)
    }

    /// The reverse direction: the SENDING side is the unrated one.
    func test_bothAmountsTyped_unratedSendingSide_books() throws {
        let q = try seeded(fromCcy: "KRW", toCcy: "USD")
        try transfer(q, from: 137000, to: 100)
        let b = try booked(q)
        XCTAssertEqual(b.from["amount_base"] as Double, -100, accuracy: 0.001)
        XCTAssertEqual(b.to["amount_base"] as Double, 100, accuracy: 0.001)
        XCTAssertEqual(b.fxLegs, 0)
        XCTAssertEqual(b.rates, 0)
    }

    /// A side that IS the ledger's base needs no rate even when the base itself has
    /// none: a KRW ledger, ₩137,000 out, $100 in — the USD leg is valued at ₩137,000.
    func test_theBaseSideValuesTheOther_evenWhenTheBaseHasNoRate() throws {
        let q = try seeded(base: "KRW", fromCcy: "KRW", toCcy: "USD")
        try transfer(q, from: 137000, to: 100)
        let b = try booked(q)
        XCTAssertEqual(b.to["amount_base"] as Double, 137000, accuracy: 0.001)
        XCTAssertEqual(b.fxLegs, 0)
        XCTAssertEqual(b.rates, 0)
    }

    /// Without the received amount there is nothing to imply a rate from: refused.
    func test_onlyTheSentAmount_isStillRefused() throws {
        let q = try seeded()
        assertNoRate(try transfer(q, to: nil))
        try q.read { db in XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries"), 0) }
    }

    /// Neither side can be valued in base (KRW → VND in a USD ledger): refused, and
    /// nothing is written.
    func test_neitherSideValued_isStillRefused() throws {
        let q = try seeded(fromCcy: "KRW", toCcy: "VND")
        assertNoRate(try transfer(q, from: 137000, to: 2_500_000))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exchange_rates"), 0)
        }
    }

    /// When both sides DO have a rate nothing changes: each leg is valued at its own
    /// rate and the difference is the FX leg, as before.
    func test_bothSidesRated_keepTheirOwnRatesAndTheFxLeg() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "setExchangeRate", args: Args([
            "date": .string("2026-05-16"), "currency": .string("KRW"), "rate": .double(0.00072)]))
        try transfer(q)
        let b = try booked(q)
        XCTAssertEqual(b.to["amount_base"] as Double, 98.64, accuracy: 0.001)   // 137,000 × 0.00072
        XCTAssertEqual(b.fxLegs, 1)
        XCTAssertEqual(b.sum, 0, accuracy: 0.001)
    }

    /// The path the Add sheet takes: `saveTransaction` with two account cells.
    func test_saveTransaction_transferWithBothAmounts_books() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "merchant": .string(""), "date": .string("2026-05-16"),
            "time": .string("12:00"), "kind": .string("transfer"),
            "cells": .array([
                .object(["accountId": .string("a1"), "categoryId": .null, "amount": .double(-100)]),
                .object(["accountId": .string("a2"), "categoryId": .null, "amount": .double(137000)]),
            ])]))
        let b = try booked(q)
        XCTAssertEqual(b.to["amount_base"] as Double, 100, accuracy: 0.001)
        XCTAssertEqual(b.fxLegs, 0)
        XCTAssertEqual(b.rates, 0)
    }

    /// A booked transfer stays editable while the rate is still missing: moving its
    /// date re-values the legs, and the unrated one follows the other again.
    func test_movingTheDate_reValuesWithoutARate() throws {
        let q = try seeded()
        try transfer(q)
        let posting = try q.read { try String.fetchOne($0, sql: "SELECT id FROM postings WHERE account_id='a2'")! }
        try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
            "id": .string(posting), "patch": .object(["date": .string("2026-05-20")])]))
        let b = try booked(q)
        XCTAssertEqual(b.to["amount_base"] as Double, 100, accuracy: 0.001)
        XCTAssertEqual(b.fxLegs, 0)
        XCTAssertEqual(try q.read { try String.fetchOne($0, sql: "SELECT date FROM entries") }, "2026-05-20")
    }

    /// Changing the ledger's base re-values every leg; the unrated one follows its
    /// partner rather than blocking the whole change.
    func test_changingTheBase_reValuesWithoutARate() throws {
        let q = try seeded()
        try transfer(q)
        try Apply.apply(dbQueue: q, action: "changeLedgerBase", args: Args([
            "ledgerId": .string("l1"), "newBase": .string("EUR")]))
        let b = try booked(q)
        let fromBase = b.from["amount_base"] as Double
        XCTAssertEqual(fromBase, -92, accuracy: 0.001)   // $100 at EUR's static 1.087
        XCTAssertEqual(b.to["amount_base"] as Double, -fromBase, accuracy: 0.001)
        XCTAssertEqual(b.fxLegs, 0)
    }
}
