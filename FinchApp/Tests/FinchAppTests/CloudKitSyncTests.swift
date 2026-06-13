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
}
