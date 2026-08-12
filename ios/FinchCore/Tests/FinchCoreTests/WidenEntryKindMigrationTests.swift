import XCTest
import GRDB
@testable import FinchCore

/// The `entries` rebuild that widens the `kind` CHECK (2026-08-12 design, D3).
///
/// This is the migration that carried the real risk, and these are the tests
/// that price it: `entries` is the spine — postings and attachments CASCADE from
/// it, 7 indexes and 4 triggers hang off it, and an FTS shadow mirrors it. A
/// rebuild that drops it with foreign keys live would take every posting in the
/// database with it, and one that forgets a trigger would leave search quietly
/// returning nothing.
/// These tests drive `Migrations.runAll`, not `widenEntryKind` directly, and that
/// is deliberate: GRDB runs migrations with foreign keys DISABLED (outside the
/// transaction), which is exactly what stops `DROP TABLE entries_old` cascading
/// into postings. Calling the function straight bypasses that protection and
/// fails — which is how the cascade hazard was first observed here.
final class WidenEntryKindMigrationTests: XCTestCase {

    /// A database in the PRE-widening shape: the canonical schema with the one
    /// CHECK narrowed back. Derived from `Schema.ddl` rather than transcribed, so
    /// it cannot drift as the schema moves.
    private func oldShapeDB() throws -> DatabaseQueue {
        let narrowed = Schema.ddl.replacingOccurrences(
            of: "CHECK(kind IN ('opening','income','expense','transfer','adjustment','refund','interledger'))",
            with: "CHECK(kind IN ('opening','income','expense','transfer','adjustment','refund'))")
        XCTAssertNotEqual(narrowed, Schema.ddl, "the narrowing must actually match the canonical CHECK")
        let q = try DatabaseQueue()
        try q.write { db in
            try db.execute(sql: narrowed)
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','Personal','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','Checking','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('c1','l1',NULL,'Food','expense',0,datetime('now'),datetime('now'))")
            // Two ordinary entries with their money lines — the rows a bad rebuild
            // would destroy.
            for n in 1...2 {
                try db.execute(sql: """
                    INSERT INTO entries (id,ledger_id,date,description,kind,status,sealed,created_at,updated_at)
                    VALUES ('e\(n)','l1','2026-08-0\(n)','Groceries \(n)','expense','confirmed',0,datetime('now'),datetime('now'))
                    """)
                try db.execute(sql: """
                    INSERT INTO postings (id,entry_id,account_id,category_id,amount,currency,amount_base,exchange_rate,sort_order)
                    VALUES ('p\(n)a','e\(n)','a1',NULL,-10,'USD',-10,1,0),
                           ('p\(n)b','e\(n)',NULL,'c1',10,'USD',10,1,1)
                    """)
                try db.execute(sql: "UPDATE entries SET sealed = 1 WHERE id = 'e\(n)'")
            }
        }
        return q
    }

    func test_theOldShapeRejectsInterledger() throws {
        let q = try oldShapeDB()
        try q.write { db in
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO entries (id,ledger_id,date,description,kind,status,sealed,created_at,updated_at)
                VALUES ('x','l1','2026-08-12','x','interledger','confirmed',0,datetime('now'),datetime('now'))
                """), "the pre-migration shape must reject the new kind — otherwise this test proves nothing")
        }
    }

    func test_rebuildKeepsEveryEntryAndEveryPosting() throws {
        let q = try oldShapeDB()
        try Migrations.runAll(on: q)   // the production path — see the note on runAll below
        try q.read { db in
            // Guard against a vacuous pass: if the migration silently skipped,
            // every assertion below would hold on the untouched table.
            let ddl = try String.fetchOne(db, sql:
                "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'entries'") ?? ""
            XCTAssertTrue(ddl.contains("'refund','interledger'"),
                          "the table was not actually rebuilt — the rest of this test would pass for free")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries"), 2)
            // THE assertion this file exists for: postings CASCADE from entries, so
            // a rebuild with foreign keys live would silently empty this table.
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings"), 4,
                           "the money lines must survive the rebuild — this is the cascade hazard")
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT SUM(amount) FROM postings"), 0)
            let descs = try String.fetchAll(db, sql: "SELECT description FROM entries ORDER BY id")
            XCTAssertEqual(descs, ["Groceries 1", "Groceries 2"], "row content must come across intact")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE sealed = 1"), 2,
                           "sealed state is data, not decoration — an unsealed copy would be editable")

            // The OTHER half of the rename hazard, and the quiet one: without
            // `PRAGMA legacy_alter_table = ON` the rename rewrites every foreign
            // key to follow the renamed table, so postings would be left pointing
            // at `entries_old` — a table that no longer exists. Nothing fails at
            // migration time; enforcement just silently stops working.
            let postingsDDL = try String.fetchOne(db, sql:
                "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'postings'") ?? ""
            XCTAssertTrue(postingsDDL.contains("REFERENCES entries(id)"),
                          "postings must still reference `entries`, not the scaffolding table")
            XCTAssertFalse(postingsDDL.contains("entries_old"),
                           "a foreign key pointing at the dropped table is silent corruption")
            let violations = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pragma_foreign_key_check")
            XCTAssertEqual(violations, 0, "the database must be referentially clean after the rebuild")
        }
    }

    func test_rebuildAcceptsTheNewKindAfterwards() throws {
        let q = try oldShapeDB()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO entries (id,ledger_id,date,description,kind,status,sealed,created_at,updated_at)
                VALUES ('e3','l1','2026-08-12','Travel · Card','interledger','confirmed',0,datetime('now'),datetime('now'))
                """)
        }
        XCTAssertEqual(try q.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM entries WHERE kind = 'interledger'") }, 1)
    }

