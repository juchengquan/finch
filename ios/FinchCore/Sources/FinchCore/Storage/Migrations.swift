import Foundation
import GRDB

/// The iOS port's mirror of the web's migration runner `migrate(exec, { fresh })`
/// (`schema.ts:688`). Phase 1.0 is fresh-DB-only: apply the canonical `SCHEMA`
/// (already the post-cutover DE shape) and stamp the metadata row. The web's
/// `2026-06-14` DE data-move is intentionally absent from `MIGRATIONS` (dead
/// code in git history only) — there is no `cutover.ts` to port (D1).
public enum Migrations {
    public static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // The single baseline migration: apply the full canonical schema, then
        // port `ensureMetadataRow` (schema.ts:665).
        migrator.registerMigration("baseline-2026-06-14") { db in
            try Schema.apply(to: db)
            try Self.ensureMetadataRow(db)
        }

        // First post-baseline migration: group colors (web migration
        // 2026-07-17). Tolerant of duplicate columns — imported web packs may
        // already carry them while lacking GRDB's bookkeeping table.
        migrator.registerMigration("2026-07-17-group-color") { db in
            for table in ["budget_groups", "account_groups"] {
                do { try db.execute(sql: "ALTER TABLE \(table) ADD COLUMN color TEXT") }
                catch { if !"\(error)".contains("duplicate column") { throw error } }
            }
            try Self.ensureMetadataRow(db)   // re-stamp schema_version
        }

        // Budget match columns (web migration 2026-07-21): income budgets (goals)
        // track real transactions by tag/merchant. Additive + nullable; tolerant
        // of duplicate columns (imported web packs may already carry them).
        migrator.registerMigration("2026-07-21-budget-match-columns") { db in
            for col in ["tag_ids", "counterparty_ids"] {
                do { try db.execute(sql: "ALTER TABLE budgets ADD COLUMN \(col) TEXT") }
                catch { if !"\(error)".contains("duplicate column") { throw error } }
            }
            try Self.ensureMetadataRow(db)   // re-stamp schema_version
        }

        // Scheduled occurrence link (web migration 2026-07-22). Additive +
        // nullable; tolerant of duplicate columns (imported web packs may already
        // carry it).
        migrator.registerMigration("2026-07-22-entry-occurrence-date") { db in
            do { try db.execute(sql: "ALTER TABLE entries ADD COLUMN occurrence_date TEXT") }
            catch { if !"\(error)".contains("duplicate column") { throw error } }
            try Self.ensureMetadataRow(db)   // re-stamp schema_version
        }

        return migrator
    }

    /// Port of `ensureMetadataRow` (schema.ts:665): INSERT the id=1 metadata row
    /// (app_name + schema_version + app_version); UPDATE on conflict. Phase 1.0
    /// only ever hits the INSERT path (the baseline runs on a fresh DB).
    static func ensureMetadataRow(_ db: Database) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try db.execute(sql: """
            INSERT INTO db_metadata (id, app_name, schema_version, app_version, created_at, updated_at)
            VALUES (1, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              schema_version = excluded.schema_version,
              app_version = excluded.app_version,
              updated_at = excluded.updated_at
            """, arguments: [Schema.appName, Schema.version, FinchCore.version, now, now])
    }

    /// Run the migration on the given queue. Idempotent.
    public static func runAll(on dbQueue: DatabaseQueue) throws {
        try makeMigrator().migrate(dbQueue)
    }
}
