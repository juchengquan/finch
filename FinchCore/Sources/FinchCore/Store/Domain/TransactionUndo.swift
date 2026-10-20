import Foundation
import GRDB

/// Undo for a transaction delete. NATIVE-ONLY: the web has no undo, so
/// `restoreTransactions` never enters WRITE_SEQUENCE (it would break fixture
/// regeneration) and is covered by `TransactionUndoTests` instead.
///
/// A delete removes more than the entry the user pointed at, and a restore that
/// re-inserted only that entry would come back subtly wrong. What a
/// `deleteTransaction` takes, and therefore what this captures:
///
/// - the **entry and its postings** — every leg, so a transfer comes back with
///   both accounts and a split with all its category legs;
/// - its **tags** (`entry_tags`) and **attachment rows** (`entry_attachments`),
///   which cascade with the entry;
/// - the **other half of a cross-ledger transfer**, which `deleteTransaction`
///   deletes too, even though it lives in another ledger;
/// - **refund links pointing at it** — `refunded_entry_id` is
///   `ON DELETE SET NULL`, so a refund of a deleted purchase silently forgets
///   what it refunded;
/// - **the group membership of a survivor** — a grid purchase left with one
///   member has its `group_id` cleared (`clearGroupIfAlone`);
/// - **cached figures the delete rewrote**: each touched account's
///   `updated_at` (its balance is recomputed, not restored) and any budget
///   rollover the delete invalidated;
/// - the **skip the app's delete recorded** (`deleteTransactionSkippingOccurrence`)
///   for the scheduled occurrence a row fulfilled — derived from the restored
///   rows themselves, so it needs nothing in the capture.
///
/// Every row comes back under its ORIGINAL id — and rowid, where it is free — so
/// a route, a selection, a Spotlight item or a receipt path naming it still
/// resolves. Attachment FILES are not the engine's business (it is
/// filesystem-agnostic); the app keeps them on disk until the undo expires.
///
/// The flow is two reads around the ordinary delete, so the delete itself still
/// goes through the chokepoint unchanged: `capture` BEFORE (while the rows
/// exist), `settle` AFTER (keeping only what actually went — a batch skips an op
/// the engine rejects), then `restoreTransactions` with `settled.args`.
public enum TransactionUndo {

    public static let handlers: [ActionName: Apply.Handler] = [
        .restoreTransactions: restore,
    ]

    /// Read everything deleting `txIds` could remove or rewrite. `txIds` take the
    /// same ids `deleteTransaction` does — a Tx (account-posting) id or an entry id.
    /// Unresolvable ids are skipped, exactly as the delete skips them.
    public static func capture(_ db: Database, txIds: [String]) throws -> DeletedTransactions {
        var ids: [String] = []
        func add(_ id: String) { if !ids.contains(id) { ids.append(id) } }
        for txId in txIds {
            guard let ref = try Entries.resolveEntryRef(db, txId) else { continue }
            add(ref.entryId)
            // The delete takes both halves of a cross-ledger transfer, so the
            // capture must too — the partner is in another ledger and never selected.
            if let link = try String.fetchOne(db, sql: "SELECT interledger_link_id FROM entries WHERE id = ?",
                                              arguments: [ref.entryId]) {
                for half in try String.fetchAll(db, sql: "SELECT id FROM entries WHERE interledger_link_id = ? ORDER BY id",
                                                arguments: [link]) { add(half) }
            }
        }
        var snap = DeletedTransactions()
        guard !ids.isEmpty else { return snap }
        let inList = placeholders(ids.count)
        let args = StatementArguments(ids)
        snap.entries = try rows(db, "SELECT rowid AS \(rowidKey), * FROM entries WHERE id IN \(inList) ORDER BY rowid", args)
        snap.postings = try rows(db, "SELECT rowid AS \(rowidKey), * FROM postings WHERE entry_id IN \(inList) ORDER BY rowid", args)
        snap.entryTags = try rows(db, "SELECT rowid AS \(rowidKey), * FROM entry_tags WHERE entry_id IN \(inList) ORDER BY rowid", args)
        snap.attachments = try rows(db, "SELECT rowid AS \(rowidKey), * FROM entry_attachments WHERE entry_id IN \(inList) ORDER BY rowid", args)
        snap.refundLinks = try Row.fetchAll(db, sql: """
            SELECT id, refunded_entry_id FROM entries
             WHERE refunded_entry_id IN \(inList) AND id NOT IN \(inList) ORDER BY id
            """, arguments: args + args).map { DeletedTransactions.Link(id: $0["id"], value: $0["refunded_entry_id"]) }
        snap.groupLinks = try Row.fetchAll(db, sql: """
            SELECT id, group_id FROM entries
             WHERE group_id IN (SELECT group_id FROM entries WHERE id IN \(inList) AND group_id IS NOT NULL)
               AND id NOT IN \(inList) ORDER BY id
            """, arguments: args + args).map { DeletedTransactions.Link(id: $0["id"], value: $0["group_id"]) }
        snap.accounts = try rows(db, """
            SELECT id, updated_at FROM accounts
             WHERE id IN (SELECT account_id FROM postings WHERE entry_id IN \(inList) AND account_id IS NOT NULL) ORDER BY id
            """, args)
        snap.budgets = try rows(db, """
            SELECT id, last_rolled_period, carry_forward, updated_at FROM budgets
             WHERE last_rolled_period IS NOT NULL ORDER BY id
            """, [])
        return snap
    }

