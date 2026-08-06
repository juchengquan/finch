#if os(iOS)
import UIKit
import SwiftUI
import FinchCore

/// The transaction row — **hosted, not rebuilt**.
///
/// Phase 2 rendered these with `cell.defaultContentConfiguration()`: category as the
/// title, `tx.date` as the subtitle, amount as a trailing accessory. That is Apple's
/// generic two-line subtitle cell, and measuring it against the screen it replaced
/// showed **72.3pt vs 52.0pt — 39% taller on every row** (recorded in
/// `simulator-ui-driving.md`).
///
/// Height was the visible symptom; the substitution had quietly dropped more than
/// that. `TxRow` also renders the kind stripe (expense red / income green / refund
/// purple / transfer blue), the pending clock, the anomaly warning, tag chips with a
/// `ViewThatFits` 3→2→1 cascade, the note, the running-balance column, and dates
/// through `relativeOrShort` — which honours the `finch.feed.relativeDates` preference
/// the Appearance screen exposes. The generic cell showed a raw `2026-07-29` and
/// ignored that toggle entirely.
///
/// **Why hosting is the right answer rather than a UIKit reimplementation.** `TxRow`
/// is a leaf — `HStack`/`VStack`, no scroll view — and the migration's rule is that
/// hosting leaves is fine; it is hosting a screen's *scroll view* that brings the
/// iOS 26 resume shadow back (`ios26-shadow-variant-matrix.md`, reproducer B). The
/// `UICollectionView` is still the scroll view here. Rebuilding all of the above in
/// UIKit would be a few hundred lines that then drift from the SwiftUI original every
/// time a row gains a feature — and the Mac keeps rendering that original, so drift is
/// guaranteed, not hypothetical.

/// A transaction row's background, pinned so it does NOT follow the cell's
/// highlighted state.
///
/// A list cell's default background paints grey while highlighted. Tapping a swipe
/// action highlights the cell, and diffable MOVES that cell to its new index path
/// rather than re-dequeuing it — `prepareForReuse` never fires, so the highlight
/// arrives with the row and fades there. Clearing `isHighlighted` after the apply
/// treated the symptom and missed frames; a row that never paints a highlight has
/// nothing to leave behind.
///
/// Selection is left alone: these rows are only selectable in the split shell's
/// column mode, where `onSelect` is non-nil, and that state still resolves normally.
func txRowBackground() -> UIBackgroundConfiguration {
    var bg = UIBackgroundConfiguration.listGroupedCell()
    bg.backgroundColor = .secondarySystemGroupedBackground
    bg.backgroundColorTransformer = nil
    return bg
}

enum TxRowCell {

    /// Configure a list cell as a transaction row.
    ///
    /// `store` is passed rather than read from `.shared` because hosting controllers
    /// inherit no environment — the trap that crashed `BackupSyncSettingsVC` in Phase 2.
    static func configure(_ cell: UICollectionViewListCell,
                          tx: Tx,
                          store: FinchStore,
                          showDate: Bool = true,
                          showRunningBalance: Bool = true,
                          onPreviewReceipt: ((Tx) -> Void)? = nil,
                          onToggleStatus: ((Tx) -> Void)? = nil) {
        cell.contentConfiguration = UIHostingConfiguration {
            TxRow(txn: tx,
                  onPreviewReceipt: onPreviewReceipt,
                  onToggleStatus: onToggleStatus,
                  showDate: showDate,
                  showRunningBalance: showRunningBalance)
                .environmentObject(store)
                // ONE VoiceOver element per row, and announced as a button.
                //
                // The SwiftUI screens wrap this row in a `Button`, which aggregates its
                // children — a row there reads as
                // "Expense, Groceries, Jul 30 · 12:00, −$58.20". Hosted in a cell it has
                // no such wrapper, so VoiceOver read the type, merchant, tags, date and
                // amount as five separate elements and never announced the row as
                // actionable. Measured against a control build: the converted feed
                // exposed 40 StaticTexts and ONE labelled control, the SwiftUI feed 15
                // elements of which every row was a Button.
                //
                // Combining hides any control INSIDE the row from VoiceOver, and since
                // the status glyph became tappable there now is one. It stays combined
                // anyway — one stop per row is what the measurement above bought — and
                // the glyph is re-exposed as a custom action below rather than as a
                // second stop on every row in the feed.
                //
                // (`onPreviewReceipt` is still not a control here: in a cell it is
                // invoked from the swipe/context actions, not from the row.)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                // The sighted affordance is a tap on the glyph; this is its equivalent.
                // Named for what the tap WILL do, not for the state the row is in.
                .accessibilityAction(named: Text(RowStatusStyle.actionTitle(pending: tx.pending == true))) {
                    onToggleStatus?(tx)
                }
        }
        // `UIHostingConfiguration`'s default margins are considerably larger than a
        // SwiftUI `List` row's, which would leave the row tall even with the right
        // content in it. Tuned against the measured 52.0pt reference.
        .margins(.vertical, 7)
    }

}
#endif
