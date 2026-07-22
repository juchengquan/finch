import XCTest
import GRDB
@testable import FinchCore

final class MigrationsTests: XCTestCase {
    func test_migrateOnEmptyDatabaseStampsMetadata() throws {
        // One connection type everywhere: GRDB DatabaseQueue (R10).
        let dbQueue = try DatabaseQueue()  // in-memory
        try Migrations.runAll(on: dbQueue)
        // The metadata row is stamped in the `db_metadata` TABLE columns (the web
        // reads the version from this column, NOT PRAGMA user_version).
        try dbQueue.read { db in
            let row = try Row.fetchOne(
                db, sql: "SELECT app_name, schema_version FROM db_metadata WHERE id = 1"
            )
            XCTAssertEqual(row?["app_name"], "finch")
            XCTAssertEqual(row?["schema_version"], Schema.version)
        }
    }

    func test_schemaCreatesTheCanonicalDoubleEntryTables() throws {
        let dbQueue = try DatabaseQueue()
        try Migrations.runAll(on: dbQueue)
        try dbQueue.read { db in
            // The DE tables exist (entries/postings, not a legacy `transactions`).
            for table in ["entries", "postings", "entry_tags", "entry_attachments", "ledgers", "accounts"] {
                XCTAssertTrue(try db.tableExists(table), "expected table \(table)")
            }
            XCTAssertFalse(try db.tableExists("transactions"), "legacy `transactions` must NOT exist")
            // FTS5 virtual table is present.
            XCTAssertTrue(try db.tableExists("entries_fts"))
        }
    }

    /// #533 dropped counterparties.ledger_id from the baseline without a
    /// migration — a database created before it keeps the per-ledger table and
    /// every NEW-merchant insert fails its NOT NULL constraint. The 07-23
    /// rebuild heals it: ledger_id gone, rows kept, inserts work.
    func test_counterpartiesRebuild_dropsLedgerId_keepsRows() throws {
        let dbQueue = try DatabaseQueue()
        try Migrations.runAll(on: dbQueue)
        // Regress the table to its pre-#533 per-ledger shape (as an old install
        // would have it), then re-run the migrator — only the guarded rebuild
        // has observable work left to do.
        try dbQueue.write { db in
            try db.execute(sql: "DROP TABLE counterparties")
            try db.execute(sql: """
                CREATE TABLE counterparties (
                  id            TEXT PRIMARY KEY,
                  ledger_id     TEXT NOT NULL,
                  name          TEXT NOT NULL COLLATE NOCASE,
                  is_verified   INTEGER NOT NULL DEFAULT 0,
                  created_at    TEXT NOT NULL,
                  updated_at    TEXT NOT NULL
                )
                """)
            try db.execute(sql: """
                INSERT INTO counterparties (id,ledger_id,name,is_verified,created_at,updated_at)
                VALUES ('cp1','l1','Blue Bottle',1,'2026-01-01','2026-01-01')
                """)
            // Forget the migration record so the migrator replays it.
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = '2026-07-23-counterparties-global'")
        }
        try Migrations.runAll(on: dbQueue)
        try dbQueue.read { db in
            let cols = try Row.fetchAll(db, sql: "PRAGMA table_info(counterparties)").map { $0["name"] as String }
            XCTAssertFalse(cols.contains("ledger_id"))
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM counterparties"), 1)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT name FROM counterparties WHERE id = 'cp1'"), "Blue Bottle")
        }
        // The failing insert from the bug report now succeeds.
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO counterparties (id,name,is_verified,created_at,updated_at)
                VALUES ('cp2','Gym Membership',0,datetime('now'),datetime('now'))
                """)
        }
    }

    func test_occurrenceDateColumn_isAddedAndIdempotent() throws {
        let dbQueue = try DatabaseQueue()  // in-memory
        try Migrations.runAll(on: dbQueue)
        try Migrations.runAll(on: dbQueue)  // replay must not throw
        try dbQueue.read { db in
            let cols = try Row.fetchAll(db, sql: "PRAGMA table_info(entries)").map { $0["name"] as String }
            XCTAssertTrue(cols.contains("occurrence_date"))
        }
    }
}
