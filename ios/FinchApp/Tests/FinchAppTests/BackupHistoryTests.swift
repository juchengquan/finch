import XCTest
@testable import FinchApp

/// The pure backup-history builder — filename→date parsing and the local+iCloud
/// merge/dedup. The FileManager / NSMetadataQuery gathering is the untested shell.
final class BackupHistoryTests: XCTestCase {
    private let newer = "finch-20260721-131200.finch"   // Jul 21 13:12:00
    private let mid   = "finch-20260720-090000.finch"   // Jul 20 09:00:00
    private let older = "finch-20260719-082200.finch"   // Jul 19 08:22:00

    func test_dateFromName_parsesValidAndRejectsGarbage() {
        XCTAssertNotNil(BackupHistory.date(fromName: newer))
        XCTAssertNil(BackupHistory.date(fromName: "garbage.finch"))
        XCTAssertNil(BackupHistory.date(fromName: "finch-notadate.finch"))
        XCTAssertNil(BackupHistory.date(fromName: "finch-20260721-131200.txt"))
        // Chronological by construction: a later stamp parses to a later date.
        XCTAssertGreaterThan(BackupHistory.date(fromName: newer)!, BackupHistory.date(fromName: older)!)
    }

    func test_localOnly_isOnDeviceAndDownloaded() {
        let m = BackupHistory.merge(local: [LocalBackup(name: newer, size: 100)], iCloud: [])
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(m[0].name, newer)
        XCTAssertEqual(m[0].size, 100)
        XCTAssertTrue(m[0].onDevice)
        XCTAssertFalse(m[0].inICloud)
        XCTAssertTrue(m[0].downloaded)   // on-device ⇒ bytes present
    }

    func test_iCloudOnly_notDownloaded() {
        let m = BackupHistory.merge(local: [], iCloud: [ICloudBackup(name: mid, size: 200, downloaded: false)])
        XCTAssertEqual(m.count, 1)
        XCTAssertFalse(m[0].onDevice)
        XCTAssertTrue(m[0].inICloud)
        XCTAssertFalse(m[0].downloaded)  // needs a download before restore
        XCTAssertEqual(m[0].size, 200)   // size known from metadata without downloading
    }

    func test_sameNameInBothStores_dedupesToOneEntryOnBoth() {
        let m = BackupHistory.merge(
            local: [LocalBackup(name: newer, size: 128)],
            iCloud: [ICloudBackup(name: newer, size: 128, downloaded: false)])
        XCTAssertEqual(m.count, 1)                 // deduped by filename
        XCTAssertTrue(m[0].onDevice)
        XCTAssertTrue(m[0].inICloud)
        XCTAssertTrue(m[0].downloaded)             // on-device wins
        XCTAssertEqual(m[0].size, 128)             // local size preferred
    }

    func test_merge_sortsNewestFirst_acrossStores() {
        let m = BackupHistory.merge(
            local: [LocalBackup(name: older, size: 1), LocalBackup(name: newer, size: 3)],
            iCloud: [ICloudBackup(name: mid, size: 2, downloaded: false)])
        XCTAssertEqual(m.map(\.name), [newer, mid, older])   // newest → oldest
    }

    func test_unparseableNamesAreDropped() {
        let m = BackupHistory.merge(
            local: [LocalBackup(name: "bogus.finch", size: 1), LocalBackup(name: newer, size: 2)],
            iCloud: [ICloudBackup(name: "also-bad", size: 1, downloaded: true)])
        XCTAssertEqual(m.map(\.name), [newer])
    }
}
