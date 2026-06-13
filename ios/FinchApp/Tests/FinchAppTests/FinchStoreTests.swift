import XCTest
@testable import FinchApp
import FinchCore

/// DESIGN §4 — the import pipeline. Uses CLEAN/dirty web-built `.finch` fixtures
/// (the round-trip samples; no pre-DE fixture, D1).
final class FinchStoreTests: XCTestCase {
    @MainActor
    func test_loadPackProjectsAndPersists() async throws {
        let packURL = try XCTUnwrap(Bundle.module.url(
            forResource: "Fixtures/roundtrip/sample", withExtension: "finch"))
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: packURL))

        // Projected state is populated...
        XCTAssertFalse(store.txns.isEmpty)
        XCTAssertFalse(store.accounts.isEmpty)
        // ...and the DB was swapped into Application Support (persists).
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.liveDBURL.path))
    }

    @MainActor
    func test_loadPackThrowsAuditFailedOnDirtyPack() async throws {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "Fixtures/roundtrip/dirty", withExtension: "finch"))
        let store = FinchStore()
        do {
            try await store.loadPack(from: try Data(contentsOf: url))
            XCTFail("expected auditFailed")
        } catch PackError.auditFailed(let problems) {
            XCTAssertFalse(problems.isEmpty)
        }
    }
}
