#if os(iOS)
import UIKit
import SwiftUI
import Combine

/// The launch-window stand-in for an empty transaction list.
///
/// `FinchStore` defers the txns projection off the first-paint path, so for ~600ms at
/// scale every txn-backed list is *legitimately* empty. Rendering the normal empty
/// state there asserts something false — "No transactions" on a ledger holding
/// thousands — and then flips a moment later. The SwiftUI screens spin instead; these
/// are their UIKit counterparts.
///
/// This is not a theoretical window. `RootTabBarController`'s `nativeRoute` pushes
/// `AccountDetailVC` / `ActivityFeedVC` / `BudgetDetailVC` straight from a deep link,
/// so a widget tap, Spotlight hit or notification at cold launch lands on one of these
/// screens *before* the projection has landed.
///
/// **Only for the unfiltered case.** Under an active search "No matching transactions"
/// is true whether or not the projection is in flight, and spinning there would hide a
/// real answer.
@MainActor
enum TxnsLoadingCell {

    /// True when an empty list means "still projecting" rather than "nothing here".
    static func shouldSpin(_ store: FinchStore, searchQuery: String = "") -> Bool {
        !store.txnsReady && searchQuery.isEmpty
    }

    /// Render a list cell as a centred spinner.
    ///
    /// Hosted because `ProgressView` is a leaf with no environment dependency, and it
    /// keeps the indicator identical to the one the SwiftUI screens show — the two
    /// appear on adjacent screens in the same app, so a `UIActivityIndicatorView` here
    /// would read as a different kind of loading.
    static func configure(_ cell: UICollectionViewListCell) {
        cell.contentConfiguration = UIHostingConfiguration {
            HStack { Spacer(); ProgressView(); Spacer() }
        }
        cell.accessories = []
    }

    /// Re-render when the deferred projection lands.
    ///
    /// Subscribing to `$txns` alone is NOT enough. On an genuinely empty ledger the
    /// txns list goes from `[]` to `[]`, so a snapshot driven by that publisher
    /// re-applies while `txnsReady` is still false — `reprojectActiveLedger` publishes
    /// `txns` first and calls `markTxnsReady()` after — and the spinner would never
    /// stop. This publisher is what actually clears it.
    static func observe(_ store: FinchStore, onChange: @escaping () -> Void) -> AnyCancellable {
        store.$txnsReady
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { _ in onChange() }
    }
}
#endif
