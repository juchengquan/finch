import XCTest
import CloudKit
@testable import FinchApp

/// Phase 8 — the CI-verifiable core of row-level CloudKit sync: the row↔CKRecord
/// mapping (round-trips without an iCloud account) and the LWW conflict
/// resolution. The push/fetch loop needs a real iCloud account and isn't tested.
final class CloudKitSyncTests: XCTestCase {
    func test_rowRecordRoundTrip() {
        let row = ["id": "e1", "ledger_id": "l1", "description": "Coffee", "kind": "expense"]
        let record = CloudKitRecordMapper.record(table: "entries", row: row)
        XCTAssertEqual(record.recordType, "entries")
        XCTAssertEqual(record.recordID.recordName, "e1")
        XCTAssertEqual(record["description"] as? String, "Coffee")
        let back = CloudKitRecordMapper.row(from: record)
        XCTAssertEqual(back, row)
    }

    func test_conflictLastWriterWins() {
        XCTAssertEqual(CloudKitConflict.resolve(localUpdatedAt: "2026-05-01", remoteUpdatedAt: "2026-05-02"), .remote)
        XCTAssertEqual(CloudKitConflict.resolve(localUpdatedAt: "2026-05-03", remoteUpdatedAt: "2026-05-02"), .local)
        XCTAssertEqual(CloudKitConflict.resolve(localUpdatedAt: "2026-05-02", remoteUpdatedAt: "2026-05-02"), .local) // tie → local
        XCTAssertEqual(CloudKitConflict.resolve(localUpdatedAt: nil, remoteUpdatedAt: "2026-05-02"), .remote)
        XCTAssertEqual(CloudKitConflict.resolve(localUpdatedAt: "2026-05-02", remoteUpdatedAt: nil), .local)
    }

    // MARK: - Phase 8 scaffold

    /// The bootstrap mirrors the canonical tables minus the per-device app_state.
    func test_bootstrapTablesExcludeAppState() {
        XCTAssertFalse(CloudKitBootstrap.tables.contains("app_state"))
        XCTAssertTrue(CloudKitBootstrap.tables.contains("entries"))
        XCTAssertTrue(CloudKitBootstrap.tables.contains("postings"))
        XCTAssertTrue(CloudKitBootstrap.tables.contains("ledgers"))
    }

    /// `syncableRows` reads the live DB into string-keyed dicts the mapper can
    /// turn into CKRecords. bootstrap() guarantees ≥1 ledger (seeded or
    /// pre-existing); every extracted row carries an id and round-trips through
    /// the mapper. The allowlist guard rejects app_state (per-device) + unknowns.
    /// (Asserts on the extraction mechanism, not specific seeded ids, so it's
    /// robust to a persisted app-support DB across test runs.)
    @MainActor func test_syncableRowsExtractsAndRoundTrips() {
        let store = FinchStore()
        store.bootstrap()
        let ledgers = store.syncableRows(table: "ledgers")
        XCTAssertFalse(ledgers.isEmpty, "bootstrap leaves at least one ledger")
        for row in ledgers {
            XCTAssertNotNil(row["id"])
            XCTAssertEqual(CloudKitRecordMapper.row(from: CloudKitRecordMapper.record(table: "ledgers", row: row)), row)
        }
        // Allowlist guard: app_state (per-device) + unknown tables yield nothing.
        XCTAssertTrue(store.syncableRows(table: "app_state").isEmpty)
        XCTAssertTrue(store.syncableRows(table: "not_a_table").isEmpty)
    }

    /// The single switch persists through SyncPreferences.
    func test_syncPreferenceTogglePersists() {
        let original = SyncPreferences.enabled
        defer { SyncPreferences.enabled = original }
        SyncPreferences.enabled = true
        XCTAssertTrue(SyncPreferences.enabled)
        SyncPreferences.enabled = false
        XCTAssertFalse(SyncPreferences.enabled)
    }
}
