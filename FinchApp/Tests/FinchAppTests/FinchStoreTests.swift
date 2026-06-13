import XCTest
@testable import FinchApp
import FinchCore

/// DESIGN §4 — the import pipeline. Uses CLEAN/dirty web-built `.finch` fixtures
/// (the round-trip samples; no pre-DE fixture, D1).
final class FinchStoreTests: XCTestCase {
    /// Resources are bundled via a folder reference (preserves the
    /// `Fixtures/roundtrip/` hierarchy); reach them through the test bundle.
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: name, withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
    }

    @MainActor
    func test_loadPackProjectsAndPersists() async throws {
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: fixture("sample")))

        // Projected state is populated...
        XCTAssertFalse(store.txns.isEmpty)
        XCTAssertFalse(store.accounts.isEmpty)
        // ...and the DB was swapped into Application Support (persists).
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.liveDBURL.path))
    }

    @MainActor
    func test_loadPackThrowsAuditFailedOnDirtyPack() async throws {
        let store = FinchStore()
        do {
            try await store.loadPack(from: try Data(contentsOf: fixture("dirty")))
            XCTFail("expected auditFailed")
        } catch PackError.auditFailed(let problems) {
            XCTAssertFalse(problems.isEmpty)
        }
    }
}
