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
}
