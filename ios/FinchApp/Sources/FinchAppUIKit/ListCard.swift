#if os(iOS)
import UIKit

/// The list card, drawn by US so its corner radius is ours to set.
///
/// **Why this exists.** The rounded card on a `.insetGrouped` list is not settable.
/// Established by experiment, not assumption: giving a cell's `UIBackgroundConfiguration`
/// a `cornerRadius` did nothing; giving it a garish colour AND a `cornerRadius` turned
/// the rows that colour while leaving the corners untouched; replacing the background
/// with a custom view carrying its own corners and per-row `maskedCorners` produced one
/// continuous section card at the system radius with no trace of the per-row shaping.
/// `.insetGrouped` clips whatever a cell draws to the shape it wants. The SDK confirms
/// there is no API for it — `UICollectionLayoutListConfiguration` exposes eleven
/// properties and none touch card geometry.
///
/// So a section that wants a different radius opts out to `.grouped`, which draws no
/// card, and uses the three pieces below. All three are needed together:
///
///  1. `listCardBackground` — the card itself, with the right corners rounded.
///  2. `listCardSeparators` — `.grouped` runs separators edge to edge otherwise.
///  3. `applyListCardInsets` — the inset from the screen edge.
///
/// **Insetting the SECTION, not the background, is deliberate.** An earlier version
/// inset only the background and left the cell's content — and its trailing accessory —
/// running to the screen edge, so the text overhung the card it was meant to sit in.
///
/// **Every cell in an opted-in section must use this, not just the interesting ones.**
/// A section is one card. Carding only the transaction rows left empty-state rows
/// ("No transactions", "No matching transactions") with no card at all, full-width and
/// square — twice, on two different screens, before it was caught by looking.
///
/// This is a background configuration rather than a wrapper around the row's content,
/// which an earlier version used. A background leaves the system's own row margins
/// alone, so row heights are unchanged and nothing has to be re-derived by hand; it
/// also works for rows built from `defaultContentConfiguration()`, which a SwiftUI
/// wrapper cannot touch.
///
/// **KNOWN ISSUE — swiped rows.** While a row is open for swipe actions its card
/// loses the inset and the corners, bleeding square to the screen edge. The swipe
/// container lays the cell out itself and does not honour the section's content
/// insets, and `.insetGrouped` used to clip the swipe state to the card shape for
/// free. Cosmetic and only visible mid-swipe, but it is the clearest running cost of
/// owning the card rather than borrowing the system's.
///
/// Sizes come from `Metrics.listCard*` so the look is tunable in one place.
func listCardBackground(isFirst: Bool, isLast: Bool) -> UIBackgroundConfiguration {
    var bg = UIBackgroundConfiguration.clear()
    let card = UIView()
    card.backgroundColor = .secondarySystemGroupedBackground
    card.layer.cornerRadius = Metrics.listCardCornerRadius
    card.layer.cornerCurve = .continuous
    let top: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    let bottom: CACornerMask = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    card.layer.maskedCorners = (isFirst && isLast) ? top.union(bottom)
        : isFirst ? top : isLast ? bottom : []
    bg.customView = card
    return bg
}

/// Separators pulled inside the card, and hidden on a section's LAST row.
///
/// Both halves matter. `.grouped` runs separators the full screen width, so without
/// the insets they cross the rounded corners; and unlike `.insetGrouped` it does not
/// drop the separator on the final row, so one was left cutting across the bottom of
/// every card.
///
/// A per-item handler rather than a plain `separatorConfiguration` because only the
/// handler is told which row it is being asked about.
func listCardSeparatorHandler(_ collectionView: @escaping () -> UICollectionView?)
    -> (IndexPath, UIListSeparatorConfiguration) -> UIListSeparatorConfiguration {
    { indexPath, proposed in
        var c = proposed
        c.topSeparatorVisibility = .hidden
        c.bottomSeparatorInsets = NSDirectionalEdgeInsets(
            top: 0, leading: Metrics.listCardInset * 2, bottom: 0, trailing: Metrics.listCardInset)
        if let cv = collectionView(),
           indexPath.item == cv.numberOfItems(inSection: indexPath.section) - 1 {
            c.bottomSeparatorVisibility = .hidden
        }
        return c
    }
}

/// The card's inset from the screen edge, applied to the whole section so content and
/// accessories move with it — matching where `.insetGrouped` puts the card on the
/// sections that kept it.
func applyListCardInsets(_ section: NSCollectionLayoutSection) {
    section.contentInsets.leading = Metrics.listCardInset
    section.contentInsets.trailing = Metrics.listCardInset
}
#endif
