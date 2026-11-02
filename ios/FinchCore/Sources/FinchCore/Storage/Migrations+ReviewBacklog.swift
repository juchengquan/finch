import Foundation
import GRDB

extension Migrations {
    /// Mark reviewed every settled entry an iOS build wrote before the review queue
    /// existed — once.
    ///
    /// `entries.reviewed_at` is the web's (its triage queue, #104), and NULL there
    /// means "still needs a look". iOS stored the column but had no queue until #809,
    /// so nothing on iOS ever stamped it: every entry typed in before then is NULL.
    /// The update that brought the queue therefore opened "Needs review" on the
    /// user's whole history — 2,000+ rows for a long-time user, a queue nobody can
    /// work through and that buries the few entries it is meant to catch. Those rows
    /// were never waiting for anyone; they predate the question.
    ///
    /// So the update answers it for them. What it leaves alone:
    ///   - **entries entered from now on.** This runs once (GRDB records it), so the
    ///     next launch's migrator pass does not sweep them away;
    ///   - **pending rows.** They are not in the queue — they wait in "To confirm" —
    ///     and confirming one later is a new event that should get its look;
    ///   - **an entry already reviewed** keeps its own stamp;
    ///   - **`updated_at`**, because this is not an edit. Like
    ///     `Entries.refreshPendingKind`, it also stays out of `Apply`: each device
    ///     runs the same migration on its own copy.
    ///
    /// **iOS-only, by decision.** The web has had its "Needs review" queue since
    /// #104, so a NULL in a web-made database is a queue its user has been shown all
    /// along, not a backlog an update surfaced — clearing it would be hiding work,
    /// not removing noise. `runAll` tells the two apart by GRDB's own bookkeeping
    /// table, which only an iOS build ever writes (see `runAll`), so the web's
    /// SCHEMA_VERSION does not move and no fixture changes. It is also why the
    /// projection parity gate, which migrates a web-made fixture, is unaffected.
    ///
    /// A restored or imported backup takes the same path — `FinchStore.loadPack`
    /// migrates the staged database before swapping it in — so one made by an iOS
    /// build before the update arrives cleared, and one made after it carries this
    /// migration's record and keeps its own unreviewed entries.
    ///
    /// Returns the number of entries stamped. Exposed for the same reason as
    /// `addEntryGroupId`: on a fresh database the migration is recorded as applied
    /// before a test could insert a row for it to find.
    @discardableResult
    static func clearReviewBacklog(_ db: Database) throws -> Int {
        try db.execute(sql: """
            UPDATE entries SET reviewed_at = datetime('now')
             WHERE reviewed_at IS NULL AND status = 'confirmed'
            """)
        return db.changesCount
    }

    /// GRDB's bookkeeping table: present in every database an iOS build has opened,
    /// absent from one the web made. Read BEFORE the migrator runs, since the
    /// migrator creates it.
    static func wasOpenedByIOS(_ dbQueue: DatabaseQueue) throws -> Bool {
        try dbQueue.read { try $0.tableExists("grdb_migrations") }
    }
}