    /// Narrow a capture to what the delete actually removed or rewrote. Call
    /// AFTER the delete, on the same database.
    public static func settle(_ captured: DeletedTransactions, _ db: Database) throws -> DeletedTransactions {
        var gone = Set<String>()
        for id in captured.entryIds
        where try Int.fetchOne(db, sql: "SELECT 1 FROM entries WHERE id = ?", arguments: [id]) == nil {
            gone.insert(id)
        }
        var s = DeletedTransactions()
        guard !gone.isEmpty else { return s }
        func owned(_ r: [String: JSONValue], _ key: String) -> Bool {
            if case .string(let id)? = r[key] { return gone.contains(id) }
            return false
        }
        s.entries = captured.entries.filter { owned($0, "id") }
        s.postings = captured.postings.filter { owned($0, "entry_id") }
        s.entryTags = captured.entryTags.filter { owned($0, "entry_id") }
        s.attachments = captured.attachments.filter { owned($0, "entry_id") }
        // A back-link is worth restoring only where the delete actually cleared it:
        // the survivor still exists and the column is now empty.
        func cleared(_ column: String, on id: String) throws -> Bool {
            guard let row = try Row.fetchOne(db, sql: "SELECT \(column) FROM entries WHERE id = ?", arguments: [id])
            else { return false }
            return (row[column] as String?) == nil
        }
        s.refundLinks = try captured.refundLinks.filter { l in
            guard gone.contains(l.value), !gone.contains(l.id) else { return false }
            return try cleared("refunded_entry_id", on: l.id)
        }
        s.groupLinks = try captured.groupLinks.filter { l in
            guard !gone.contains(l.id) else { return false }
            return try cleared("group_id", on: l.id)
        }
        let touched = Set(s.postings.compactMap { r -> String? in
            if case .string(let a)? = r["account_id"] { return a }; return nil
        })
        s.accounts = captured.accounts.filter { if case .string(let id)? = $0["id"] { return touched.contains(id) }; return false }
        s.budgets = try captured.budgets.filter { b in
            guard case .string(let id)? = b["id"] else { return false }
            let now = try rows(db, "SELECT id, last_rolled_period, carry_forward, updated_at FROM budgets WHERE id = ?", [id]).first
            return now != nil && (now?["last_rolled_period"] != b["last_rolled_period"] || now?["carry_forward"] != b["carry_forward"])
        }
        return s
    }

    // MARK: restoreTransactions

