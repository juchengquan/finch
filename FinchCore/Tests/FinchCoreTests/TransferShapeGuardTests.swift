import XCTest
import GRDB
@testable import FinchCore

/// The transfer guards belong in `validateShape`, not in `postTransfer`.
///
/// `postTransfer` is one caller. `validateShape` runs on EVERY write path —
/// including `rebuildEntry` and `saveTransaction` — so a guard living only in
/// `postTransfer` protects the `createTransfer` action and nothing else.
final class TransferShapeGuardTests: XCTestCase {

    private func twoAccounts() throws -> DatabaseQueue {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Savings','cash','USD',0,1,1,1,datetime('now'),datetime('now'))
                """)
        }
        return q
    }

    /// The hole this task closes. `validateShape`'s `.transfer` case checks only
    /// that there are exactly two account legs and no plain category leg — so a
    /// "transfer" from an account to ITSELF satisfies it and posts, moving money
    /// nowhere while looking like a real transfer in the feed.
    ///
    /// `postTransfer` refuses it, but `postTransfer` is not the only way in.
    func test_aTransferBetweenOneAccountAndItself_isRefused() throws {
        let q = try twoAccounts()
        XCTAssertThrowsError(try q.write { db in
            try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: "l1", date: "2026-06-01", time: "12:00",
                description: "Transfer", kind: .transfer,
                legs: [
                    .account(Entries.AccountLeg(accountId: "a1", amount: -100)),
                    .account(Entries.AccountLeg(accountId: "a1", amount: 100)),
                ], skipRules: true))
        }) { error in
            XCTAssertEqual((error as? I18nError)?.code, "error.transfer.sameAccount",
                           "a transfer needs two DIFFERENT accounts")
        }
    }

    /// Zero moves nothing. Guarded in `postTransfer` only, so any other path
    /// could post it.
    func test_aZeroAmountTransfer_isRefused() throws {
        let q = try twoAccounts()
        XCTAssertThrowsError(try q.write { db in
            try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: "l1", date: "2026-06-01", time: "12:00",
                description: "Transfer", kind: .transfer,
                legs: [
                    .account(Entries.AccountLeg(accountId: "a1", amount: 0)),
                    .account(Entries.AccountLeg(accountId: "a2", amount: 0)),
                ], skipRules: true))
        }) { error in
            XCTAssertEqual((error as? I18nError)?.code, "error.transfer.amountGt0")
        }
    }

    /// Both accounts hold USD, so the two sides must agree. A mismatch here is a
    /// typo, and `appendResidue` would otherwise force it to balance through the
    /// FX equity leg — hiding the error as a phantom exchange-rate difference
    /// between two accounts that share a currency.
    func test_aSameCurrencyTransferWhoseSidesDisagree_isRefused() throws {
        let q = try twoAccounts()
        XCTAssertThrowsError(try q.write { db in
            try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: "l1", date: "2026-06-01", time: "12:00",
                description: "Transfer", kind: .transfer,
                legs: [
                    .account(Entries.AccountLeg(accountId: "a1", amount: -100)),
                    .account(Entries.AccountLeg(accountId: "a2", amount: 90)),
                ], skipRules: true))
        }) { error in
            XCTAssertEqual((error as? I18nError)?.code, "error.transfer.sameCurrencyMismatch")
        }
    }

    /// A legitimate transfer must still post — without this, "refuse everything"
    /// passes all three tests above.
    func test_anOrdinaryTransferStillPosts() throws {
        let q = try twoAccounts()
        let eid = try q.write { db in
            try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: "l1", date: "2026-06-01", time: "12:00",
                description: "Transfer", kind: .transfer,
                legs: [
                    .account(Entries.AccountLeg(accountId: "a1", amount: -100)),
                    .account(Entries.AccountLeg(accountId: "a2", amount: 100)),
                ], skipRules: true))
        }
        XCTAssertFalse(eid.isEmpty)
        XCTAssertTrue(try Audit.run(on: q).isEmpty, "and the ledger stays clean")
    }
}

/// `saveTransaction` handles transfers too — one command for every kind, so the
/// sheets stop needing a separate `saveTransfer()` path with its own ordering.
final class SaveTransferTests: XCTestCase {

    private func twoAccounts() throws -> DatabaseQueue {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Savings','cash','USD',0,1,1,1,datetime('now'),datetime('now'))
                """)
        }
        return q
    }

    private func transferArgs(id: String? = nil, from: Double = -100, to: Double = 100,
                              fromAccount: String = "a1") -> Args {
        var o: [String: JSONValue] = [
            "ledgerId": .string("l1"), "date": .string("2026-06-01"), "time": .string("12:00"),
            "merchant": .string(""), "kind": .string("transfer"), "currency": .string("USD"),
            "cells": .array([
                .object(["accountId": .string(fromAccount), "amount": .double(from)]),
                .object(["accountId": .string("a2"), "amount": .double(to)]),
            ]),
        ]
        if let id { o["id"] = .string(id) }
        return Args(o)
    }

    /// A transfer has NO category leg, so the balancing leg `saveTransaction`
    /// computes for every other kind must not be emitted here.
    func test_aTransferPostsWithNoCategoryLeg() throws {
        let q = try twoAccounts()
        let id = try Apply.applyReturningId(dbQueue: q, action: "saveTransaction", args: transferArgs())!
        let (acct, cat) = try q.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [id]) ?? 0,
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE entry_id = ? AND category_id IS NOT NULL", arguments: [id]) ?? 0)
        }
        XCTAssertEqual(acct, 2, "two account legs")
        XCTAssertEqual(cat, 0, "and no category leg — that is what makes it a transfer")
        XCTAssertTrue(try Audit.run(on: q).isEmpty)
    }

    /// Engine-authored, not the sheet's job: the memos name the other side, so a
    /// transfer reads correctly in each account's feed.
    func test_aTransferGetsItsDerivedDescriptionAndMemos() throws {
        let q = try twoAccounts()
        let id = try Apply.applyReturningId(dbQueue: q, action: "saveTransaction", args: transferArgs())!
        let (desc, memos) = try q.read { db in
            (try String.fetchOne(db, sql: "SELECT description FROM entries WHERE id = ?", arguments: [id]),
             try String.fetchAll(db, sql: "SELECT memo FROM postings WHERE entry_id = ? AND account_id IS NOT NULL ORDER BY sort_order", arguments: [id]))
        }
        XCTAssertEqual(desc, "Transfer")
        XCTAssertEqual(memos.sorted(), ["Transfer from Cash", "Transfer to Savings"].sorted(),
                       "each leg names the OTHER side, so the row reads correctly in that account's feed")
    }

    /// Decision 30, applied to transfers: editing the AMOUNT unticks BOTH legs,
    /// because each tick asserted something a different amount no longer supports.
    /// `Transfers.update` preserved them deliberately; that is now reversed.
    func test_editingAClearedTransfersAmount_unticksBothLegs() throws {
        let q = try twoAccounts()
        let id = try Apply.applyReturningId(dbQueue: q, action: "saveTransaction", args: transferArgs())!
        try q.write { db in
            try db.execute(sql: "UPDATE postings SET cleared_at = '2026-06-02T00:00:00Z' WHERE entry_id = ?", arguments: [id])
        }
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: transferArgs(id: id, from: -120, to: 120))
        let stillCleared = try q.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE entry_id = ? AND cleared_at IS NOT NULL", arguments: [id]) ?? -1
        }
        XCTAssertEqual(stillCleared, 0, "both sides changed, so both ticks go")
    }
}

