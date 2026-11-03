import XCTest
import GRDB
@testable import FinchCore

/// The one-time clear of the review backlog (`Migrations.clearReviewBacklog`).
///
/// `entries.reviewed_at` has existed since the web's triage queue, but iOS had no
/// queue until #809, so every entry anyone typed into an iOS build before then still
/// reads NULL — "needs review". The update opened "Needs review" on all of them at
/// once, 2,000+ for a long-time user. The update now marks those reviewed exactly
/// once; what is entered afterwards starts in the queue as designed.
final class ReviewBacklogMigrationTests: XCTestCase {
    private static let identifier = "2026-11-02-review-backlog"

    /// A database an iOS build made before the update: the migrator's bookkeeping
    /// is there, minus this migration, and every entry is unreviewed.
    private func preUpdateInstall(_ q: DatabaseQueue) throws {
        try Migrations.runAll(on: q)
        try q.write { db in
            try Self.seed(db)
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = ?", arguments: [Self.identifier])
        }
    }

    private static func seed(_ db: Database) throws {
        try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
        try insert(db, "old1", status: "confirmed")
        try insert(db, "old2", status: "confirmed")
        try insert(db, "kept", status: "confirmed", reviewedAt: "2026-05-01 09:00:00")
        try insert(db, "due", status: "pending")
    }

    private static func insert(_ db: Database, _ id: String, status: String, reviewedAt: String? = nil) throws {
        try db.execute(sql: """
            INSERT INTO entries (id,ledger_id,date,description,kind,status,reviewed_at,sealed,created_at,updated_at)
            VALUES (?, 'l1', '2026-06-01', 'Coffee', 'expense', ?, ?, 0, '2026-06-01 08:00:00', '2026-06-01 08:00:00')
            """, arguments: [id, status, reviewedAt])
    }

    private func reviewedAt(_ q: DatabaseQueue) throws -> [String: String?] {
        try q.read { db in
            Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT id, reviewed_at FROM entries")
                .map { ($0["id"] as String, $0["reviewed_at"] as String?) })
        }
    }

    // MARK: An install from before the update

    func test_the_update_marks_every_settled_entry_reviewed() throws {
        let q = try DatabaseQueue()
        try preUpdateInstall(q)
        try Migrations.runAll(on: q)

        let r = try reviewedAt(q)
        XCTAssertNotNil(r["old1"] ?? nil, "an entry from before the update leaves the queue")
        XCTAssertNotNil(r["old2"] ?? nil)
        XCTAssertEqual(r["kept"] ?? nil, "2026-05-01 09:00:00", "one already reviewed keeps its own stamp")
    }

    /// A pending row is not in the queue — it waits in "To confirm". Confirming it is
    /// a new event, so it joins the queue then, like anything confirmed from now on.
    func test_a_pending_row_is_left_for_when_it_settles() throws {
        let q = try DatabaseQueue()
        try preUpdateInstall(q)
        try Migrations.runAll(on: q)
        XCTAssertNil(try reviewedAt(q)["due"] ?? nil)
    }

    /// Not an edit, so nothing reads it as one (sync, "recently changed" ordering).
    func test_the_stamp_does_not_touch_updated_at() throws {
        let q = try DatabaseQueue()
        try preUpdateInstall(q)
        try Migrations.runAll(on: q)
        let updated = try q.read { try String.fetchAll($0, sql: "SELECT DISTINCT updated_at FROM entries") }
        XCTAssertEqual(updated, ["2026-06-01 08:00:00"])
    }

    // MARK: Exactly once

    /// What is entered after the update starts in the queue, and the next launch's
    /// migrator run does not sweep it away.
    func test_entries_added_after_the_update_stay_in_the_queue() throws {
        let q = try DatabaseQueue()
        try preUpdateInstall(q)
        try Migrations.runAll(on: q)
        try q.write { try Self.insert($0, "new", status: "confirmed") }

        try Migrations.runAll(on: q)   // the next launch
        XCTAssertNil(try reviewedAt(q)["new"] ?? nil)
    }

    /// A fresh install has nothing to clear, and must not record the clear in a way
    /// that later catches its own entries.
    func test_a_fresh_install_starts_with_an_empty_backlog_and_keeps_new_entries() throws {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in try Self.seed(db) }
        try Migrations.runAll(on: q)
        XCTAssertNil(try reviewedAt(q)["old1"] ?? nil)
    }

    // MARK: Backups and imports

    /// A backup made before the update goes through the same pipeline when it is
    /// restored — `FinchStore.loadPack` is parse → extract → `runAll` → swap — so it
    /// arrives cleared too. One made after the update carries this migration's
    /// record, so its own unreviewed entries come back unreviewed.
    func test_a_restored_backup_from_before_the_update_is_cleared_and_one_from_after_is_not() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-backlog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        func restore(_ dbFile: URL, into name: String) throws -> DatabaseQueue {
            let built = try Pack.build(.init(
                dbBytes: try Data(contentsOf: dbFile), attachmentFiles: [],
                meta: .init(appVersion: "1", schemaVersion: Schema.version, exportedAt: "2026-11-01T00:00:00Z",
                            exportedFrom: nil, rowCounts: [:])))
            let extracted = try Pack.extract(try Pack.parse(built.bytes), to: dir.appendingPathComponent(name))
            let q = try DatabaseQueue(path: extracted.dbPath.path)
            try Migrations.runAll(on: q)
            return q
        }

        // Before the update.
        let beforeFile = dir.appendingPathComponent("before.sqlite3")
        do {
            let q = try DatabaseQueue(path: beforeFile.path)
            try preUpdateInstall(q)
            try q.close()
        }
        let restoredBefore = try restore(beforeFile, into: "r1")
        XCTAssertNotNil(try reviewedAt(restoredBefore)["old1"] ?? nil)

        // After the update: the clear has run, then a new entry was typed in.
        let afterFile = dir.appendingPathComponent("after.sqlite3")
        do {
            let q = try DatabaseQueue(path: afterFile.path)
            try preUpdateInstall(q)
            try Migrations.runAll(on: q)
            try q.write { try Self.insert($0, "new", status: "confirmed") }
            try q.close()
        }
        let restoredAfter = try restore(afterFile, into: "r2")
        XCTAssertNil(try reviewedAt(restoredAfter)["new"] ?? nil, "a post-update entry stays in the queue")
    }

    /// A database the web made has had its review queue all along (the web's Activity
    /// "Needs review"), so its unreviewed entries are a real queue, not a backlog an
    /// update surfaced. The web never runs GRDB's migrator, which is how it is told
    /// apart. This is also what keeps the projection parity gate's web-made fixture
    /// projecting exactly as the web does.
    func test_a_web_made_database_keeps_its_queue() throws {
        let q = try DatabaseQueue()
        try q.write { db in
            try Schema.apply(to: db)
            try Self.seed(db)
        }
        try Migrations.runAll(on: q)
        let r = try reviewedAt(q)
        XCTAssertNil(r["old1"] ?? nil)
        XCTAssertNil(r["old2"] ?? nil)
    }
}
