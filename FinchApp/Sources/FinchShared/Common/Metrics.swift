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
}
