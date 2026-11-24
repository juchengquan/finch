import XCTest
@testable import FinchApp

/// Phase 5 — the pure backup retention policy (the tested core; the file IO +
/// debounce timing in AutoBackupManager is the untested runtime shell).
final class BackupPrunerTests: XCTestCase {
    private let files = [
        "finch-20260101-090000.finch", "finch-20260102-090000.finch",
        "finch-20260103-090000.finch", "finch-20260104-090000.finch",
    ]

    func test_keepsNewestN() {
        // Keep 2 → prune the 2 oldest.
        XCTAssertEqual(Set(BackupPruner.toPrune(files, keep: 2)),
                       ["finch-20260101-090000.finch", "finch-20260102-090000.finch"])
    }

    func test_nothingToPruneWhenUnderLimit() {
        XCTAssertTrue(BackupPruner.toPrune(files, keep: 14).isEmpty)
        XCTAssertTrue(BackupPruner.toPrune([], keep: 14).isEmpty)
    }

    func test_keepZeroPrunesAll() {
        XCTAssertEqual(BackupPruner.toPrune(files, keep: 0).count, 4)
    }

    // toPruneOwn: in a SHARED folder, a device prunes only ITS OWN newest N —
    // never another device's, never the old suffix-less names.
    func test_toPruneOwn_onlyPrunesOwnNewestN() {
        let shared = [
            "finch-20260101-090000-me0001.finch",   // own, oldest
            "finch-20260102-090000-me0001.finch",   // own
            "finch-20260103-090000-me0001.finch",   // own, newest
            "finch-20260104-090000-other9.finch",   // another device — never pruned
            "finch-20260105-090000.finch",           // old format (no id) — never pruned
        ]
        XCTAssertEqual(Set(BackupPruner.toPruneOwn(shared, deviceId: "me0001", keep: 1)),
                       ["finch-20260101-090000-me0001.finch", "finch-20260102-090000-me0001.finch"])
        XCTAssertEqual(BackupPruner.toPruneOwn(shared, deviceId: "me0001", keep: 2),
                       ["finch-20260101-090000-me0001.finch"])
        XCTAssertTrue(BackupPruner.toPruneOwn(shared, deviceId: "nobody", keep: 1).isEmpty)  // no own files
    }

    /// New names carry a UTC stamp, so a newer backup always reads as newer, wherever
    /// the phone's clock is. Local-time names followed the time zone: east of UTC, a
    /// backup at 04:00 on the 25th was stamped later than one made an hour after it
    /// in another zone — and pruning, which keeps the newest, deleted the newer one.
    func test_utcStampsParseAndCarryTheDeviceId() {
        let t = Date(timeIntervalSince1970: 1_795_550_400)   // 2026-11-24 20:00:00 UTC
        let name = "finch-\(BackupHistory.stamp(t))-me0001.finch"
        XCTAssertEqual(name, "finch-20261124T200000Z-me0001.finch")
        XCTAssertEqual(BackupHistory.date(fromName: name), t)
        XCTAssertEqual(BackupHistory.deviceId(fromName: name), "me0001")
    }

    /// The first backup after this update sits beside one with an old local-time
    /// name. They are ordered by the time each records, not by name: in UTC+8 the
    /// older one's name reads "20261125-040000", which sorts after the newer
    /// "20261124T210000Z", and the newer one was pruned.
    func test_oldAndNewNamesAreOrderedByTheirTime() {
        let older = Date(timeIntervalSince1970: 1_795_550_400)   // 20:00 UTC
        let local = DateFormatter(); local.locale = Locale(identifier: "en_US_POSIX"); local.dateFormat = "yyyyMMdd-HHmmss"
        let legacy = "finch-\(local.string(from: older))-me0001.finch"
        let newer = "finch-\(BackupHistory.stamp(older.addingTimeInterval(3600)))-me0001.finch"
        XCTAssertEqual(BackupPruner.toPrune([newer, legacy], keep: 1), [legacy])
        XCTAssertEqual(BackupPruner.toPruneOwn([newer, legacy], deviceId: "me0001", keep: 1), [legacy])
    }
}
