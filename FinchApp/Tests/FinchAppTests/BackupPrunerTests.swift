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
}
