import XCTest
@testable import FinchApp
import FinchCore

/// DESIGN §4 — the import pipeline. `sample.finch` (CLEAN) is built from
/// SimulatorDemoSeed — seed a scratch DB, export via buildPack(), replace the
/// fixture — so the data these tests swap into a dev sim matches the demo the
/// app seeds itself. `dirty.finch` stays web-built (proves a web-exported pack
/// still hits the audit gate). Note: this drops the web-built CLEAN-import
/// proof — revisit at release if cross-platform pack interchange matters.
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