    /// The seal trigger and the three FTS triggers travel with a rename, so a
    /// rebuild that doesn't drop them first gets a table with no balance check and
    /// a search index that stops updating — both silent failures.
    func test_triggersAndSearchSurvive() throws {
        let q = try oldShapeDB()
        try Migrations.runAll(on: q)   // the production path — see the note on runAll below
        try q.write { db in
            let ddl = try String.fetchOne(db, sql:
                "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'entries'") ?? ""
            XCTAssertTrue(ddl.contains("'refund','interledger'"), "the table was not actually rebuilt")
            let triggers = try String.fetchAll(db, sql:
                "SELECT name FROM sqlite_master WHERE type = 'trigger' AND tbl_name = 'entries' ORDER BY name")
            XCTAssertEqual(triggers, ["tr_entry_fts_delete", "tr_entry_fts_insert",
                                      "tr_entry_fts_update", "tr_entry_seal"])
            let indexes = try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND tbl_name = 'entries' AND name LIKE 'idx_entry%'")
            XCTAssertEqual(indexes, 7, "all seven lookup indexes must be back")

            // The shadow was rebuilt exactly once — not doubled, not emptied.
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries_fts"), 2)
            let hits = try String.fetchAll(db, sql:
                "SELECT id FROM entries_fts WHERE entries_fts MATCH 'groceries' ORDER BY id")
            XCTAssertEqual(hits, ["e1", "e2"], "search must still find the migrated rows")

            // And the seal trigger still refuses an unbalanced entry.
            try db.execute(sql: """
                INSERT INTO entries (id,ledger_id,date,description,kind,status,sealed,created_at,updated_at)
                VALUES ('bad','l1','2026-08-12','x','expense','confirmed',0,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO postings (id,entry_id,account_id,category_id,amount,currency,amount_base,exchange_rate,sort_order)
                VALUES ('pbad','bad','a1',NULL,-10,'USD',-10,1,0)
                """)
            XCTAssertThrowsError(try db.execute(sql: "UPDATE entries SET sealed = 1 WHERE id = 'bad'"),
                                 "the seal trigger must still guard the rebuilt table")
        }
    }

    /// Replaying must be a no-op — imported packs arrive without GRDB's
    /// bookkeeping table, so every migration runs again over an already-current
    /// database. The guard is what makes that safe, so it is asserted directly:
    /// a second call must return before touching any DDL.
    func test_replayIsANoOp() throws {
        let q = try oldShapeDB()
        try Migrations.runAll(on: q)
        try Migrations.runAll(on: q)
        // And the guard itself, called straight: on an already-wide table it must
        // bail out before the rename, which is why this direct call is safe even
        // with foreign keys live (the migrator's FK handling is not in play here).
        try q.write { db in try Migrations.widenEntryKind(db) }
        XCTAssertEqual(try q.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM postings") }, 4)
        XCTAssertEqual(try q.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM entries") }, 2)
        XCTAssertEqual(try q.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM entries_fts") }, 2)
    }
}
