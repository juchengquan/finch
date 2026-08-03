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
