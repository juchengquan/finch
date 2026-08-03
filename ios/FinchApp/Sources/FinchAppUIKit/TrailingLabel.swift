#if os(iOS)
import UIKit

/// Installs a read-only trailing text accessory on a list cell — and, crucially,
/// REUSES it, for the same reason `ToggleAccessory` does.
///
/// WHY THIS EXISTS. A cell that carries BOTH a value label and a switch (Currencies'
/// rate + tracking switch, Rules' match count + active switch) has to update the
/// label on every reconfigure. The obvious way is to rebuild the accessory array:
///
///     cell.accessories = [.customView(configuration: .init(customView: rate, …))]
///     ToggleAccessory.install(on: cell, …)
///
/// That assignment removes the previously-installed switch from the hierarchy, so
/// `ToggleAccessory`'s `viewWithTag` lookup misses and it builds a NEW `UISwitch` —
/// which is exactly the pattern `ToggleAccessory`'s header documents as destroying
/// iOS 26's glass treatment and swallowing taps. Both screens had it, and on
/// Currencies it fired on every snapshot: `applySnapshot()` reconfigures every
/// carried row, so the switch the user was mid-way through sliding was torn down and
/// replaced by one hard-set with `animated: false`, cutting the thumb animation.
///
/// So the label is created once and then left alone: only its text/colour change, and
/// `cell.accessories` is touched only when there is no label yet. A nil `text` hides
/// the label in place rather than removing the accessory — removing it would mean
/// reassigning `cell.accessories` again, reintroducing the very fault this avoids.
/// A hidden, empty label has zero intrinsic width and sits inboard of the switch, so
/// it costs no visible space.
enum TrailingLabel {

    /// Tag used to find an already-installed label on a reused cell. One past
    /// `ToggleAccessory.tag` so the two never collide.
    static let tag = 0x5714

    /// Call INSTEAD of building a label by hand. Safe to call on every configure.
    /// Pass `text: nil` for "no value right now" — the accessory stays, hidden.
    static func install(on cell: UICollectionViewListCell,
                        text: String?,
                        font: UIFont = .preferredFont(forTextStyle: .body),
                        color: UIColor = .label,
                        accessibilityLabel: String? = nil) {
        if let existing = cell.viewWithTag(tag) as? UILabel {
            configure(existing, text: text, font: font, color: color,
                      accessibilityLabel: accessibilityLabel)
            return   // leave the accessory — and the view — untouched
        }
        let label = UILabel()
        label.tag = tag
        configure(label, text: text, font: font, color: color,
                  accessibilityLabel: accessibilityLabel)
        cell.accessories = cell.accessories
            + [.customView(configuration: .init(customView: label, placement: .trailing()))]
    }

    private static func configure(_ label: UILabel, text: String?, font: UIFont,
                                  color: UIColor, accessibilityLabel: String?) {
        label.text = text
        label.font = font
        label.textColor = color
        label.accessibilityLabel = accessibilityLabel
        label.isHidden = text == nil
    }

    /// True when this cell already carries a trailing label, so the caller knows not
    /// to wipe `cell.accessories`.
    static func isInstalled(on cell: UICollectionViewListCell) -> Bool {
        cell.viewWithTag(tag) is UILabel
    }
}
#endif
