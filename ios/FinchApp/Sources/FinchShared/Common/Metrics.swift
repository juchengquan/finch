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

    /// Gap between sections in the add/edit sheet family only — applied by
    /// `finchSheetForm()`.
    ///
    /// SEPARATE from `sectionSpacing` on purpose: that one is set once at
    /// `AdaptiveShell` and inherited by every `List` in every tab, so tightening
    /// the sheets through it would tighten the Accounts groups, Budgets and the
    /// rest along with them. These sheets are dense forms of short rows; the
    /// browse screens are not.
    static let sheetSectionSpacing: CGFloat = 6

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

    /// Height of the kind/type stripe at a row's trailing edge, beside the amount —
    /// `TxRow` in every transaction list, and `ScheduledRow`, which mirrors it.
    ///
    /// It is a fixed height because a SwiftUI shape is infinitely flexible: given only
    /// `.frame(width: 3)` the rectangle fills whatever the tallest sibling is, which
    /// measured 38pt — the full height of the row's text block. At that length, sitting
    /// at the trailing edge, it read as a rule between rows rather than a marker on the
    /// amount. 26pt stops clearly short of the text.
    ///
    /// Both rows read this ONE value on purpose. They were deliberately matched when
    /// the stripe moved to the trailing edge ("mirrors TxRow's move so the two lists
    /// still scan alike"), and two literals would let that drift silently.
    ///
    /// Deliberately not `@ScaledMetric`: nothing else in the app scales a metric that
    /// way, and at accessibility text sizes a marker that stays put while the row grows
    /// is the intended reading. Revisit if the rows start looking top-heavy there.
    static let kindStripeHeight: CGFloat = 26

    /// The type style for a row's trailing amount — `TxRow` in every transaction list,
    /// and `ScheduledRow`, which mirrors it.
    ///
    /// It was the inherited `.body`, which put it at the SAME size as the category name
    /// beside it and made the two compete for first glance. A transaction list is
    /// scanned by category as often as by figure, so the amount steps down one notch
    /// and the name leads. It keeps `.semibold` at the call sites — still the only
    /// weighted thing in the row, so it reads as a figure rather than more body text.
    ///
    /// Where it sits in the row's scale: category `.body` 17 → **amount 15** → date
    /// `.footnote` 13 → running balance `.caption2` 11.
    ///
    /// A semantic style, not a point size, so Dynamic Type still scales it. Both rows
    /// read this ONE value for the same reason they share `kindStripeHeight`: they are
    /// deliberately built to scan alike, and two literals is how that drifts.
    static let rowAmountFont: Font = .subheadline

    /// Minimum side of an interactive element, per Apple's HIG.
    ///
    /// Named as a FLOOR, not a size, because the pressure on it is always
    /// downward: `ios/CLAUDE.md` records shrinking Categories' expand chevron as
    /// one of two levers once considered for getting that row under 60pt (the
    /// swipe-action style boundary). It was already sub-44 at the time — 22×30 —
    /// which is what made missing it — and drilling into the category instead —
    /// the common failure. `ExpandChevronTapTargetTests` makes the floor a tripwire.
    static let tapTargetMin: CGFloat = 44

    /// Minimum row height of the add/edit sheet family — applied by
    /// `finchSheetForm()` via `defaultMinListRowHeight`, so every sheet moves
    /// together. The SYSTEM default in this form style is 52 (measured; row
    /// this floor lands the type caption and short-content rows at 48; rows
    /// whose content + the STYLE'S OWN padding exceed it sit at ~50.3.
    ///
    /// MEASURED DEAD ENDS (2026-08-08, three sim cycles) — do not retry:
    /// custom `listRowInsets` vertical values change NOTHING in this form
    /// style (rows identical at 0, 9, and default), with or without the
    /// floor; the style's vertical padding is fixed. This 48 keeps 4pt of
    /// margin above `tapTargetMin`; pushing real rows below ~50 would take
    /// negative-padding hacks, and row content wins over rendering details.
    static let sheetRowMinHeight: CGFloat = 48

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
