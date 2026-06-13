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
}
