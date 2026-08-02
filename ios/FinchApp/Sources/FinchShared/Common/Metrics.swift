import SwiftUI

/// App-wide layout metric tokens — tune here to adjust globally.
/// (Named `Metrics`, not `Layout`, to avoid colliding with SwiftUI's `Layout` protocol.)
enum Metrics {
    /// Gap between grouped `List` sections — the spacing between the sectionized
    /// blocks (e.g. the account groups on the Accounts page). Set once at
    /// `AdaptiveShell` via `.listSectionSpacing(...)`; because that's an
    /// environment value, every descendant `List` across all tabs inherits it.
    /// Individual screens may still override it locally (e.g. the Add sheet's 6).
    static let sectionSpacing: CGFloat = 12

    /// Top margin between a sheet's nav bar and its first section. Sheets do NOT
    /// agree on this by default — Budget/Scheduled/Account sit ~29pt lower than the
    /// transaction sheets — so `finchSheetForm()` pins it explicitly. 6 reproduces
    /// the transaction sheets' spacing (measured).
    static let sheetTopMargin: CGFloat = 6

    /// Extra gap ABOVE a `finchSectionHeader` title. This ADDS to the inset the
    /// system already applies to a custom header view, so 0 reproduces today's
    /// rendering — dial up from here.
    static let headerTopPadding: CGFloat = 0
    /// Extra gap BELOW a `finchSectionHeader` title, added on top of the system's
    /// own spacing (see above).
    static let headerBottomPadding: CGFloat = 0
    /// Row insets for the type-caption row (`TxnTypeToolbar.caption`).
    static let captionInsets = EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)

    /// Gap below the Calendar/List mode picker, before the content it switches.
    ///
    /// One number because the three screens that carry the picker — Activity, the
    /// account page and Scheduled — each had it fixed separately and drifted apart
    /// (28 / 34 / different again). `ViewModePickerRow` applies it on the SwiftUI
    /// side; on the UIKit side each screen's layout provider applies it to the
    /// picker SECTION (`contentInsets.bottom`, with `.top = 0`), not just to the
    /// hosted cell's margins — an insetGrouped section pads itself on top of the
    /// inter-section spacing, and that padding was most of the gap. Measured on
    /// Activity: the following header sat at 297.7pt and now sits at 280.0pt.
    ///
    /// Tuning this alone moves things ~2pt; the section insets above are the lever.
    /// What remains below the picker is `sectionSpacing`, which every grouped list
    /// in the app shares — deliberately not narrowed to close the last few points.
    static let modePickerBottomGap: CGFloat = 4

    /// Minimum side of an interactive element, per Apple's HIG.
    ///
    /// Named as a FLOOR, not a size, because the pressure on it is always
    /// downward: `ios/CLAUDE.md` records shrinking Categories' expand chevron as
    /// one of two levers once considered for getting that row under 60pt (the
    /// swipe-action style boundary). It was already sub-44 at the time — 22×30 —
    /// which is what made missing it — and drilling into the category instead —
    /// the common failure. `ExpandChevronTapTargetTests` makes the floor a tripwire.
    static let tapTargetMin: CGFloat = 44

    // MARK: List cards
    //
    // The rounded card behind list rows. On screens still using UIKit's
    // `.insetGrouped` these are IGNORED — that appearance draws the card itself and
    // clips anything a cell draws to its own shape, so its radius (measured ~21pt)
    // cannot be overridden. These apply only where a screen has opted out via
    // `.grouped` and draws the card itself through `ListCard`.

    /// Corner radius of a list card. **The knob to turn.**
    ///
    /// Measured, not nominal: a `.continuous` corner reaches its straight edge before
    /// its nominal radius, so 10 here renders as ~7.3pt of arc against the system's
    /// ~21pt. Raise it toward 14 for something nearer half the system curve.
    static let listCardCornerRadius: CGFloat = 10

    /// The card's inset from the screen edge. 16 reproduces where `.insetGrouped`
    /// put it, so opted-out screens line up with the ones still using the system card.
    static let listCardInset: CGFloat = 16

    /// Inner padding, replacing the margins `UIHostingConfiguration` supplied before
    /// they were zeroed. Zeroing them is what lets rows in a section stack seamlessly;
    /// left in place, each card stops short of the cell edge and the section renders
    /// as separate lozenges. 7 is what keeps a transaction row at its documented 52pt.
    static let listCardContentPadding = EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16)

    /// Gap below the last row of a section, replacing `.insetGrouped`'s spacing.
    static let listCardSectionGap: CGFloat = 18

    /// Layout height the expand chevron REPORTS to its row, as distinct from the
    /// `tapTargetMin` box it actually accepts touches in.
    ///
    /// The two differ only on the SwiftUI side, where the chevron is a layout
    /// participant in the row's `HStack` and a 44pt-tall frame would push the row
    /// past 60pt. Clamping the reported height keeps iPad/macOS rows at the same
    /// 60pt as iPhone's while the 44×44 hit box overflows it by 7pt top and bottom.
    /// In UIKit the chevron is a cell accessory, not row content, so it takes the
    /// full 44 and nothing moves.
    static let expandChevronLayoutHeight: CGFloat = 30
}
