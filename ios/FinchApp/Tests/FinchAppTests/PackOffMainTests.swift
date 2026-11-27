import XCTest
import FinchCore
@testable import FinchApp

/// Import, export and every scheduled backup unzip, hash and zip the whole
/// database and its receipts. That work runs off the main actor now; only the
/// swap into the live database comes back to it.
@MainActor
final class PackOffMainTests: XCTestCase {

    private func samplePack() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        return try Data(contentsOf: url)
    }

    /// Staging touches nothing the store owns, so it can run on any thread.
    func test_stagingAPackRunsOffTheMainThread() async throws {
        let data = try samplePack()
        let (onMain, staged) = try await Task.detached {
            (Thread.isMainThread, try FinchStore.stage(data))
        }.value
        XCTAssertFalse(onMain)
        XCTAssertTrue(staged.problems.isEmpty, "\(staged.problems)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.dbPath.path))
    }

    /// Every export cloned the whole database into the temp folder and left it
    /// there — one more full copy per scheduled backup.
    func test_anExportLeavesNoCloneBehind() async throws {
        let store = try await SharedStoreFixture.load()
        let tmp = FileManager.default.temporaryDirectory
        func clones() throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: tmp.path).filter { $0.hasPrefix("export-") }
        }
        let before = Set(try clones())
        let bytes = try await store.buildPack()
        XCTAssertEqual(Set(try clones()).subtracting(before), [])

        // And the pack is still a whole one: it imports cleanly.
        try await store.loadPack(from: bytes)
        XCTAssertFalse(store.accounts.isEmpty)
    }
}
