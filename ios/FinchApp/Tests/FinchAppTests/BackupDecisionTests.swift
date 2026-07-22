import XCTest
@testable import FinchApp

/// The pure per-write targeting decision: the LOCAL latest is on a fixed daily
/// cadence, the folder archive follows the user's frequency, and forced writes
/// ("Back up now", the pre-restore safety copy) hit both. The two throttles are
/// independent — an hourly folder cadence keeps working even though the device
/// snapshot only refreshes daily.
final class BackupDecisionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func ago(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_800_000_000 - s) }

    func test_forced_writesBothWhenFolderAvailable() {
        let t = BackupDecision.compute(force: true, lastLocalAt: ago(60), folderAvailable: true,
                                       lastFolderAt: ago(60), frequency: .monthly, now: now)
        XCTAssertTrue(t.local)
        XCTAssertTrue(t.folder)
    }

    func test_forced_neverWritesFolderWhenUnavailable() {
        let t = BackupDecision.compute(force: true, lastLocalAt: nil, folderAvailable: false,
                                       lastFolderAt: nil, frequency: .hourly, now: now)
        XCTAssertTrue(t.local)
        XCTAssertFalse(t.folder)
    }

    func test_firstEverBackup_writesLocal() {
        let t = BackupDecision.compute(force: false, lastLocalAt: nil, folderAvailable: false,
                                       lastFolderAt: nil, frequency: .daily, now: now)
        XCTAssertTrue(t.local)
    }

    func test_localThrottle_isDaily_regardlessOfFolderFrequency() {
        // 1h since the local latest: not due, even though the folder runs hourly.
        let t = BackupDecision.compute(force: false, lastLocalAt: ago(3_600), folderAvailable: true,
                                       lastFolderAt: ago(3_600), frequency: .hourly, now: now)
        XCTAssertFalse(t.local)
        XCTAssertTrue(t.folder)    // hourly folder IS due — throttles are independent
    }

    func test_localDue_after24h() {
        let t = BackupDecision.compute(force: false, lastLocalAt: ago(86_400), folderAvailable: false,
                                       lastFolderAt: nil, frequency: .daily, now: now)
        XCTAssertTrue(t.local)
    }

    func test_folderRespectsItsFrequency() {
        // Daily folder, last written 1h ago: local may be due (25h) but folder is not.
        let t = BackupDecision.compute(force: false, lastLocalAt: ago(90_000), folderAvailable: true,
                                       lastFolderAt: ago(3_600), frequency: .daily, now: now)
        XCTAssertTrue(t.local)
        XCTAssertFalse(t.folder)
    }

    func test_nothingDue_writesNothing() {
        let t = BackupDecision.compute(force: false, lastLocalAt: ago(60), folderAvailable: true,
                                       lastFolderAt: ago(60), frequency: .daily, now: now)
        XCTAssertFalse(t.local)
        XCTAssertFalse(t.folder)
    }
}