    /// Put a settled capture back, in the one write transaction `Apply` opens.
    ///
    /// Refuses — with nothing written — when the ledger has moved on underneath
    /// it: a restored id already taken, or a row it needs (account, category, tag,
    /// merchant, ledger) gone. The app expires an undo on any other write, so this
    /// is the backstop for a stale snapshot replayed from somewhere else (a sync
    /// replay), not the primary rule.
    static func restore(_ db: Database, _ args: Args) throws {
        let snap = try args.to(DeletedTransactions.self)
        guard !snap.entries.isEmpty else { return }
        for (table, rows) in [("entries", snap.entries), ("postings", snap.postings), ("entry_attachments", snap.attachments)] {
            for r in rows {
                guard case .string(let id)? = r["id"] else { throw stale() }
                if try Int.fetchOne(db, sql: "SELECT 1 FROM \(table) WHERE id = ?", arguments: [id]) != nil { throw stale() }
            }
        }
        do {
            // Entries go in unsealed (postings can only be inserted into an unsealed
            // entry) and without their refund link (it may point at another entry of
            // this same restore that is not in yet); both are set right after.
            try insert(db, "entries", snap.entries, override: ["sealed": .int(0), "refunded_entry_id": .null])
            try insert(db, "postings", snap.postings)
            for e in snap.entries {
                // Sealing fires the balance check, so a restored entry is held to the
                // same rule as a freshly posted one.
                try db.execute(sql: "UPDATE entries SET sealed = ?, refunded_entry_id = ? WHERE id = ?",
                               arguments: [bind(e["sealed"]), bind(e["refunded_entry_id"]), bind(e["id"])])
            }
            try insert(db, "entry_tags", snap.entryTags)
            try insert(db, "entry_attachments", snap.attachments)
            for l in snap.refundLinks {
                try db.execute(sql: "UPDATE entries SET refunded_entry_id = ? WHERE id = ? AND refunded_entry_id IS NULL",
                               arguments: [l.value, l.id])
            }
            for l in snap.groupLinks {
                try db.execute(sql: "UPDATE entries SET group_id = ? WHERE id = ? AND group_id IS NULL",
                               arguments: [l.value, l.id])
            }
            // Balances are recomputed from the restored postings — the truth — and
            // only the timestamp the recompute stamps is put back.
            for a in snap.accounts {
                guard case .string(let id)? = a["id"] else { continue }
                try Entries.recomputeAccountFromPostings(db, id)
                try db.execute(sql: "UPDATE accounts SET updated_at = ? WHERE id = ?", arguments: [bind(a["updated_at"]), id])
            }
            for b in snap.budgets {
                try db.execute(sql: "UPDATE budgets SET last_rolled_period = ?, carry_forward = ?, updated_at = ? WHERE id = ?",
                               arguments: [bind(b["last_rolled_period"]), bind(b["carry_forward"]), bind(b["updated_at"]), bind(b["id"])])
            }
            // The app's delete counted a linked row's occurrence as skipped. With the
            // row back the occurrence is posted again, so the skip goes — otherwise a
            // later delete by any other path would leave it skipped, not due. A no-op
            // for a row nothing skipped.
            for e in snap.entries {
                guard case .string(let template)? = e["source_template_id"],
                      case .string(let date)? = e["occurrence_date"].flatMap({ $0 == .null ? nil : $0 }) ?? e["date"]
                else { continue }
                try Scheduled.unskip(db, Args(["templateId": .string(template), "date": .string(date)]))
            }
        } catch is DatabaseError {
            // A foreign key with nothing left to point at, a dedup collision, a
            // balance that no longer seals: all mean "the ledger changed since".
            throw stale()
        }
    }

    static func stale() -> I18nError {
        I18nError("error.undo.stale", [:], "This can't be undone any more — the ledger changed since the delete.")
    }

    // MARK: Row plumbing

    /// The key the capture stores a row's SQLite rowid under. Kept so a restored
    /// row lands back at the same place in insertion order — the tie-breaker for
    /// rows a query's ORDER BY cannot tell apart.
    static let rowidKey = "_rowid"

    private static func placeholders(_ n: Int) -> String {
        "(" + Array(repeating: "?", count: n).joined(separator: ",") + ")"
    }

