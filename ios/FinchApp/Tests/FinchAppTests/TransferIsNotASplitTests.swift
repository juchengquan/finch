import XCTest
import GRDB
@testable import FinchApp
import FinchCore

/// Editing a transfer must not open the split-purchase page.
///
/// A transfer is one entry with two account legs, which is exactly what a
/// purchase paid from two cards looks like if you only count legs. The Edit
/// sheet seeded its card split from every leg of the entry, so a transfer
/// arrived as a "two-card purchase": ✓ became Next, and Next led to a grid
/// that could never balance. Through the real engine, so the projection's
/// shape is the one the sheet actually sees.
final class TransferIsNotASplitTests: XCTestCase {

    private func seed() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','Cash','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a2','l1','Card','credit_card','USD',0,1,1,1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('c1','l1',NULL,'Food','expense',0,datetime('now'),datetime('now'))")
        }
        return q
    }

    /// What the sheet's Save button does: `.notNeeded` is ✓, anything else is Next.
    private func page2(opening txn: Tx, in txns: [Tx]) -> PurchaseFlow.Page2 {
        PurchaseFlow.page2(accounts: PurchaseFlow.paymentLegs(of: txn, in: txns).count,
                           categories: txn.splits?.count ?? 0)
    }

    func test_aTransferSavesFromPageOne() throws {
        let q = try seed()
        try Apply.apply(dbQueue: q, action: "createTransfer", args: Args([
            "fromAccountId": .string("a1"), "toAccountId": .string("a2"),
            "fromAmount": .double(250), "date": .string("2026-06-01")]))
        let txns = try Projection.run(dbQueue: q, ledgerId: "l1")
        let legs = txns.filter { $0.kind == "transfer" }
        XCTAssertEqual(legs.count, 2, "both halves are in the projection")
        XCTAssertEqual(Set(legs.compactMap(\.entryId)).count, 1,
                       "and share one entry — the shape that was misread")

        for leg in legs {
            XCTAssertTrue(PurchaseFlow.paymentLegs(of: leg, in: txns).isEmpty)
            XCTAssertEqual(page2(opening: leg, in: txns), .notNeeded,
                           "opening either half of a transfer shows ✓, not Next")
        }
    }

    /// The guard must not cost a genuine split-tender purchase its page 2.
    func test_aPurchasePaidFromTwoCardsStillGoesToPageTwo() throws {
        let q = try seed()
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "merchant": .string("Market"),
            "date": .string("2026-06-01"), "kind": .string("expense"),
            "currency": .string("USD"), "skipRules": .bool(true),
            "cells": .array([
                .object(["accountId": .string("a1"), "categoryId": .string("c1"), "amount": .double(-60)]),
                .object(["accountId": .string("a2"), "categoryId": .string("c1"), "amount": .double(-40)]),
            ]),
        ]))
        let txns = try Projection.run(dbQueue: q, ledgerId: "l1")
        let tapped = try XCTUnwrap(txns.first { $0.account == "a1" })
        XCTAssertNil(tapped.groupId, "one entry paid from two cards, not a grid")

        XCTAssertEqual(PurchaseFlow.paymentLegs(of: tapped, in: txns).count, 2)
        XCTAssertEqual(page2(opening: tapped, in: txns), .list)
    }

    // MARK: - The feed row's "part of one purchase" mark

    /// The feed row reads the same classification. It marked a row as "part of one
    /// purchase" whenever its entry had more than one account leg, so both halves of
    /// every transfer carried the mark, and VoiceOver read "Part of one purchase" on
    /// money that was never spent.
    func test_aTransferRowIsNotMarkedAsPartOfOnePurchase() throws {
        let q = try seed()
        try Apply.apply(dbQueue: q, action: "createTransfer", args: Args([
            "fromAccountId": .string("a1"), "toAccountId": .string("a2"),
            "fromAmount": .double(250), "date": .string("2026-06-01")]))
        let legs = try Projection.run(dbQueue: q, ledgerId: "l1").filter { $0.kind == "transfer" }
        XCTAssertEqual(legs.count, 2)
        for leg in legs {
            XCTAssertEqual(leg.accountLegCount, 2, "two account legs — the shape that was misread")
            XCTAssertFalse(PurchaseFlow.isPartOfOnePurchase(leg))
        }
    }

    /// Both real shapes keep the mark: one purchase paid from two cards (one entry,
    /// two account legs), and a grid (several entries sharing a `groupId`).
    func test_splitPurchaseRowsKeepTheMark() throws {
        let q = try seed()
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "merchant": .string("Market"),
            "date": .string("2026-06-01"), "kind": .string("expense"),
            "currency": .string("USD"), "skipRules": .bool(true),
            "cells": .array([
                .object(["accountId": .string("a1"), "categoryId": .string("c1"), "amount": .double(-60)]),
                .object(["accountId": .string("a2"), "categoryId": .string("c1"), "amount": .double(-40)]),
            ]),
        ]))
        let tender = try Projection.run(dbQueue: q, ledgerId: "l1")
        XCTAssertEqual(tender.count, 2)
        for row in tender { XCTAssertTrue(PurchaseFlow.isPartOfOnePurchase(row), "split tender: \(row.account)") }

        // A grid row: one leg of its own, linked to its siblings by group.
        let grid = try XCTUnwrap(tender.first)
        var gridRow = grid
        gridRow.accountLegCount = 1
        gridRow.groupId = "g1"
        XCTAssertTrue(PurchaseFlow.isPartOfOnePurchase(gridRow), "grid")

        // And a plain one-card purchase has nothing to mark.
        var plain = grid
        plain.accountLegCount = 1
        plain.groupId = nil
        XCTAssertFalse(PurchaseFlow.isPartOfOnePurchase(plain))
    }
}
