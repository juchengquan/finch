import XCTest
import FinchCore
@testable import FinchApp

/// A failed import swap rolls the database file back — and must reopen it. It left
/// the connection closed, so the app ran on with no database until relaunched.
@MainActor
final class ImportSwapFailureTests: XCTestCase {
    func test_aFailedSwapLeavesTheLiveDatabaseOpen() async throws {
        let packURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: packURL))
        let before = try XCTUnwrap(store.dbQueue)
        let accounts = try await before.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM accounts") }
        XCTAssertGreaterThan(accounts ?? 0, 0)

        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID()).sqlite3")
        XCTAssertThrowsError(try store.swapInAndProject(stagedDB: missing, stagedAttachments: nil, problems: []))

        let q = try XCTUnwrap(store.dbQueue, "the rolled-back database is open again")
        let n = try await q.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM accounts") }
        XCTAssertEqual(n, accounts)
    }

    /// Under XCTest every file the app writes lives in the test directory, beside the
    /// test database. Backups, shared receipts and the sync outbox named Application
    /// Support themselves, so a test run wrote into the real backup folder.
    func test_testsWriteNothingIntoTheRealDataFolder() {
        let tests = FinchStore.dataDirectory.standardizedFileURL.path
        XCTAssertTrue(tests.hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path))
        for url in [AutoBackupManager.shared.backupsDir, PendingAttachmentImporter.attachmentsRoot,
                    FinchStore.shared.attachmentsRoot, FinchStore.shared.liveDBURL] {
            XCTAssertTrue(url.standardizedFileURL.path.hasPrefix(tests), url.path)
        }
    }
}