    private static func rows(_ db: Database, _ sql: String, _ args: StatementArguments) throws -> [[String: JSONValue]] {
        try Row.fetchAll(db, sql: sql, arguments: args).map { row in
            var o: [String: JSONValue] = [:]
            for (col, dbv) in row {
                switch dbv.storage {
                case .null: o[col] = .null
                case .int64(let i): o[col] = .int(Int(i))
                case .double(let d): o[col] = .double(d)
                case .string(let s): o[col] = .string(s)
                case .blob: throw I18nError("error.undo.unsupported", [:], "This transaction can't be captured for undo")
                }
            }
            return o
        }
    }

    private static func bind(_ v: JSONValue?) -> DatabaseValue {
        switch v {
        case .int(let i)?: return i.databaseValue
        case .double(let d)?: return d.databaseValue
        case .string(let s)?: return s.databaseValue
        case .bool(let b)?: return (b ? 1 : 0).databaseValue
        default: return .null
        }
    }

    /// INSERT each row under its captured column names — validated against the
    /// table's real columns, because a snapshot can arrive from outside (a sync
    /// replay) and a column name is spliced into the SQL. The captured rowid is
    /// reused when it is still free.
    private static func insert(_ db: Database, _ table: String, _ rows: [[String: JSONValue]],
                               override: [String: JSONValue] = [:]) throws {
        guard !rows.isEmpty else { return }
        let known = Set(try db.columns(in: table).map(\.name))
        for r in rows {
            var cols: [String] = [], vals: [DatabaseValue] = []
            for (k, v) in r.sorted(by: { $0.key < $1.key }) {
                if k == rowidKey {
                    guard case .int(let rid) = v,
                          try Int.fetchOne(db, sql: "SELECT 1 FROM \(table) WHERE rowid = ?", arguments: [rid]) == nil
                    else { continue }
                    cols.append("rowid"); vals.append(rid.databaseValue)
                    continue
                }
                guard known.contains(k) else { throw stale() }
                cols.append("\"\(k)\""); vals.append(bind(override[k] ?? v))
            }
            try db.execute(sql: "INSERT INTO \(table) (\(cols.joined(separator: ", "))) VALUES \(placeholders(cols.count))",
                           arguments: StatementArguments(vals))
        }
    }
}

/// What a transaction delete removed — the payload of `restoreTransactions`.
/// Rows are raw column maps (plus `_rowid`) so the restore puts back exactly what
/// was there, including iOS-only columns the parity snapshot ignores.
public struct DeletedTransactions: Codable, Sendable, Equatable {
    public var entries: [[String: JSONValue]] = []
    public var postings: [[String: JSONValue]] = []
    public var entryTags: [[String: JSONValue]] = []
    public var attachments: [[String: JSONValue]] = []
    /// A surviving entry → the deleted entry it refunds.
    public var refundLinks: [Link] = []
    /// A surviving grid member → the group id the delete cleared from it.
    public var groupLinks: [Link] = []
    /// Touched accounts' `id` + `updated_at`.
    public var accounts: [[String: JSONValue]] = []
    /// Budgets whose rollover cache the delete reset.
    public var budgets: [[String: JSONValue]] = []

    /// One surviving row's link to restore: `id` is the survivor, `value` what
    /// the column held before the delete cleared it.
    public struct Link: Codable, Sendable, Equatable {
        public let id: String
        public let value: String
    }

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }

    /// The deleted entries' ids, in capture order.
    public var entryIds: [String] {
        entries.compactMap { if case .string(let id)? = $0["id"] { return id }; return nil }
    }

    /// `rel_path` of every attachment row the delete took — the files the app
    /// must keep on disk while an undo is still possible.
    public var attachmentRelPaths: [String] {
        attachments.compactMap { if case .string(let p)? = $0["rel_path"] { return p }; return nil }
    }

    /// The chokepoint args for `restoreTransactions`.
    public var args: Args {
        get throws {
            let data = try JSONEncoder().encode(self)
            return try JSONDecoder().decode(Args.self, from: data)
        }
    }
}
