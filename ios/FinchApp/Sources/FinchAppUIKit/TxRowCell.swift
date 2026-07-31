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
                          onPreviewReceipt: ((Tx) -> Void)? = nil) {
        cell.contentConfiguration = UIHostingConfiguration {
            TxRow(txn: tx,
                  onPreviewReceipt: onPreviewReceipt,
                  showDate: showDate,
                  showRunningBalance: showRunningBalance)
                .environmentObject(store)
        }
        // `UIHostingConfiguration`'s default margins are considerably larger than a
        // SwiftUI `List` row's, which would leave the row tall even with the right
        // content in it. Tuned against the measured 52.0pt reference.
        .margins(.vertical, 7)
    }

    /// The rows that should print their own date.
    ///
    /// A row shows its date only when it differs from the row above, so a run of
    /// same-day transactions prints the date once. Pending rows always show it —
    /// they sit in their own bucket, with no day-de-dup context around them. Mirrors
    /// `ActivityTab.dateShownIds`; kept here so the two cannot drift.
    static func dateShownIDs(pending: [Tx], ordered: [Tx]) -> Set<String> {
        var shown = Set(pending.map(\.id))
        var last: String?
        for tx in ordered where tx.date != last {
            shown.insert(tx.id)
            last = tx.date
        }
        return shown
    }
}
#endif
