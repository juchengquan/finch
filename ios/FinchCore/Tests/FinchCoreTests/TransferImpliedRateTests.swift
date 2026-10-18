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

    // MARK: editing a transfer valued from its partner, after a rate appears

    private func setRate(_ q: DatabaseQueue, _ date: String, _ ccy: String = "KRW", _ rate: Double = 0.00073) throws {
        try Apply.apply(dbQueue: q, action: "setExchangeRate", args: Args([
            "date": .string(date), "currency": .string(ccy), "rate": .double(rate)]))
    }

    private func entryId(_ q: DatabaseQueue) throws -> String {
        try q.read { try String.fetchOne($0, sql: "SELECT id FROM entries")! }
    }

    /// What the Edit sheet sends: both legs, every time, plus the header.
    private func saveInSheet(_ q: DatabaseQueue, from: Double = 100, to: Double = 137000,
                             date: String = "2026-05-16", note: String? = nil) throws {
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: Args([
            "id": .string(try entryId(q)), "ledgerId": .string("l1"), "merchant": .string("Transfer"),
            "date": .string(date), "time": .string("12:00"), "kind": .string("transfer"),
            "note": note.map(JSONValue.string) ?? .null,
            "cells": .array([
                .object(["accountId": .string("a1"), "categoryId": .null, "amount": .double(-from)]),
                .object(["accountId": .string("a2"), "categoryId": .null, "amount": .double(to)]),
            ])]))
    }

    /// KRW rows other than the ones a test set itself — a rate saved under the
    /// transfer's date would be the later rate, written back to May.
    private func krwRows(_ q: DatabaseQueue) throws -> [String] {
        try q.read { try String.fetchAll($0, sql: "SELECT date FROM exchange_rates WHERE currency='KRW' ORDER BY date") }
    }

    /// The pairing, unchanged: the KRW leg is still worth exactly the dollars, at
    /// the rate the two amounts imply, with no FX leg.
    private func assertPaired(_ q: DatabaseQueue, usd: Double = 100, krw: Double = 137000,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        let b = try booked(q)
        XCTAssertEqual(b.from["amount_base"] as Double, -usd, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(b.to["amount"] as Double, krw, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(b.to["amount_base"] as Double, usd, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(b.to["exchange_rate"] as Double, ((usd / krw) * 1e6).rounded() / 1e6, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(b.fxLegs, 0, file: file, line: line)
        XCTAssertEqual(b.sum, 0, accuracy: 0.001, file: file, line: line)
    }

    /// $100 → ₩137,000 booked in May with no KRW rate; a refresh then adds one
    /// dated October. Editing only the note in the sheet must leave the transfer as
    /// it was booked. It used to re-value the KRW leg at the October rate ($95.90),
    /// add a $4.10 FX leg, and save the October rate under May 16.
    func test_aLaterRate_noteEditInTheSheet_keepsThePairing() throws {
        let q = try seeded()
        try transfer(q)
        try setRate(q, "2026-10-19", "KRW", 0.0007)
        try saveInSheet(q, note: "rent deposit")
        try assertPaired(q)
        XCTAssertEqual(try krwRows(q), ["2026-10-19"])
        XCTAssertEqual(try q.read { try String.fetchOne($0, sql: "SELECT notes FROM entries") }, "rent deposit")
    }

    /// Moving the date — from the sheet or from updateTransaction — to a day that
    /// still has no KRW rate on or before it keeps the pairing; the October rate is
    /// not reached back for.
    func test_aLaterRate_movingTheDate_keepsThePairing() throws {
        let q = try seeded()
        try transfer(q)
        try setRate(q, "2026-10-19", "KRW", 0.0007)
        let posting = try q.read { try String.fetchOne($0, sql: "SELECT id FROM postings WHERE account_id='a2'")! }
        try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
            "id": .string(posting), "patch": .object(["date": .string("2026-05-20")])]))
        try assertPaired(q)
        try saveInSheet(q, date: "2026-05-22")
        try assertPaired(q)
        XCTAssertEqual(try krwRows(q), ["2026-10-19"])
    }

    /// Changing the ledger's base after the later rate appeared: the KRW leg still
    /// follows the dollars, now in euros.
    func test_aLaterRate_changingTheBase_keepsThePairing() throws {
        let q = try seeded()
        try transfer(q)
        try setRate(q, "2026-10-19", "KRW", 0.0007)
        try Apply.apply(dbQueue: q, action: "changeLedgerBase", args: Args([
            "ledgerId": .string("l1"), "newBase": .string("EUR")]))
        let b = try booked(q)
        let fromBase = b.from["amount_base"] as Double
        XCTAssertEqual(fromBase, -92, accuracy: 0.001)   // $100 at EUR's static 1.087
        XCTAssertEqual(b.to["amount_base"] as Double, -fromBase, accuracy: 0.001)
        XCTAssertEqual(b.fxLegs, 0)
        XCTAssertEqual(try krwRows(q), ["2026-10-19"])
    }

    /// Both amounts changed through updateTransfer: the two legs stay paired, the
    /// KRW leg valued at the new dollars. Each leg used to scale its own old base,
    /// which left a $2.19 FX leg ($100 → ₩140,000).
    func test_bothAmountsChanged_updateTransfer_keepsThePairing() throws {
        let q = try seeded()
        try transfer(q)
        try Apply.apply(dbQueue: q, action: "updateTransfer", args: Args([
            "id": .string(try entryId(q)),
            "patch": .object(["fromAmount": .double(100), "toAmount": .double(140000)])]))
        try assertPaired(q, usd: 100, krw: 140000)
        try Apply.apply(dbQueue: q, action: "updateTransfer", args: Args([
            "id": .string(try entryId(q)), "patch": .object(["fromAmount": .double(120)])]))
        try assertPaired(q, usd: 120, krw: 168000)
    }

    /// Both amounts changed in the sheet, after the later rate appeared: paired,
    /// valued from the dollar side.
    func test_aLaterRate_bothAmountsChangedInTheSheet_keepsThePairing() throws {
        let q = try seeded()
        try transfer(q)
        try setRate(q, "2026-10-19", "KRW", 0.0007)
        try saveInSheet(q, from: 120, to: 160000)
        try assertPaired(q, usd: 120, krw: 160000)
        try saveInSheet(q, from: 150, to: 160000)   // only one side changed
        try assertPaired(q, usd: 150, krw: 160000)
        XCTAssertEqual(try krwRows(q), ["2026-10-19"])
    }

    /// A rate dated ON or BEFORE the transfer is a real rate for that day, so a
    /// re-valuation uses it, exactly as booking the transfer fresh would: each leg
    /// at its own rate, with the FX leg. A note edit still re-values nothing.
    func test_anEarlierRate_reValuationUsesIt_aNoteEditDoesNot() throws {
        let q = try seeded()
        try transfer(q)
        try setRate(q, "2026-05-01", "KRW", 0.00072)
        try saveInSheet(q, note: "still as booked")
        try assertPaired(q)
        let posting = try q.read { try String.fetchOne($0, sql: "SELECT id FROM postings WHERE account_id='a2'")! }
        try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
            "id": .string(posting), "patch": .object(["date": .string("2026-05-20")])]))
        let b = try booked(q)
        XCTAssertEqual(b.to["amount_base"] as Double, 98.64, accuracy: 0.001)   // 137,000 × 0.00072
        XCTAssertEqual(b.fxLegs, 1)
        XCTAssertEqual(b.sum, 0, accuracy: 0.001)
    }

    /// Booking fresh when the only KRW rate is dated later gives the same transfer
    /// as booking first and refreshing after: valued from the dollars, and the
    /// later rate is not saved under the transfer's date.
    func test_aLaterRateOnly_bookingBothAmounts_valuesFromThePartner() throws {
        let q = try seeded()
        try setRate(q, "2026-10-19", "KRW", 0.0007)
        try transfer(q)
        try assertPaired(q)
        XCTAssertEqual(try krwRows(q), ["2026-10-19"])
    }

    /// A 'derived' copy dated before the transfer is not a rate for that day: the
    /// lookup skips copies, so this check must too. A copy of the October rate
    /// saved under May 1 by an older version leaves a date move paired, no FX leg.
    func test_aDerivedCopyDatedEarlier_doesNotCountAsARate() throws {
        let q = try seeded()
        try transfer(q)
        try setRate(q, "2026-10-19", "KRW", 0.0007)
        try q.write { try $0.execute(sql: "INSERT INTO exchange_rates (date, currency, rate, source) VALUES ('2026-05-01','KRW',0.0007,'derived')") }
        let posting = try q.read { try String.fetchOne($0, sql: "SELECT id FROM postings WHERE account_id='a2'")! }
        try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
            "id": .string(posting), "patch": .object(["date": .string("2026-05-20")])]))
        try assertPaired(q)
    }
}
