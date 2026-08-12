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

        // Cross-ledger transfers (plans/ios-macos/2026-08-12-cross-ledger-transfers-design.md).
        // Both changes are iOS-ONLY, following entries.group_id: the web has no
        // action that writes either, so nothing that is compared diverges.
        migrator.registerMigration("2026-08-12-entries-interledger-link") { db in
            do { try db.execute(sql: "ALTER TABLE entries ADD COLUMN interledger_link_id TEXT") }
            catch { if !"\(error)".contains("duplicate column") { throw error } }
            try Self.ensureMetadataRow(db)
        }

        // Widen entries.kind to admit the interledger half. GRDB runs migrations
        // with `foreignKeyChecks: .deferred` by DEFAULT, which is what makes
        // dropping `entries` safe: postings/entry_attachments cascade from it, and
        // with checks live the DROP would take every posting with it.
        migrator.registerMigration("2026-08-12-entries-interledger-kind") { db in
            try Self.widenEntryKind(db)
            try Self.ensureMetadataRow(db)
        }

        // Widen categories.system to admit the 4th marker. SQLite cannot ALTER a
        // CHECK, so this is a table rebuild — the same shape as the
        // 2026-07-23-counterparties-global migration above, including leaving the
        // foreign_keys pragma alone: the FK text in postings/budgets still reads
        // "REFERENCES categories(id)" and becomes valid again the moment the
        // rebuilt table is renamed into place.
        migrator.registerMigration("2026-08-12-categories-interledger-system") { db in
            let ddl = try String.fetchOne(db, sql:
                "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'categories'") ?? ""
            if !ddl.contains("interledger") {
                try db.execute(sql: "DROP TABLE IF EXISTS categories_new")
                try db.execute(sql: """
                    CREATE TABLE categories_new (
                      id         TEXT PRIMARY KEY,
                      ledger_id  TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
                      parent_id  TEXT REFERENCES categories(id) ON DELETE SET NULL,
                      name       TEXT NOT NULL,
                      kind       TEXT NOT NULL CHECK(kind IN ('expense','income','equity')),
                      icon       TEXT,
                      color      TEXT,
                      sort_order INTEGER NOT NULL DEFAULT 0,
                      system     TEXT CHECK(system IN ('opening','adjustment','fx','interledger')),
                      created_at TEXT NOT NULL,
                      updated_at TEXT NOT NULL
                    )
                    """)
                try db.execute(sql: """
                    INSERT INTO categories_new (id,ledger_id,parent_id,name,kind,icon,color,sort_order,system,created_at,updated_at)
                      SELECT id,ledger_id,parent_id,name,kind,icon,color,sort_order,system,created_at,updated_at FROM categories
                    """)
                try db.execute(sql: "DROP TABLE categories")
                try db.execute(sql: "ALTER TABLE categories_new RENAME TO categories")
                try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_cat_parent ON categories(parent_id) WHERE parent_id IS NOT NULL")
                try db.execute(sql: "CREATE UNIQUE INDEX IF NOT EXISTS idx_cat_system ON categories(ledger_id, system) WHERE system IS NOT NULL")
                try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_cat_ledger ON categories(ledger_id)")
            }
            try Self.ensureMetadataRow(db)
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
        // The triggers that keep it correct from here on. Additive, which is the whole
        // reason the rule is a trigger and not a CHECK — CREATE TRIGGER can be applied
        // to an existing table, ALTER ... CHECK cannot.
        for ddl in [Self.pendingKindInsertTrigger, Self.pendingKindUpdateTrigger] {
            try db.execute(sql: ddl)
        }
    }

    /// Kept in Swift beside the migration AND in `Schema.ddl` for fresh databases; the
    /// two must stay identical, which `SchemaTests` asserts.
    static let pendingKindInsertTrigger = """
CREATE TRIGGER IF NOT EXISTS tr_entry_pending_kind_insert AFTER INSERT ON entries
FOR EACH ROW WHEN NEW.pending_kind IS NOT (
  CASE WHEN NEW.status <> 'pending' THEN NULL
       WHEN NEW.date > date('now')  THEN 'upcoming'
       ELSE 'due' END)
BEGIN
  UPDATE entries SET pending_kind =
    CASE WHEN NEW.status <> 'pending' THEN NULL
         WHEN NEW.date > date('now')  THEN 'upcoming'
         ELSE 'due' END
   WHERE id = NEW.id;
END
"""

    static let pendingKindUpdateTrigger = """
CREATE TRIGGER IF NOT EXISTS tr_entry_pending_kind_update AFTER UPDATE OF status, date ON entries
FOR EACH ROW WHEN NEW.pending_kind IS NOT (
  CASE WHEN NEW.status <> 'pending' THEN NULL
       WHEN NEW.date > date('now')  THEN 'upcoming'
       ELSE 'due' END)
BEGIN
  UPDATE entries SET pending_kind =
    CASE WHEN NEW.status <> 'pending' THEN NULL
         WHEN NEW.date > date('now')  THEN 'upcoming'
         ELSE 'due' END
   WHERE id = NEW.id;
END
"""

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

    /// Rebuild `entries` so its `kind` CHECK admits `interledger`. SQLite cannot
    /// alter a CHECK, and this table is the spine — 7 indexes, 4 triggers, an FTS
    /// shadow and three tables cascading from it — so rather than transcribe the
    /// DDL (which drifts the moment Schema.swift changes) it renames the old table
    /// aside and lets the CANONICAL schema recreate the real one.
    ///
    /// Exposed for the same reason as `addEntryGroupId`: on a fresh database the
    /// baseline already creates the widened table, so the migration records itself
    /// as applied and a test could never exercise this path through `runAll`.
    static func widenEntryKind(_ db: Database) throws {
        // Match the KIND LIST specifically, not the word anywhere in the table:
        // `interledger_link_id` is a column on this same table, so a substring
        // check for "interledger" is true before the widening ever happens — the
        // migration then skips silently and its tests pass vacuously. (It did.)
        let ddl = try String.fetchOne(db, sql:
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'entries'") ?? ""
        guard !ddl.contains("'refund','interledger'") else { return }

        // Indexes and triggers TRAVEL with a rename, so their names would still be
        // taken and `Schema.apply`'s CREATE … IF NOT EXISTS would silently skip
        // them — leaving the rebuilt table without its seal check or its search
        // sync. Drop them first; the canonical schema puts them back.
        for t in ["tr_entry_seal", "tr_entry_fts_insert", "tr_entry_fts_delete", "tr_entry_fts_update"] {
            try db.execute(sql: "DROP TRIGGER IF EXISTS \(t)")
        }
        for i in ["idx_entry_ledger_date", "idx_entry_pending", "idx_entry_source",
                  "idx_entry_refunded", "idx_entry_counterparty", "idx_entry_unsealed",
                  "idx_entry_dedup"] {
            try db.execute(sql: "DROP INDEX IF EXISTS \(i)")
        }
        // THE load-bearing pragma. Without it, ALTER TABLE … RENAME rewrites every
        // OTHER table's foreign keys to follow the rename — so postings would start
        // cascading from `entries_old`, and the DROP at the end would delete every
        // money line in the database (observed: the sealed-entry trigger aborted the
        // migration, which is the only reason it surfaced loudly rather than
        // silently). GRDB's deferred foreign-key checks do NOT prevent this:
        // deferring postpones constraint VIOLATIONS, while ON DELETE CASCADE is an
        // action that still runs. With legacy mode on, the FKs keep pointing at the
        // name `entries`, which the canonical schema recreates a moment later.
        // This is SQLite's documented procedure for a table rebuild.
        try db.execute(sql: "PRAGMA legacy_alter_table = ON")
        try db.execute(sql: "ALTER TABLE entries RENAME TO entries_old")
        // Every other statement in the DDL is CREATE … IF NOT EXISTS, so applying
        // the whole schema recreates exactly the one table that is missing, plus
        // its indexes and triggers, and no-ops for everything else.
        try Schema.apply(to: db)
        // The copy below fires tr_entry_fts_insert per row, and the shadow still
        // holds the pre-rebuild rows — clear it so the triggers repopulate it once.
        try db.execute(sql: "DELETE FROM entries_fts")
        let cols = """
            id,ledger_id,date,time,description,kind,status,pending_kind,confirmed_at,\
            counterparty_id,refunded_entry_id,source_template_id,occurrence_date,group_id,\
            interledger_link_id,notes,applied_rule_ids,reviewed_at,dedup_hash,sealed,\
            created_at,updated_at
            """.replacingOccurrences(of: "\n", with: "")
        try db.execute(sql: "INSERT INTO entries (\(cols)) SELECT \(cols) FROM entries_old")
        try db.execute(sql: "DROP TABLE entries_old")
        try db.execute(sql: "PRAGMA legacy_alter_table = OFF")
    }

    /// Run the migration on the given queue. Idempotent.
    public static func runAll(on dbQueue: DatabaseQueue) throws {
        try makeMigrator().migrate(dbQueue)
    }
}
