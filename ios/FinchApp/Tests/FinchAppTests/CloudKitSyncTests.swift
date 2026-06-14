import XCTest
import CloudKit
import FinchCore
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

    // MARK: - Mutation log (Phase 8 live-loop content model — pure parts)

    /// A SyncMutation round-trips through its CKRecord mapping, including the
    /// Args payload (decoded back to the same bag) and the ledger-zone.
    func test_mutationRecordRoundTrip() {
        let args = Args(["id": .string("e1"), "amount": .double(-12.5), "merchant": .string("Coffee")])
        let m = SyncMutation(id: "mut-1", seq: 7, deviceId: "devA", ledgerId: "personal",
                             action: "addTransaction", argsJSON: SyncMutation.encode(args), ts: "2026-06-15T00:00:00Z")
        let rec = SyncMutationRecord.record(m)
        XCTAssertEqual(rec.recordType, "Mutation")
        XCTAssertEqual(rec.recordID.zoneID.zoneName, "personal")
        let back = SyncMutationRecord.mutation(from: rec)
        XCTAssertEqual(back, m)
        XCTAssertEqual(back?.actionName, .addTransaction)
        XCTAssertEqual(back?.args, args)   // Args is Equatable
    }

    /// A non-Mutation record maps to nil (forward-compat / wrong type guard).
    func test_mutationRecordRejectsWrongType() {
        let other = CloudKitRecordMapper.record(table: "entries", row: ["id": "e1"])
        XCTAssertNil(SyncMutationRecord.mutation(from: other))
    }

    /// The outbox assigns monotonic seqs, drops acked ids, and de-dups applied
    /// remote ids. Uses an isolated temp file so it doesn't touch app state.
    @MainActor func test_outboxOrderingAndDedup() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let box = SyncOutbox(fileURL: tmp)

        let m1 = box.append(action: "createBudget", args: Args([:]), ledgerId: "personal", ts: "t1")
        let m2 = box.append(action: "removeBudget", args: Args([:]), ledgerId: "personal", ts: "t2")
        XCTAssertEqual(box.pending.map(\.seq), [1, 2])
        XCTAssertLessThan(m1.seq, m2.seq)

        box.remove(ids: [m1.id])
        XCTAssertEqual(box.pending.map(\.id), [m2.id])

        XCTAssertTrue(box.markApplied(id: "remote-1"))   // first time → applied
        XCTAssertFalse(box.markApplied(id: "remote-1"))  // second time → skip (idempotent)
        XCTAssertTrue(box.hasApplied(id: "remote-1"))

        // Persistence: a fresh outbox over the same file keeps the pending + seq.
        let reopened = SyncOutbox(fileURL: tmp)
        XCTAssertEqual(reopened.pending.map(\.id), [m2.id])
        XCTAssertEqual(reopened.append(action: "x", args: Args([:]), ledgerId: "personal", ts: "t3").seq, 3)
    }
}
