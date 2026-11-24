import XCTest
import FinchCore
@testable import FinchApp

/// `FinchStore.shared` on a fresh copy of the sample pack, for tests of screens
/// (which read the shared store).
///
/// Every store in the test process opens the same database file, and another
/// test's `loadPack` swaps that file out from under the shared store's open
/// connection: its next write fails with "disk I/O error". Loading the pack here
/// swaps it in for the shared store, which reopens its connection.
@MainActor
enum SharedStoreFixture {
    private final class Token {}

    static func load() async throws -> FinchStore {
        let packURL = try XCTUnwrap(Bundle(for: Token.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore.shared
        try await store.loadPack(from: try Data(contentsOf: packURL))
        return store
    }
}
