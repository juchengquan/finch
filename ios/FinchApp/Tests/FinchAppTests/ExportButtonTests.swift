import XCTest
@testable import FinchApp
import FinchCore

/// Task 11 — export produces a valid, parseable pack stamped `device = "ios"`.
final class ExportButtonTests: XCTestCase {
    @MainActor
    func test_buildPackProducesValidBytes() async throws {
        let packURL = try XCTUnwrap(Bundle.module.url(
            forResource: "Fixtures/roundtrip/sample", withExtension: "finch"))
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: packURL))

        let exportedData = try await store.buildPack()
        let parsed = try Pack.parse(exportedData)
        XCTAssertEqual(parsed.manifest.packFormatVersion, "1")
        XCTAssertEqual(parsed.manifest.exportedFrom?.device, "ios")
    }
}
