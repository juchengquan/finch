import XCTest
import UIKit
import FinchCore
@testable import FinchApp

/// The ledger screen's currency row sets the DISPLAY currency, and must say so.
/// It said "Base currency", which is the conversion a base change performs.
@MainActor
final class LedgerDetailLabelTests: XCTestCase {

    func test_theCurrencyRowIsLabelledDisplayCurrency() async throws {
        let packURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore.shared
        if store.accounts.isEmpty { try await store.loadPack(from: try Data(contentsOf: packURL)) }
        let ledger = try XCTUnwrap(store.ledgers.first)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let vc = LedgerDetailVC(ledgerId: ledger.id)
        window.rootViewController = UINavigationController(rootViewController: vc)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(300))
        vc.view.layoutIfNeeded()

        let cv = try XCTUnwrap(vc.view.subviews.compactMap { $0 as? UICollectionView }.first)
        let labels = cv.visibleCells.compactMap {
            (($0 as? UICollectionViewListCell)?.contentConfiguration as? UIListContentConfiguration)?.text
        }
        XCTAssertTrue(labels.contains(String(localized: "Display currency")), "\(labels)")
        XCTAssertFalse(labels.contains(String(localized: "Base currency")), "\(labels)")
    }
}
