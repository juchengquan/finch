import XCTest
import GRDB
@testable import FinchCore

/// A purchase paid from several accounts AND split across several categories is
/// now refused at write time. That strands anything already in the shape:
/// `rebuildEntry` re-validates the EXISTING legs, so such an entry would become
/// uneditable — not even a note change — reporting an error about leg shapes that
/// never hints deleting is the only way out.
///
/// The migration collapses those entries into their dominant category, which is
/// already the single category the projection displays for them.
final class CollapseBothAxesMigrationTests: XCTestCase {

    /// Writes the shape the engine now refuses, by inserting postings directly
    /// while the entry is unsealed. Returns the entry id.
    private func insertBothAxesEntry(_ q: DatabaseQueue) throws -> String {
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
                INSERT INTO entries (id,ledger_id,date,time,description,kind,status,sealed,created_at,updated_at)
                VALUES ('e-bad','l1','2026-06-01','12:00','Market','expense','confirmed',0,datetime('now'),datetime('now'))
                """)
            // Two payment legs and two category legs — the forbidden combination.
            for (pid, acct, cat, amt, sort) in [
                ("p-a2", "a2", String?.none, -60.0, 0), ("p-a1", "a1", nil, -40.0, 1),
                ("p-c1", nil, "c1", 70.0, 2), ("p-c2", nil, "c2", 30.0, 3),
            ] as [(String, String?, String?, Double, Int)] {
                try db.execute(sql: """
                    INSERT INTO postings (id,entry_id,account_id,category_id,amount,currency,amount_base,exchange_rate,sort_order)
                    VALUES (?,?,?,?,?, 'USD', ?, 1, ?)
                    """, arguments: [pid, "e-bad", acct, cat, amt, amt, sort])
            }
            try db.execute(sql: "UPDATE entries SET sealed = 1 WHERE id = 'e-bad'")
        }
        return "e-bad"
    }

    func test_migration_collapsesBothAxesEntryIntoItsDominantCategory() throws {
        let q = try TestSeed.base()
        let eid = try insertBothAxesEntry(q)

        try q.write { db in try Migrations.collapseBothAxesEntries(db) }

        let legs = try q.read { db in
            try Row.fetchAll(db, sql: """
                SELECT category_id, amount, amount_base FROM postings
                 WHERE entry_id = ? AND category_id IS NOT NULL
                """, arguments: [eid])
        }
        XCTAssertEqual(legs.count, 1, "the category legs are merged into one")
        XCTAssertEqual(legs[0]["category_id"] as String?, "c1", "into the dominant one — 70 beats 30")
        XCTAssertEqual(legs[0]["amount_base"] as Double, 100, accuracy: 0.001, "carrying the whole purchase")
        XCTAssertEqual(legs[0]["amount"] as Double, 100, accuracy: 0.001, "a category leg is in base, so amount mirrors it")

        let acctLegs = try q.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [eid]) ?? 0
        }
        XCTAssertEqual(acctLegs, 2, "both payments survive — this is not a delete")

        XCTAssertTrue(try Audit.run(on: q).isEmpty, "the collapsed entry must still be a clean ledger")
    }

    /// The assertion that proves the trap is closed. Collapsing is not the point —
    /// being able to edit the row afterwards is.
    ///
    /// The block is narrower than it first looks, and worth stating precisely:
    /// `rebuildEntry` rebuilds legs when `legsProvided || dateChanged`
    /// (`Entries.swift:682`) and validates the result, so **changing the date** —
    /// an entirely ordinary edit — carries the forbidden shape forward and throws.
    /// A notes-only patch touches no legs and validates nothing, so it still works.
    /// Either way the doubled category totals persist until the shape is gone.
    func test_migratedEntry_canHaveItsDateChangedAgain() throws {
        let q = try TestSeed.base()
        let eid = try insertBothAxesEntry(q)

        XCTAssertThrowsError(try q.write { db in
            var p = Entries.EntryPatch(); p.date = .set("2026-06-02")
            try Entries.rebuildEntry(db, eid, p)
        }, "a date change rebuilds the legs, which re-validates the forbidden shape")

        // A header-only edit was never blocked — assert that too, so the boundary
        // is pinned rather than assumed in either direction.
        try q.write { db in
            var p = Entries.EntryPatch(); p.notes = .set("header edits were always fine")
            try Entries.rebuildEntry(db, eid, p)
        }

        try q.write { db in try Migrations.collapseBothAxesEntries(db) }

        try q.write { db in
            var p = Entries.EntryPatch(); p.date = .set("2026-06-02")
            try Entries.rebuildEntry(db, eid, p)
        }
        let date = try q.read { db in
            try String.fetchOne(db, sql: "SELECT date FROM entries WHERE id = ?", arguments: [eid])
        }
        XCTAssertEqual(date, "2026-06-02", "the date moves once the shape is gone")
    }
}
