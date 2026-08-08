import SwiftUI

/// The transaction-style **type control**, shared by `AddTransactionSheet`,
/// `EditTransactionSheet`, and `ScheduledSheet` so the pattern lives once instead
/// of being hand-rolled per sheet.
///
/// Two pieces:
/// - a `.principal` toolbar segmented Picker of type icons (the system's crystal
///   Liquid Glass selection — a custom View can't reproduce it), either editable
///   (`segmented`) or a single disabled segment for an immutable type (`locked`);
/// - a centered `caption` row that names the current type under the control.
///
/// Generic over each screen's own kind enum via `icon`/`label` closures — the
/// enums differ (`AddTransactionSheet.Kind` maps `adjust`→the "adjustment" icon,
/// so it supplies its own `iconName`), so the mapping is passed in, not assumed.
enum TxnTypeToolbar {
    /// Editable N-segment glass picker, sized to the segment count (50pt each,
    /// matching the hand-rolled widths the three sheets used before). For the Add
    /// path and reclassify-on-edit.
    static func segmented<K: Hashable & Identifiable>(
        _ kinds: [K], selection: Binding<K>,
        icon: @escaping (K) -> String, label: @escaping (K) -> String
    ) -> some View {
        Picker("Type", selection: selection) {
            ForEach(kinds) { k in
                Image(systemName: icon(k)).accessibilityLabel(label(k)).tag(k)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: CGFloat(kinds.count) * 50)
    }

    /// A single disabled segment showing one icon — for an immutable type
    /// (Edit Scheduled, or a transfer on Edit Transaction).
    static func locked(icon: String, label: String) -> some View {
        Picker("Type", selection: .constant(0)) {
            Image(systemName: icon).accessibilityLabel(label).tag(0)
        }
        .pickerStyle(.segmented)
        .frame(width: 52)
        .disabled(true)
    }

    /// The centered caption naming the current type — used as the content of the
    /// first `Form` section, directly under the toolbar control.
    static func caption(_ label: String) -> some View {
        Text(label)
            // .title3, not .subheadline: the caption sits in a row pinned to
            // `sheetRowMinHeight` (48) that it cannot shrink — the floor is there
            // so TAPPABLE rows clear a finger, and this label is not one. A bigger
            // face fills more of the fixed box, so the air above and below it
            // halves without anything moving. Measured: row stays 48 at both sizes.
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowBackground(Color.clear)
            .listRowInsets(Metrics.captionInsets)
    }
}
