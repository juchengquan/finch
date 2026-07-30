#if os(iOS)
import UIKit

/// Installs the trailing `UISwitch` on a list cell — and, crucially, REUSES it.
///
/// WHY THIS EXISTS. The obvious implementation builds a fresh `UISwitch` in the cell
/// registration and assigns `cell.accessories` each time. That is wrong twice over,
/// and both faults were found on a device rather than here:
///
///   1. **It destroys iOS 26's glass treatment.** `applySnapshot()` reconfigures
///      every carried-over row, so the first snapshot after load rebuilt every
///      switch on the screen and they all went flat — permanently. It looked like
///      some screens "didn't have glass" and others did; really it was screens whose
///      observers fire early, reconfiguring immediately. Toggling one row made all
///      the others go flat, which is what gave it away.
///   2. **It swallows taps.** A switch replaced out from under a touch never
///      completes its gesture: a tap did nothing while a slower drag still worked.
///      That was initially blamed on the automation tool. It was not the tool.
///
/// So the switch is created once and then left alone. Only `isOn` and the action are
/// updated, and `cell.accessories` is reassigned only when there is no switch yet.
enum ToggleAccessory {

    /// Tag used to find an already-installed switch on a reused cell.
    static let tag = 0x5713
    private static let actionID = UIAction.Identifier("finch.toggle.valueChanged")

    /// Call INSTEAD of building a switch by hand. Safe to call on every configure.
    static func install(on cell: UICollectionViewListCell,
                        isOn: Bool,
                        accessibilityLabel: String? = nil,
                        onChange: @escaping (Bool) -> Void) {
        if let existing = cell.viewWithTag(tag) as? UISwitch {
            configure(existing, isOn: isOn, accessibilityLabel: accessibilityLabel, onChange: onChange)
            return   // leave the accessory — and the view — untouched
        }
        let toggle = UISwitch()
        toggle.tag = tag
        configure(toggle, isOn: isOn, accessibilityLabel: accessibilityLabel, onChange: onChange)
        cell.accessories = cell.accessories
            + [.customView(configuration: .init(customView: toggle, placement: .trailing()))]
    }

    private static func configure(_ toggle: UISwitch, isOn: Bool,
                                  accessibilityLabel: String?,
                                  onChange: @escaping (Bool) -> Void) {
        toggle.accessibilityLabel = accessibilityLabel
        // Only touch `isOn` when it actually differs — assigning it mid-interaction
        // is another way to interrupt the control.
        if toggle.isOn != isOn { toggle.setOn(isOn, animated: false) }
        // The closure captures row-specific state, and a reused cell may now be
        // showing a DIFFERENT row, so the old action must go. Removing by identifier
        // because `removeTarget` does not remove `UIAction`-based handlers.
        toggle.removeAction(identifiedBy: actionID, for: .valueChanged)
        toggle.addAction(UIAction(identifier: actionID) { [weak toggle] _ in
            onChange(toggle?.isOn ?? false)
        }, for: .valueChanged)
    }

    /// True when this cell already carries a switch, so the caller knows not to wipe
    /// `cell.accessories` — clearing them removes the switch from the hierarchy and
    /// reintroduces both faults above.
    static func isInstalled(on cell: UICollectionViewListCell) -> Bool {
        cell.viewWithTag(tag) is UISwitch
    }
}
#endif
