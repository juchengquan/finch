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

        // Global merchants, healed (web migration 2026-07-23). #533 (schema
        // 2026-07-20) dropped counterparties.ledger_id from the baseline DDL but
        // shipped NO migration — databases created before it still carry the
        // per-ledger table, and every NEW-merchant insert fails its NOT NULL
        // constraint ("SQLite error 19"). Guarded rebuild via the standard
        // recreation dance; a no-op when the table is already global. GRDB runs
        // this with deferred foreign-key checks, so the parent-table swap is safe
        // (entries.counterparty_id re-resolves after the RENAME) and integrity is
        // verified at the end of the migration.
        migrator.registerMigration("2026-07-23-counterparties-global") { db in
            let hasLedgerId = try Row.fetchAll(db, sql: "PRAGMA table_info(counterparties)")
                .contains { ($0["name"] as? String) == "ledger_id" }
            if hasLedgerId {
                try db.execute(sql: "DROP TABLE IF EXISTS counterparties_new")
                try db.execute(sql: """
                    CREATE TABLE counterparties_new (
                      id                TEXT PRIMARY KEY,
                      name              TEXT NOT NULL COLLATE NOCASE,
                      is_verified       INTEGER NOT NULL DEFAULT 0,
                      created_at        TEXT NOT NULL,
                      updated_at        TEXT NOT NULL
                    )
                    """)
                try db.execute(sql: """
                    INSERT INTO counterparties_new (id,name,is_verified,created_at,updated_at)
                      SELECT id,name,is_verified,created_at,updated_at FROM counterparties
                    """)
                try db.execute(sql: "DROP TABLE counterparties")
                try db.execute(sql: "ALTER TABLE counterparties_new RENAME TO counterparties")
                try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_counterparty_name ON counterparties(name)")
            }
            try Self.ensureMetadataRow(db)   // re-stamp schema_version
        }

        // A scheduled template's intended time-of-day. Additive + nullable: existing
        // templates keep NULL and post at the firing moment, exactly as before.
        migrator.registerMigration("2026-08-01-scheduled-start-time") { db in
            do { try db.execute(sql: "ALTER TABLE scheduled_templates ADD COLUMN start_time TEXT") }
            catch { if !"\(error)".contains("duplicate column") { throw error } }
            try Self.ensureMetadataRow(db)   // re-stamp schema_version
        }

        // A budget cycle's turnover time. Additive + nullable: NULL means midnight,
        // which is exactly what every existing budget already does.
        migrator.registerMigration("2026-08-01-budget-cycle-time") { db in
            for col in ["start_time", "end_time"] {
                do { try db.execute(sql: "ALTER TABLE budgets ADD COLUMN \(col) TEXT") }
                catch { if !"\(error)".contains("duplicate column") { throw error } }
            }
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
