import Foundation
import GRDB

/// Phase 8 — the fresh-device **down-sync seed**: re-hydrate an empty DB from the
/// row-mirror bootstrap records a new install pulls from CloudKit. This is the
/// piece the live loop deliberately left unbuilt; it's implemented + unit-tested
/// here WITHOUT any CloudKit dependency (it's pure DB I/O), so it's safe to land
/// and verify ahead of provisioning.
///
/// Shape: `[table: [rowDict]]` → fresh (already-migrated) DB → the engine's own
/// triggers + audit gate validate it. Two subtleties the engine forces on us:
///   1. **Sealed two-phase write.** `tr_post_sealed_insert` rejects a posting
///      whose entry is already `sealed = 1`. So entries are inserted `sealed = 0`,
///      then postings, then a single `UPDATE entries SET sealed = 1` re-fires
///      `tr_entry_seal` — re-validating that every entry balances.
///   2. **Balance triggers.** `tr_post_balance` increments `accounts.current_balance`
///      on each confirmed-entry posting insert. So accounts are seeded with
///      balance 0 and the triggers rebuild the authoritative balance (audit then
///      checks cached == derived).
public enum DownSync {
    /// FK-safe insertion order over the canonical tables (parents before
    /// children). `app_state` is excluded — it's per-device, never synced.
    public static let insertOrder = [
        "ledgers",
        "account_groups", "categories", "counterparties", "tags", "exchange_rates",
        "accounts",
        "budgets", "scheduled_templates",
        "scheduled_splits",
        "entries",
        "postings",
        "entry_tags", "entry_attachments",
    ]

    /// Read every row of the canonical tables as `[column: stringValue]` — the
    /// upload side (mirrors the app's `syncableRows`, kept here so the round-trip
    /// is testable in FinchCore). BLOBs skipped, NULLs omitted.
    public static func extract(from dbQueue: DatabaseQueue) throws -> [String: [[String: String]]] {
        try dbQueue.read { db in
            var out: [String: [[String: String]]] = [:]
            for table in insertOrder {
                let rows = try Row.fetchAll(db, sql: "SELECT * FROM \(table)")
                out[table] = rows.map { stringRow($0) }
            }
            return out
        }
    }

    /// Ingest row-mirror records into a fresh DB (schema already applied by the
    /// caller) and return the post-ingest audit problems (empty == clean).
    /// All-or-nothing: a FK/trigger rejection rolls the whole seed back.
    @discardableResult
    public static func ingest(into dbQueue: DatabaseQueue,
                              tables: [String: [[String: String]]]) throws -> [Audit.AuditProblem] {
        try dbQueue.write { db in
            for table in insertOrder {
                guard let rows = tables[table], !rows.isEmpty else { continue }
                for row in rows { try insertRow(db, table: table, row: row) }
            }
            // Phase 2 of the sealed write: seal every entry, re-running tr_entry_seal
            // (balance re-validation) on each.
            try db.execute(sql: "UPDATE entries SET sealed = 1 WHERE sealed = 0")
        }
        return try Audit.run(on: dbQueue)
    }

    // MARK: - internals

    private static func insertRow(_ db: Database, table: String, row: [String: String]) throws {
        var r = row
        if table == "entries" { r["sealed"] = "0" }            // insert unsealed (phase 1)
        if table == "accounts" { r["current_balance"] = "0" }  // balance triggers rebuild it
        let cols = Array(r.keys)
        guard !cols.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: cols.count).joined(separator: ",")
        let sql = "INSERT INTO \(table) (\(cols.joined(separator: ","))) VALUES (\(placeholders))"
        // String binding relies on SQLite column affinity (INTEGER/REAL columns
        // coerce "1"/"12.5"); the canonical schema is text/number/JSON only.
        try db.execute(sql: sql, arguments: StatementArguments(cols.map { r[$0] }))
    }

    private static func stringRow(_ row: Row) -> [String: String] {
        var out: [String: String] = [:]
        for column in row.columnNames {
            let value: DatabaseValue = row[column]
            switch value.storage {
            case .string(let s): out[column] = s
            case .int64(let i):  out[column] = String(i)
            case .double(let d): out[column] = String(d)
            case .blob, .null:   break
            }
        }
        return out
    }
}
