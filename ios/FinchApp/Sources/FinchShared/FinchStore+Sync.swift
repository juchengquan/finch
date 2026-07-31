import Foundation
import FinchCore
import GRDB

/// Phase 8 scaffold — raw row extraction for the CloudKit bootstrap upload. Pure
/// reads off the live DB; no network. Each canonical row becomes a string-keyed
/// dict (the schema is text/number/JSON, all round-trippable as strings — the
/// same shape `CloudKitRecordMapper` maps to a `CKRecord`).
extension FinchStore {
    /// Every row of a canonical `table` as `[column: stringValue]`. Returns empty
    /// for an unknown table (allowlisted via `CloudKitBootstrap.tables`, so the
    /// interpolated name is never user input) or before the DB is open. BLOBs are
    /// skipped (none of the synced columns are blobs); NULLs are omitted.
    func syncableRows(table: String) -> [[String: String]] {
        guard let q = dbQueue, CloudKitBootstrap.tables.contains(table) else { return [] }
        return (try? q.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM \(table)").map { row in
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
        }) ?? []
    }
}
