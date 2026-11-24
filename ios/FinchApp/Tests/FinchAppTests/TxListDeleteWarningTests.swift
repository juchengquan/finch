import XCTest
import FinchCore
@testable import FinchApp

/// Deleting one row deletes its whole entry. The merchant, tag and category lists
/// asked "Delete transaction?" with only the row, so a split purchase's other
/// payments, or a transfer's other side, went with it unannounced.
@MainActor
final class TxListDeleteWarningTests: XCTestCase {

    func test_theListsWarnThatTheOtherLegsGoToo() async throws {
        let packURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore.shared
        if store.accounts.isEmpty { try await store.loadPack(from: try Data(contentsOf: packURL)) }
        let category = try XCTUnwrap(store.categories.first)
        let plain = try XCTUnwrap(store.txns.first { $0.transferGroupId == nil })
        var split = plain; split.accountLegCount = 2
        var transfer = plain; transfer.transferGroupId = "g1"; transfer.accountLegCount = 2

        let vc = TxListDetailVC(.category(category))
        XCTAssertEqual(vc.deleteAlert(split).message?.hasSuffix(ActivityFeedView.multiLegDeleteHint), true)
        XCTAssertEqual(vc.deleteAlert(transfer).message?.hasSuffix(ActivityFeedView.transferDeleteHint), true)
        let message = try XCTUnwrap(vc.deleteAlert(plain).message)
        XCTAssertFalse(message.contains(ActivityFeedView.multiLegDeleteHint) || message.contains(ActivityFeedView.transferDeleteHint))
    }
}
