import XCTest
import GRDB
@testable import FinchCore

/// `saveTransaction` — one command carrying a whole purchase: header, payment
/// legs, category legs, tags and merchant. No `id` creates; an `id` replaces that
/// transaction's contents wholesale.
///
/// It exists because saving currently sends three to five separate commands, so
/// the screen owns the ordering and a part-way failure leaves the ledger
/// half-updated. That has already shipped as a bug once.
final class SaveTransactionTests: XCTestCase {

    private func seed() throws -> DatabaseQueue {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Card','credit_card','USD',0,1,1,1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at)
                VALUES ('c2','l1',NULL,'Household','expense',1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO tags (id,ledger_id,name,created_at,updated_at)
                VALUES ('t1','l1','Trip',datetime('now'),datetime('now'))
                """)
        }
        return q
    }

    /// A one-card, one-category purchase: the simplest payload there is.
    private func simplePayload(id: String? = nil, amount: Double = -100,
                               merchant: String = "Market", note: String? = nil,
                               account: String = "a1", tagIds: [String]? = nil) -> Args {
        Args(payloadDict(id: id, amount: amount, merchant: merchant, note: note,
                         account: account, tagIds: tagIds))
    }

    private func payloadDict(id: String? = nil, amount: Double = -100,
                             merchant: String = "Market", note: String? = nil,
                             account: String = "a1", tagIds: [String]? = nil) -> [String: JSONValue] {
        var o: [String: JSONValue] = [
            "ledgerId": .string("l1"), "date": .string("2026-06-01"), "time": .string("12:00"),
            "merchant": .string(merchant), "kind": .string("expense"), "currency": .string("USD"),
            "cells": .array([.object([
                "accountId": .string(account), "categoryId": .string("c1"), "amount": .double(amount),
            ])]),
        ]
        if let id { o["id"] = .string(id) }
        if let note { o["note"] = .string(note) }
        if let tagIds { o["tagIds"] = .array(tagIds.map { .string($0) }) }
        return o
    }

    private func clearedAt(_ q: DatabaseQueue, account: String) throws -> String? {
        try q.read { db in
            try String.fetchOne(db, sql: "SELECT cleared_at FROM postings WHERE account_id = ? AND cleared_at IS NOT NULL LIMIT 1", arguments: [account])
        }
    }
    private func markCleared(_ q: DatabaseQueue, account: String) throws {
        try q.write { db in
            try db.execute(sql: "UPDATE postings SET cleared_at = '2026-06-02T00:00:00Z' WHERE account_id = ?", arguments: [account])
        }
    }

    // MARK: reconcile marks — three cases, and (c) is what stops the wrong fix

    /// A tick means "I checked this against my statement", and `clearedBalance` is
    /// simply the sum of ticked legs. Moving the leg to another card means this
    /// card no longer owes it, so the tick cannot survive.
    ///
    /// This must fail on the SINGLE-account path today too: `updateTransaction`
    /// passes `cleared_at` through unconditionally even when the account moved.
    func test_reconcileMark_dropsWhenTheAccountChanges() throws {
        let q = try seed()
        let id = try Apply.applyReturningId(dbQueue: q, action: "saveTransaction", args: simplePayload())!
        try markCleared(q, account: "a1")

        try Apply.apply(dbQueue: q, action: "saveTransaction", args: simplePayload(id: id, account: "a2"))

        // Assert the SHAPE, not merely the absence of a mark on a2. Matching legs
        // by account makes "no mark on the new card" true for free, so a weaker
        // assertion would agree with the design rather than test it. An
        // implementation that matched by INDEX instead would reuse the old row —
        // same posting, new account, mark intact — and only this catches that.
        let legs = try q.read { db in
            try Row.fetchAll(db, sql: "SELECT account_id, cleared_at FROM postings WHERE entry_id = ? AND account_id IS NOT NULL",
                             arguments: [id])
        }
        XCTAssertEqual(legs.count, 1, "one payment, moved — not two")
        XCTAssertEqual(legs[0]["account_id"] as String?, "a2", "…now on the other card")
        XCTAssertNil(legs[0]["cleared_at"] as String?, "a moved payment is a NEW posting; the tick stayed with the old one")
    }

    /// Editing a ticked $60 payment to $70 silently moved a finished
    /// reconciliation by $10 while the screen still reported it square.
    func test_reconcileMark_dropsWhenTheAmountChanges() throws {
        let q = try seed()
        let id = try Apply.applyReturningId(dbQueue: q, action: "saveTransaction", args: simplePayload())!
        try markCleared(q, account: "a1")

        try Apply.apply(dbQueue: q, action: "saveTransaction", args: simplePayload(id: id, amount: -120))
        XCTAssertNil(try clearedAt(q, account: "a1"), "the tick was an assertion about an amount that has changed")
    }

    /// Without this, the obvious wrong fix — drop the tick on every edit — passes
    /// both tests above. A note changes nothing the account's balance owes.
    func test_reconcileMark_survivesAHeaderOnlyEdit() throws {
        let q = try seed()
        let id = try Apply.applyReturningId(dbQueue: q, action: "saveTransaction", args: simplePayload())!
        try markCleared(q, account: "a1")

        try Apply.apply(dbQueue: q, action: "saveTransaction", args: simplePayload(id: id, note: "receipt in the drawer"))
        XCTAssertNotNil(try clearedAt(q, account: "a1"), "a note does not change what this card owes")
    }

    // MARK: atomicity — the bug the whole command exists to remove

    /// The sheets fire three to five writes, so a payload that is partly valid
    /// lands partly. One command means all or nothing.
    func test_aRejectedLegSetLeavesTheHeaderUntouched() throws {
        let q = try seed()
        let id = try Apply.applyReturningId(dbQueue: q, action: "saveTransaction", args: simplePayload())!

        var bad = payloadDict(id: id, merchant: "Renamed")
        bad["cells"] = JSONValue.array([.object([
            "accountId": .string("nope"), "categoryId": .string("c1"), "amount": .double(-100),
        ])])
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "saveTransaction", args: Args(bad)))

        let merchant = try q.read { db in
            try String.fetchOne(db, sql: "SELECT description FROM entries WHERE id = ?", arguments: [id])
        }
        XCTAssertEqual(merchant, "Market", "the valid half must not land when the other half is refused")
    }

    // MARK: tags — which rebuildEntry silently ignores

    /// `entry_tags` is written only by `postEntry` and `postTransfer`;
    /// `rebuildEntry` never touches it, which is why `setTransactionTags` is a
    /// separate write in both sheets today.
    func test_tagsAndLegsChangeInOnePayload() throws {
        let q = try seed()
        let id = try Apply.applyReturningId(dbQueue: q, action: "saveTransaction", args: simplePayload(tagIds: ["t1"]))!

        try Apply.apply(dbQueue: q, action: "saveTransaction", args: simplePayload(id: id, amount: -140, tagIds: []))
        let (tags, amount) = try q.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entry_tags WHERE entry_id = ?", arguments: [id]) ?? -1,
             try Double.fetchOne(db, sql: "SELECT ROUND(SUM(amount_base), 2) FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [id]) ?? 0)
        }
        XCTAssertEqual(tags, 0, "tags are a set-replace, so clearing them clears them")
        XCTAssertEqual(amount, -140, accuracy: 0.001, "…in the same write that changed the legs")
    }

    /// Typing a merchant the ledger has never seen must not need a second command
    /// to create it first — that ordering is why a failed save can currently leave
    /// an orphan counterparty behind.
    func test_anUnknownMerchantIsCreatedInTheSameWrite() throws {
        let q = try seed()
        _ = try Apply.applyReturningId(dbQueue: q, action: "saveTransaction",
                                       args: simplePayload(merchant: "Brand New Shop"))
        let cp = try q.read { db in
            try String.fetchOne(db, sql: "SELECT id FROM counterparties WHERE name = ? COLLATE NOCASE", arguments: ["Brand New Shop"])
        }
        XCTAssertNotNil(cp, "resolve-or-create, in one write")
    }
}

/// The guards the Edit sheet's account editor depends on. It can send 1..N cards
/// for an existing purchase, so the engine has to be exact about what it accepts.
final class SaveTransactionAccountEditTests: XCTestCase {

    private func seed() throws -> DatabaseQueue {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Card','credit_card','USD',0,1,1,1,datetime('now'),datetime('now'))
                """)
        }
        return q
    }

    private func args(id: String? = nil, cells: [(String, Double)], kind: String = "expense") -> Args {
        var o: [String: JSONValue] = [
            "ledgerId": .string("l1"), "date": .string("2026-06-01"), "time": .string("12:00"),
            "merchant": .string("Market"), "kind": .string(kind), "currency": .string("USD"),
            "cells": .array(cells.map { .object([
                "accountId": .string($0.0), "categoryId": .string("c1"), "amount": .double($0.1),
            ])}),
        ]
        if let id { o["id"] = .string(id) }
        return Args(o)
    }

    /// Collapsing a split back to one card: the other payment's posting must go,
    /// not linger with a zero amount.
    func test_aTwoCardPurchaseCollapsesToOne() throws {
        let q = try seed()
        let id = try Apply.applyReturningId(dbQueue: q, action: "saveTransaction",
                                            args: args(cells: [("a1", -60), ("a2", -40)]))!
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: args(id: id, cells: [("a1", -100)]))

        let legs = try q.read { db in
            try Row.fetchAll(db, sql: "SELECT account_id, amount FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [id])
        }
        XCTAssertEqual(legs.count, 1, "the removed card's posting is gone, not zeroed")
        XCTAssertEqual(legs[0]["account_id"] as String?, "a1")
        XCTAssertEqual(legs[0]["amount"] as Double, -100, accuracy: 0.001)
        XCTAssertTrue(try Audit.run(on: q).isEmpty)
    }

    /// Zero cards is not a purchase.
    func test_zeroCardsIsRefused() throws {
        let q = try seed()
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "saveTransaction", args: args(cells: [])))
    }

    /// A share whose sign disagrees with the kind is REJECTED, never coerced.
    /// Coercing would silently record a purchase the user did not describe — an
    /// expense leg that adds money, or an income leg that removes it.
    func test_aShareWhoseSignDisagreesWithTheKindIsRejected() throws {
        let q = try seed()
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "saveTransaction",
                                             args: args(cells: [("a1", -60), ("a2", 40)]))) { error in
            XCTAssertEqual((error as? I18nError)?.code, "error.split.signMismatch",
                           "one card cannot pay a negative share of an expense while another receives")
        }
    }

    /// …and the same for income, so the rule is about agreement with `kind`
    /// rather than about negativity.
    func test_anIncomeShareThatRemovesMoneyIsRejected() throws {
        let q = try seed()
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "saveTransaction",
                                             args: args(cells: [("a1", 60), ("a2", -40)], kind: "income")))
    }
}
