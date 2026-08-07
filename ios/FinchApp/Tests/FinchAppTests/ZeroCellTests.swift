import XCTest
import GRDB
@testable import FinchApp
import FinchCore

/// Typing `0` into a page-2 cell means the same as crossing it out.
///
/// The grid's `−` button unticks a cell, and an absent cell produces no category
/// leg — that rule is already written down on `PurchaseFlow.cells`. Typing `0`
/// looked identical on screen and did something else entirely, because the
/// payload was built from every ticked row regardless of amount.
///
/// What that cost depended on the shape, which is why it went unnoticed:
///   - a grid or category split wrote a $0 CATEGORY LEG, silently, polluting the
///     category counts the leg feeds;
///   - an account split hit the engine's zero-share guard and failed the save
///     with "Every payment needs an amount" — an error with no action available
///     on the screen showing it.
final class ZeroCellTests: XCTestCase {

    private func seed() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','Cash','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a2','l1','Card','credit_card','USD',0,1,1,1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('c1','l1',NULL,'Food','expense',0,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('c2','l1',NULL,'Household','expense',1,datetime('now'),datetime('now'))")
        }
        return q
    }

    private func alloc(_ cells: [(String, String?, Double)], total: Double) -> SplitAllocation {
        var a = SplitAllocation(total: total)
        for (account, category, amount) in cells {
            let key = PurchaseFlow.cellKey(account: account, category: category)
            a.tick(key)
            a.setAmount(key, amount)
        }
        return a
    }

    private func save(_ q: DatabaseQueue, _ a: SplitAllocation) throws {
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "merchant": .string("Market"),
            "date": .string("2026-06-01"), "kind": .string("expense"),
            "currency": .string("USD"), "skipRules": .bool(true),
            "cells": .array(PurchaseFlow.cells(from: a, kind: .expense)),
        ]))
    }

    // MARK: the payload

    /// A zero cell is absent from the payload, exactly as a crossed-out one is.
    func test_aZeroCellIsAbsentFromThePayload() {
        let a = alloc([("a1", "c1", 60), ("a1", "c2", 0), ("a2", "c1", 40)], total: 100)
        XCTAssertEqual(PurchaseFlow.cells(from: a, kind: .expense).count, 2,
                       "the zeroed cell must not be sent")
    }

    /// And the allocation itself still shows the row, so the user can type into
    /// it again — dropping it from the PAYLOAD is not the same as unticking it.
    func test_aZeroCellStaysOnScreen() {
        let a = alloc([("a1", "c1", 100), ("a1", "c2", 0)], total: 100)
        XCTAssertEqual(a.rows.count, 2, "the row is still there to type into")
        XCTAssertTrue(a.isTicked("a1|c2"))
    }

    /// Zeroing everything but ONE cell is refused, with a reason — it is not
    /// silently saved as a "split" of one.
    ///
    /// This is the interaction between dropping zero cells and the page-2 gate:
    /// the payload would be a single cell, which the engine accepts happily, so
    /// without the gate a 2x2 selection could save as a plain purchase while
    /// still claiming to be split. `problem` catches it as `.needsTwo`, and both
    /// ways out are available from the screen — fund another cell, or go back and
    /// narrow the selection.
    func test_zeroingAllButOneCellIsRefusedWithAReason() {
        let a = alloc([("a1", "c1", 100), ("a1", "c2", 0),
                       ("a2", "c1", 0), ("a2", "c2", 0)], total: 100)
        XCTAssertEqual(PurchaseFlow.cells(from: a, kind: .expense).count, 1,
                       "the payload collapses to the one funded cell")
        XCTAssertEqual(a.problem, .needsTwo,
                       "and the page refuses it rather than saving a split of one")
    }

    // MARK: what reaches the ledger

    /// A grid with one zeroed cell must write no category leg for it. A $0 leg
    /// counts as a use of that category everywhere the leg is read.
    func test_aZeroedGridCellWritesNoCategoryLeg() throws {
        let q = try seed()
        try save(q, alloc([("a1", "c1", 40), ("a1", "c2", 0),
                           ("a2", "c1", 30), ("a2", "c2", 30)], total: 100))

        let zeroLegs = try q.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM postings
                 WHERE category_id IS NOT NULL AND ROUND(amount_base, 2) = 0
                """) ?? -1
        }
        XCTAssertEqual(zeroLegs, 0, "a zeroed cell left a $0 category leg behind")

        let c2 = try q.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE category_id = 'c2'") ?? -1
        }
        XCTAssertEqual(c2, 1, "Household was bought on one card, not two")
    }

    /// Zeroing every cell of one card drops that card from the purchase, rather
    /// than failing the save with the engine's zero-share guard.
    func test_zeroingACardsOnlyCellDropsTheCard() throws {
        let q = try seed()
        try save(q, alloc([("a1", "c1", 100), ("a2", "c1", 0)], total: 100))

        let accounts = try q.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT account_id FROM postings
                 WHERE account_id IS NOT NULL AND entry_id IN (SELECT id FROM entries WHERE kind = 'expense')
                 ORDER BY account_id
                """)
        }
        XCTAssertEqual(accounts, ["a1"], "the zeroed card should not be part of the purchase")
    }
}
