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

        // A purchase paid from several accounts takes a single category. The rules
        // engine used to break that (its `split` action ignored the account leg
        // count), and the projection copies an entry's whole `splits` array onto
        // every account-leg row — so such an entry had its categories summed once
        // per payment leg and budgets alerted at twice the real spend.
        //
        // The shape is now refused at write time, which strands any row already in
        // it. `rebuildEntry` rebuilds legs when `legsProvided || dateChanged`
        // (:682) and validates the result, so **changing the date** carries the
        // forbidden shape forward and throws — an ordinary edit, failing with an
        // error about leg shapes that never hints deleting is the only way out.
        // A header-only edit still works; the doubled totals persist either way.
        migrator.registerMigration("2026-08-03-collapse-both-axes-entries") { db in
            try Self.collapseBothAxesEntries(db)
            try Self.ensureMetadataRow(db)   // re-stamp schema_version
        }

        // Links the transactions of one grid purchase (see Schema's `group_id`).
        // Additive + nullable; tolerant of a duplicate column, since an imported
        // web pack may already carry it while lacking GRDB's bookkeeping table.
        migrator.registerMigration("2026-08-03-entry-group-id") { db in
            try Self.addEntryGroupId(db)
            try Self.ensureMetadataRow(db)   // re-stamp schema_version
        }

        // Account detail fields + budgets.notes (web migration 2026-08-12).
        // Purely additive and all nullable, so existing rows read as "unset" and
        // nothing is backfilled.
        migrator.registerMigration("2026-08-12-detail-fields") { db in
            try Self.addDetailFields(db)
            try Self.ensureMetadataRow(db)   // re-stamp schema_version
        }

        // entries.pending_kind (web migration 2026-08-12T01). Additive and nullable;
        // the refresh backfills it from the date, so nothing is migrated in place.
        migrator.registerMigration("2026-08-12-pending-kind") { db in
            try Self.addPendingKind(db)
            try Self.ensureMetadataRow(db)   // re-stamp schema_version
        }

        return migrator
    }

    /// Add the account detail columns and `budgets.notes`, tolerating a database
    /// that already has them. Exposed for the same reason as `addEntryGroupId`:
    /// on a fresh database the migration is recorded as applied before a test
    /// could run it.
    static func addDetailFields(_ db: Database) throws {
        for ddl in [
            "ALTER TABLE accounts ADD COLUMN icon TEXT",
            "ALTER TABLE accounts ADD COLUMN notes TEXT",
            "ALTER TABLE accounts ADD COLUMN statement_day INTEGER",
            "ALTER TABLE accounts ADD COLUMN due_day INTEGER",
            "ALTER TABLE accounts ADD COLUMN credit_limit REAL",
            "ALTER TABLE accounts ADD COLUMN institution TEXT",
            "ALTER TABLE accounts ADD COLUMN account_last4 TEXT",
            "ALTER TABLE budgets ADD COLUMN notes TEXT",
            "ALTER TABLE budgets ADD COLUMN icon TEXT",
            "ALTER TABLE budgets ADD COLUMN color TEXT",
        ] {
            do { try db.execute(sql: ddl) }
            catch { if !"\(error)".contains("duplicate column") { throw error } }
        }
    }

    /// Add `entries.pending_kind` and BACKFILL it, tolerating a database that already
    /// has the column. Exposed for the same reason as `addEntryGroupId`: on a fresh
    /// database the migration is recorded as applied before a test could run it, so a
    /// test must be able to call the real thing rather than a copy of its SQL.
    ///
    /// The backfill is not optional. Without it every existing pending row sits at
    /// "pending + NULL" until the first refresh — a state indistinguishable from a bug,
    /// which would force every reader back onto the date and defeat the column.
    ///
    /// `date('now')` is UTC and can be a day off for a user far from it. Harmless: the
    /// first refresh runs on the device's own wall day and corrects any row it got wrong.
    static func addPendingKind(_ db: Database) throws {
        do { try db.execute(sql: "ALTER TABLE entries ADD COLUMN pending_kind TEXT") }
        catch { if !"\(error)".contains("duplicate column") { throw error } }
        try db.execute(sql: """
            UPDATE entries
               SET pending_kind = CASE WHEN date > date('now') THEN 'upcoming' ELSE 'due' END
             WHERE status = 'pending'
            """)
    }

    /// Add `entries.group_id`, tolerating a database that already has it.
    /// Exposed so it can be tested directly — a migration is recorded as applied
    /// on a fresh database before any test could exercise it.
    static func addEntryGroupId(_ db: Database) throws {
        do { try db.execute(sql: "ALTER TABLE entries ADD COLUMN group_id TEXT") }
        catch { if !"\(error)".contains("duplicate column") { throw error } }
    }

    /// Merge every plain category leg of a both-axes entry into its dominant one
    /// (largest `abs(amount_base)`), preserving the total so the entry re-seals.
    ///
    /// The dominant category is already the single one the projection displays for
    /// such an entry (`Projection.enrichLegTxs`), so this preserves what the user
    /// currently sees while removing what they cannot. Equity legs — the `sys:fx`
    /// residue — are left alone: they are not part of the split.
    ///
    /// Exposed rather than inlined so it can be tested directly. A migration is
    /// recorded as applied on a fresh database before any test could insert a row
    /// for it to find.
    static func collapseBothAxesEntries(_ db: Database) throws {
        let entryIds = try String.fetchAll(db, sql: """
            SELECT e.id FROM entries e
             WHERE (SELECT COUNT(*) FROM postings p
                     WHERE p.entry_id = e.id AND p.account_id IS NOT NULL) > 1
               AND (SELECT COUNT(*) FROM postings p JOIN categories c ON c.id = p.category_id
                     WHERE p.entry_id = e.id AND c.kind != 'equity') > 1
            """)
        for entryId in entryIds {
            let legs = try Row.fetchAll(db, sql: """
                SELECT p.id AS pid, p.amount_base FROM postings p JOIN categories c ON c.id = p.category_id
                 WHERE p.entry_id = ? AND c.kind != 'equity'
                 ORDER BY ABS(p.amount_base) DESC, p.sort_order
                """, arguments: [entryId])
            guard let dominant = legs.first else { continue }
            let total = legs.reduce(0.0) { $0 + ($1["amount_base"] as Double) }
            let keepId: String = dominant["pid"]

            // Postings on a sealed entry are immutable, so unseal, merge, reseal.
            // The total is unchanged, so the seal's balance check still passes.
            try db.execute(sql: "UPDATE entries SET sealed = 0 WHERE id = ?", arguments: [entryId])
            for leg in legs.dropFirst() {
                try db.execute(sql: "DELETE FROM postings WHERE id = ?", arguments: [leg["pid"] as String])
            }
            // A category leg is always in ledger base, so `amount` mirrors it.
            try db.execute(sql: "UPDATE postings SET amount = ?, amount_base = ? WHERE id = ?",
                           arguments: [total, total, keepId])
            try db.execute(sql: "UPDATE entries SET sealed = 1 WHERE id = ?", arguments: [entryId])
        }
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