/// A transfer has no single "purchase currency": 100 USD leaves one card and 90
/// EUR arrives at another, and the user types both. So a transfer's cell amounts
/// are in each CARD's own currency — the one documented exception to Decision 16,
/// and it follows from what a transfer is rather than working around it.
final class CrossCurrencyTransferTests: XCTestCase {

    private func seed() throws -> DatabaseQueue {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('eur','l1','Euro Card','credit_card','EUR',0,1,1,1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: "INSERT INTO exchange_rates (date,currency,rate) VALUES ('2026-06-01','EUR',1.10)")
        }
        return q
    }

    func test_eachSideIsStoredInItsOwnCurrency() throws {
        let q = try seed()
        let id = try Apply.applyReturningId(dbQueue: q, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "date": .string("2026-06-01"), "time": .string("12:00"),
            "merchant": .string(""), "kind": .string("transfer"), "currency": .string("USD"),
            "cells": .array([
                .object(["accountId": .string("a1"), "amount": .double(-110)]),   // USD out
                .object(["accountId": .string("eur"), "amount": .double(100)]),   // EUR in
            ]),
        ]))!
        let legs = try q.read { db in
            try Row.fetchAll(db, sql: "SELECT account_id, amount, currency FROM postings WHERE entry_id = ? AND account_id IS NOT NULL ORDER BY amount", arguments: [id])
        }
        XCTAssertEqual(legs.count, 2)
        // The euro side must be 100 EUR — the number the user typed — not 100 USD
        // converted into euros, which would silently record a different transfer.
        let eur = legs.first { ($0["account_id"] as String?) == "eur" }
        XCTAssertEqual(eur?["amount"] as Double? ?? 0, 100, accuracy: 0.001, "the amount as typed, in that card's currency")
        XCTAssertEqual(eur?["currency"] as String?, "EUR")
        let usd = legs.first { ($0["account_id"] as String?) == "a1" }
        XCTAssertEqual(usd?["amount"] as Double? ?? 0, -110, accuracy: 0.001)
        XCTAssertTrue(try Audit.run(on: q).isEmpty, "and it balances through the FX residue")
    }
}
