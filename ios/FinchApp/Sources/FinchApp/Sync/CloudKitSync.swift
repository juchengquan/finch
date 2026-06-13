import Foundation
import CloudKit
import FinchCore

/// Phase 8 — row-level CloudKit sync (supersedes Phase 5's whole-pack sync).
/// This ships the **CI-verifiable core**: the row ↔ CKRecord mapping and the
/// last-writer-wins conflict resolution (pure, unit-tested; CKRecord constructs
/// without an iCloud account). The actual push/fetch loop (`CloudKitSyncService`)
/// compiles but is inert without a signed-in iCloud account, so it can't be
/// runtime-verified in CI — it's gated behind an availability check.

/// Maps a canonical DB row to/from a `CKRecord`. recordType = table name,
/// recordName = the row's `id`; every column becomes a string field (the schema
/// is text/number/JSON, all round-trippable as strings). Pure.
public enum CloudKitRecordMapper {
    public static func record(table: String, row: [String: String]) -> CKRecord {
        let id = row["id"] ?? UUID().uuidString
        let record = CKRecord(recordType: table, recordID: CKRecord.ID(recordName: id))
        for (key, value) in row where key != "id" { record[key] = value as CKRecordValue }
        return record
    }

    public static func row(from record: CKRecord) -> [String: String] {
        var out: [String: String] = ["id": record.recordID.recordName]
        for key in record.allKeys() {
            if let v = record[key] as? String { out[key] = v }
            else if let v = record[key] { out[key] = "\(v)" }
        }
        return out
    }
}

/// Last-writer-wins on `updated_at` — the schema stamps every row. A tie keeps
/// local (idempotent). After a merge the existing audit gate re-validates the
/// double-entry invariants, so field-level merges never break balance. Pure.
public enum CloudKitConflict {
    public enum Winner: Equatable { case local, remote }
    public static func resolve(localUpdatedAt: String?, remoteUpdatedAt: String?) -> Winner {
        switch (localUpdatedAt, remoteUpdatedAt) {
        case let (l?, r?): return r > l ? .remote : .local
        case (nil, _?):    return .remote
        default:           return .local
        }
    }
}

/// The push/fetch loop. Compiles, but every method no-ops unless an iCloud
/// account is available (CI / a bare simulator has none) — so it's not
/// runtime-verifiable here. The mapping + conflict core above IS tested.
@MainActor
public final class CloudKitSyncService {
    public static let shared = CloudKitSyncService()
    private let container = CKContainer(identifier: "iCloud.com.juchengquan.finch")

    public func accountAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    /// Push changed rows as CKRecords to the private DB (one zone). No-op without
    /// an account. Full CKSyncEngine state-serialization is the remaining work.
    public func push(table: String, rows: [[String: String]]) async {
        guard await accountAvailable() else { return }
        let db = container.privateCloudDatabase
        let records = rows.map { CloudKitRecordMapper.record(table: table, row: $0) }
        _ = try? await db.modifyRecords(saving: records, deleting: [])
    }
}
