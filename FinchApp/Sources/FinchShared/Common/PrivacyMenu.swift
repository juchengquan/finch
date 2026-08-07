#if canImport(UIKit)
import UIKit

/// The privacy toggle as a menu item, built in ONE place.
///
/// Four screens show this on a long-press of their ledger button. Built here so
/// they cannot drift on the title, the checkmark or the behaviour — the item is
/// invisible until someone holds a button they have only ever tapped, so a
/// discrepancy between screens is not something anyone would report.
@MainActor
public enum PrivacyMenu {

    /// Reuses `"Hide Amounts"`, the string the macOS menu command already uses
    /// and the catalog already translates. A new key would cost an export round
    /// and a catalog commit for a phrase that already exists.
    public static func action(store: FinchStore) -> UIAction {
        let action = UIAction(title: String(localized: "Hide Amounts"),
                              image: UIImage(systemName: "eye.slash")) { _ in
            MainActor.assumeIsolated { store.privacyMode.toggle() }
        }
        // The checkmark is what lets a HIDDEN control be read rather than only
        // fired: hold the button and the menu says whether amounts are masked.
        action.state = store.privacyMode ? .on : .off
        return action
    }

    public static func menu(store: FinchStore) -> UIMenu {
        UIMenu(children: [action(store: store)])
    }
}
#endif
