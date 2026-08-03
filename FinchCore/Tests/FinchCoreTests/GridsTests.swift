import XCTest
import GRDB
@testable import FinchCore

/// A purchase split by card AND by category — the grid.
///
/// It cannot be one entry: a single entry is split on at most one axis, because
/// the projection copies an entry's whole `splits` array onto every account-leg
/// row and would double-count it. So the engine derives one entry per card,
/// linked by `group_id`.
///
/// The shape is derived from the CATEGORY count, not the card count. That is the
/// distinction everything here turns on.
final class GridsTests: XCTestCase {

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
        }
        return q
    }

    private func args(id: String? = nil, cells: [(String, String?, Double)],
                      merchant: String = "Market", date: String = "2026-06-01") -> Args {
        var o: [String: JSONValue] = [
            "ledgerId": .string("l1"), "date": .string(date), "time": .string("12:00"),
            "merchant": .string(merchant), "kind": .string("expense"), "currency": .string("USD"),
            "cells": .array(cells.map { .object([
                "accountId": .string($0.0),
                "categoryId": $0.1.map(JSONValue.string) ?? .null,
                "amount": .double($0.2),
            ])}),
        ]
        if let id { o["id"] = .string(id) }
        return Args(o)
    }

    private func entries(_ q: DatabaseQueue) throws -> [Row] {
        try q.read { db in
            try Row.fetchAll(db, sql: "SELECT id, group_id FROM entries WHERE kind != 'opening' ORDER BY id")
        }
    }

    // MARK: shape derivation — the heart of the task

    /// Two cards, ONE category. This must stay a single transaction with two
    /// payment legs — the shape that already ships. The obvious implementation of
    /// a grid (one entry per card) would silently turn every split-tender purchase
    /// into a group, so this test exists to forbid it.
    func test_twoCardsOneCategory_isOneEntryWithNoGroup() throws {
        let q = try seed()
        let id = try Apply.applyReturningId(dbQueue: q, action: "saveTransaction", args: args(cells: [
            ("a1", "c1", -60), ("a2", "c1", -40),
        ]))!
        let rows = try entries(q)
        XCTAssertEqual(rows.count, 1, "one purchase, one transaction")
        XCTAssertNil(rows[0]["group_id"] as String?, "a lone transaction is not a group of one")
        let legs = try q.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [id]) ?? 0
        }
        XCTAssertEqual(legs, 2, "…carrying both payments")
    }

    /// Two cards across TWO categories. Now it must decompose: one entry per card,
    /// each an ordinary category split, linked so they can be revised together.
    func test_twoCardsTwoCategories_isTwoEntriesSharingAGroup() throws {
        let q = try seed()
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: args(cells: [
            ("a1", "c1", -40), ("a1", "c2", -20),
            ("a2", "c1", -30), ("a2", "c2", -10),
        ]))
        let rows = try entries(q)
        XCTAssertEqual(rows.count, 2, "one entry per card")
        let groups = Set(rows.compactMap { $0["group_id"] as String? })
        XCTAssertEqual(groups.count, 1, "…sharing one group id")
        XCTAssertEqual(rows.count, groups.isEmpty ? 0 : 2, "and both carry it")
        XCTAssertTrue(try Audit.run(on: q).isEmpty)
    }

    // MARK: atomicity — the property the whole design rests on

    func test_aRejectedCellLeavesNothingBehind() throws {
        let q = try seed()
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "saveTransaction", args: args(cells: [
            ("a1", "c1", -40), ("a1", "c2", -20),
            ("nope", "c1", -30), ("nope", "c2", -10),
        ])))
        XCTAssertEqual(try entries(q).count, 0, "a grid is all or nothing")
    }

    // MARK: rewrite

    /// A grid's rows share date, time and description, differing only by account —
    /// and `dedup_hash` is stamped from exactly those. Re-posting before deleting
    /// makes the rewrite collide with itself and surface as "This looks like a
    /// duplicate", which is nonsense for an edit.
    func test_aGridCanBeSavedAgainWithNewAmounts() throws {
        let q = try seed()
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: args(cells: [
            ("a1", "c1", -40), ("a1", "c2", -20), ("a2", "c1", -30), ("a2", "c2", -10),
        ]))
        let first = try entries(q)
        let gid = try XCTUnwrap(first[0]["group_id"] as String?)

        try Apply.apply(dbQueue: q, action: "saveTransaction", args: args(id: gid, cells: [
            ("a1", "c1", -50), ("a1", "c2", -25), ("a2", "c1", -35), ("a2", "c2", -15),
        ]))
        let second = try entries(q)
        XCTAssertEqual(second.count, 2, "still two rows, not four")
        let total = try q.read { db in
            try Double.fetchOne(db, sql: "SELECT ROUND(SUM(amount_base), 2) FROM postings WHERE account_id IS NOT NULL AND entry_id IN (SELECT id FROM entries WHERE group_id = ?)", arguments: [gid]) ?? 0
        }
        XCTAssertEqual(total, -125, accuracy: 0.001, "carrying the new amounts")
    }

    // MARK: conversion between shapes (Decision 21)

    /// Adding a second category turns one transaction into two. The original must
    /// keep its id — otherwise an ordinary edit silently destroys its receipt and
    /// its reconcile marks, which the obvious "delete all, rewrite all"
    /// implementation does while passing every other test here.
    func test_growingIntoAGrid_keepsTheOriginalEntryId() throws {
        let q = try seed()
        let original = try Apply.applyReturningId(dbQueue: q, action: "saveTransaction", args: args(cells: [
            ("a1", "c1", -100),
        ]))!

        try Apply.apply(dbQueue: q, action: "saveTransaction", args: args(id: original, cells: [
            ("a1", "c1", -60), ("a1", "c2", -20), ("a2", "c1", -20),
        ]))
        let ids = try entries(q).map { $0["id"] as String }
        XCTAssertEqual(ids.count, 2, "it grew into a group")
        XCTAssertTrue(ids.contains(original), "…and card a1's entry is the SAME one, not a fresh row")
    }

    /// The reverse: collapsing back to one card keeps that card's entry.
    func test_collapsingAGrid_keepsTheSurvivingEntryId() throws {
        let q = try seed()
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: args(cells: [
            ("a1", "c1", -40), ("a1", "c2", -20), ("a2", "c1", -30), ("a2", "c2", -10),
        ]))
        let before = try entries(q)
        let gid = try XCTUnwrap(before[0]["group_id"] as String?)
        let a1Entry = try q.read { db in
            try String.fetchOne(db, sql: "SELECT entry_id FROM postings WHERE account_id = 'a1' LIMIT 1")
        }

        try Apply.apply(dbQueue: q, action: "saveTransaction", args: args(id: gid, cells: [
            ("a1", "c1", -40), ("a1", "c2", -20),
        ]))
        let after = try entries(q)
        XCTAssertEqual(after.count, 1, "the removed card's entry is gone")
        XCTAssertEqual(after[0]["id"] as String, a1Entry, "the survivor is the original, not a rebuild")
    }

    /// Decision 20: a group reduced to one member stops claiming to be a group.
    func test_aGroupReducedToOneClearsItsGroupId() throws {
        let q = try seed()
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: args(cells: [
            ("a1", "c1", -40), ("a1", "c2", -20), ("a2", "c1", -30), ("a2", "c2", -10),
        ]))
        let gid = try XCTUnwrap(try entries(q)[0]["group_id"] as String?)

        try Apply.apply(dbQueue: q, action: "saveTransaction", args: args(id: gid, cells: [
            ("a1", "c1", -40), ("a1", "c2", -20),
        ]))
        let after = try entries(q)
        XCTAssertEqual(after.count, 1)
        XCTAssertNil(after[0]["group_id"] as String?, "one transaction is not a group")
    }

    /// Every money path invalidates the rollover cache. Skipping a row leaves wrong
    /// budget numbers with no error and nothing in the audit — so the budget here
    /// is scoped to the SECOND card, which only a per-row invalidation reaches.
    func test_everyGridRowInvalidatesItsBudgets() throws {
        let q = try seed()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO budgets (id,ledger_id,kind,amount,frequency,start_date,account_ids,last_rolled_period,created_at,updated_at)
                VALUES ('b1','l1','expense',500,'monthly','2026-01-01','["a2"]','2026-12',datetime('now'),datetime('now'))
                """)
        }
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: args(cells: [
            ("a1", "c1", -40), ("a1", "c2", -20), ("a2", "c1", -30), ("a2", "c2", -10),
        ]))
        let lastRolled = try q.read { db in
            try String.fetchOne(db, sql: "SELECT last_rolled_period FROM budgets WHERE id = 'b1'")
        }
        XCTAssertNil(lastRolled, "the second card's row must invalidate too, not just the first")
    }
}
