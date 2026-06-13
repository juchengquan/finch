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
