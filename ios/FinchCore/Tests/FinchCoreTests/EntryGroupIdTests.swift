import XCTest
import GRDB
@testable import FinchCore

/// `entries.group_id` links the transactions of one grid purchase — a purchase
/// split by card AND by category, which is stored as one entry per card because
/// a single entry may be split on at most one axis.
///
/// Without the link the grid is a one-way door: buildable, never revisable, and
/// the information needed to reconstruct a group is never written, so adding the
/// column later cannot recover the groups already made.
final class EntryGroupIdTests: XCTestCase {

    /// The column has to survive all the way into `Tx`, because that is what
    /// every later task reads. A migration test alone would pass while the
    /// projection still dropped it on the floor.
    func test_groupId_reachesTx() throws {
        let q = try TestSeed.base()
        let eid = try q.write { db in
            try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: "l1", date: "2026-06-01", time: "12:00",
                description: "Market", kind: .expense,
                legs: [
                    .account(Entries.AccountLeg(accountId: "a1", amount: -100)),
                    .category(Entries.CategoryLeg(categoryId: "c1", amountBase: 100)),
                ],
                groupId: "g1"))
        }
        let stored = try q.read { db in
            try String.fetchOne(db, sql: "SELECT group_id FROM entries WHERE id = ?", arguments: [eid])
        }
        XCTAssertEqual(stored, "g1", "postEntry must write it — its INSERT names every column explicitly")

        let tx = try XCTUnwrap(try Projection.run(dbQueue: q, ledgerId: "l1").first)
        XCTAssertEqual(tx.groupId, "g1", "…and the projection must carry it into Tx")
    }

    /// An ordinary transaction is not a group of one.
    func test_groupId_isNilForAnUngroupedEntry() throws {
        let q = try TestSeed.base()
        _ = try q.write { db in
            try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: "l1", date: "2026-06-01", time: "12:00",
                description: "Cafe", kind: .expense,
                legs: [
                    .account(Entries.AccountLeg(accountId: "a1", amount: -25)),
                    .category(Entries.CategoryLeg(categoryId: "c1", amountBase: 25)),
                ]))
        }
        let tx = try XCTUnwrap(try Projection.run(dbQueue: q, ledgerId: "l1").first)
        XCTAssertNil(tx.groupId)
    }

    /// The migration must add the column to a database that predates it, and be
    /// safe to replay — imported web packs may already carry it while lacking
    /// GRDB's bookkeeping, which is why every sibling migration tolerates a
    /// duplicate column.
    func test_migration_addsGroupIdAndIsReplayable() throws {
        let q = try DatabaseQueue()
        try q.write { db in
            try db.execute(sql: """
                CREATE TABLE entries (
                  id TEXT PRIMARY KEY, ledger_id TEXT NOT NULL, date TEXT NOT NULL,
                  kind TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'confirmed',
                  sealed INTEGER NOT NULL DEFAULT 0,
                  created_at TEXT NOT NULL, updated_at TEXT NOT NULL)
                """)
        }
        try q.write { db in try Migrations.addEntryGroupId(db) }
        try q.write { db in try Migrations.addEntryGroupId(db) }   // replay must be a no-op

        let hasColumn = try q.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(entries)")
                .contains { ($0["name"] as? String) == "group_id" }
        }
        XCTAssertTrue(hasColumn, "the migration adds group_id, and adding it twice is not an error")
    }
}

/// What happens when someone edits ONE card of a grid purchase.
///
/// Decision 21 wants the whole grid to reopen, so a partial edit is impossible.
/// That is a UI routing change and is not built yet — meanwhile every screen
/// happily opens a single grid row in the Edit sheet, so the engine must not
/// quietly damage the purchase when it receives one.
final class PartialGridEditTests: XCTestCase {

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

    /// A 2x2 grid: two cards, two categories, one purchase.
    private func writeGrid(_ q: DatabaseQueue) throws {
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "merchant": .string("Market"),
            "date": .string("2026-06-01"), "kind": .string("expense"),
            "currency": .string("USD"), "skipRules": .bool(true),
            "cells": .array([
                .object(["accountId": .string("a1"), "categoryId": .string("c1"), "amount": .double(-40)]),
                .object(["accountId": .string("a1"), "categoryId": .string("c2"), "amount": .double(-20)]),
                .object(["accountId": .string("a2"), "categoryId": .string("c1"), "amount": .double(-30)]),
                .object(["accountId": .string("a2"), "categoryId": .string("c2"), "amount": .double(-10)]),
            ]),
        ]))
    }

    private func groups(_ q: DatabaseQueue) throws -> [String?] {
        try q.read { db in
            try Row.fetchAll(db, sql: "SELECT group_id FROM entries WHERE kind = 'expense' ORDER BY id")
                .map { $0["group_id"] as String? }
        }
    }

    /// Editing one card must not drop that card out of the purchase. If it does,
    /// one purchase silently becomes two — and `purchaseKey` counts it twice,
    /// which is the exact bug the group column exists to prevent.
    func test_editingOneCardOfAGrid_keepsItInTheGroup() throws {
        let q = try seed()
        try writeGrid(q)
        let before = try groups(q)
        XCTAssertEqual(before.count, 2)
        XCTAssertNotNil(before[0])
        XCTAssertEqual(before[0], before[1], "one purchase, two cards")

        // The Edit sheet names ONE posting and sends only that card's cells.
        let posting = try q.read { db in
            try String.fetchOne(db, sql: """
                SELECT p.id FROM postings p JOIN entries e ON e.id = p.entry_id
                 WHERE p.account_id = 'a1' AND e.kind = 'expense'
                """)
        }!
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: Args([
            "id": .string(posting),
            "ledgerId": .string("l1"), "merchant": .string("Market"),
            "date": .string("2026-06-01"), "kind": .string("expense"),
            "currency": .string("USD"), "skipRules": .bool(true),
            "cells": .array([
                .object(["accountId": .string("a1"), "categoryId": .string("c1"), "amount": .double(-60)]),
            ]),
        ]))

        let after = try groups(q)
        XCTAssertEqual(after.count, 2, "still two transactions")
        XCTAssertEqual(after[0], before[0], "the edited card is still part of the purchase")
        XCTAssertEqual(after[1], before[1], "and so is the other one")
    }

    /// The collapse Decision 20 DOES mean: a rewrite naming the whole group that
    /// comes back with one card. The link goes, because a lone transaction must
    /// not claim membership of a group that no longer exists.
    func test_rewritingAWholeGroupDownToOneCard_clearsTheLink() throws {
        let q = try seed()
        try writeGrid(q)
        let group = try groups(q)[0]!

        try Apply.apply(dbQueue: q, action: "saveTransaction", args: Args([
            "id": .string(group),
            "ledgerId": .string("l1"), "merchant": .string("Market"),
            "date": .string("2026-06-01"), "kind": .string("expense"),
            "currency": .string("USD"), "skipRules": .bool(true),
            "cells": .array([
                .object(["accountId": .string("a1"), "categoryId": .string("c1"), "amount": .double(-100)]),
            ]),
        ]))

        let after = try groups(q)
        XCTAssertEqual(after.count, 1, "the other card's transaction is gone")
        XCTAssertNil(after[0], "a group of one is not a group")
    }
}
