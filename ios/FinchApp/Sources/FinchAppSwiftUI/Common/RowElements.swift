import SwiftUI

/// Shared trailing elements for the Settings list rows (Tags, Categories,
/// Merchants). One definition so the three lists stay pixel-identical instead
/// of three hand-copied lookalikes.

/// The "N transactions" count capsule. Always shown, including 0 — a row with
/// no transactions reads as an explicit "0" rather than a blank the eye has to
/// interpret, and the pills stay aligned down the column.
struct CountPill: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel("\(count) transactions")
    }
}

/// The expand/collapse toggle glyph for rows with children (Categories).
/// Deliberately the ONLY chevron on these lists — a chevron always means
/// "has children, expands"; rows without one still navigate on tap. The
/// fixed 22×30 frame doubles as the tap target. `slot` is the matching
/// invisible spacer childless rows reserve so trailing edges stay aligned.
struct ExpandChevron: View {
    let expanded: Bool
    var body: some View {
        Image(systemName: expanded ? "chevron.down" : "chevron.right")
            .font(.caption).foregroundStyle(.secondary)
            .frame(width: 22, height: 30).contentShape(Rectangle())
    }

    static var slot: some View { Color.clear.frame(width: 22, height: 30) }
}
