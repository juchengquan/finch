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
    /// side and the hosted cells apply it on the UIKit side, so a screen converted
    /// later inherits the spacing instead of re-deriving it.
    static let modePickerBottomGap: CGFloat = 4
}
