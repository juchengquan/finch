#if os(iOS)
import UIKit
import SwiftUI
import FinchCore

/// Presents the hand-entered rate sheet (`ManualRateSheet`, SwiftUI) from the
/// converted FX screens. A presented sheet, so it never shadows (see TagsVC).
extension UIViewController {
    func presentManualRateSheet(currency: String? = nil, editing: ExchangeRate? = nil) {
        present(UIHostingController(rootView: ManualRateSheet(currency: currency, editing: editing)
            .environmentObject(FinchStore.shared)
            .environmentObject(DeepLinkRouter.shared)
            .environmentObject(BiometricGate.shared)), animated: true)
    }

    /// The "+" both FX screens carry: add a rate by hand, optionally for one currency.
    func addRateBarButton(currency: String? = nil) -> UIBarButtonItem {
        let item = UIBarButtonItem(systemItem: .add, primaryAction: UIAction { [weak self] _ in
            self?.presentManualRateSheet(currency: currency)
        })
        item.accessibilityLabel = String(localized: "Add rate")
        return item
    }
}
#endif
