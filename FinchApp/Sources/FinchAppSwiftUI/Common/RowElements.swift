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
/// "has children, expands"; rows without one still navigate on tap. `slot` is
/// the matching invisible spacer childless rows reserve so trailing edges stay
/// aligned.
///
/// **The tap box and the layout box are different on purpose.** The glyph accepts
/// touches across `Metrics.tapTargetMin` square but REPORTS only
/// `Metrics.expandChevronLayoutHeight` of height to the enclosing `HStack`, so
/// the 44pt box overflows the row by 7pt top and bottom instead of stretching it
/// from 60pt to ~74pt. The row's own tap drills into the category, so every point
/// this box doesn't cover is a point where a missed expand costs a push and a Back
/// — it was 22×30, roughly a third of the HIG minimum, before this.
struct ExpandChevron: View {
    let expanded: Bool
    var body: some View {
        Image(systemName: expanded ? "chevron.down" : "chevron.right")
            .font(.caption).foregroundStyle(.secondary)
            .frame(width: Metrics.tapTargetMin, height: Metrics.tapTargetMin)
            .contentShape(Rectangle())
            .frame(width: Metrics.tapTargetMin, height: Metrics.expandChevronLayoutHeight)
    }

    static var slot: some View {
        Color.clear.frame(width: Metrics.tapTargetMin, height: Metrics.expandChevronLayoutHeight)
    }
}

/// The drag grip shown at the trailing edge of a Categories row while reordering.
///
/// **Advertises the drag; does not implement it.** The lift is still SwiftUI's
/// `.draggable(_:)` on the whole row, so this is a plain `Image` with no gesture
/// of its own — anything interactive here would compete with the drag for the
/// press. Before it existed, reorder mode looked identical to normal mode apart
/// from the toolbar, and nothing on screen said the rows could be dragged.
///
/// Sized to `tapTargetMin` and height-clamped like `ExpandChevron` so it occupies
/// exactly the slot the count pill vacates, keeping the name column the same width
/// in both modes.
///
/// Hidden from VoiceOver: dragging has no VoiceOver equivalent here yet, so
/// exposing the grip would promise an interaction that cannot be performed.
struct ReorderGrip: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.caption).foregroundStyle(.tertiary)
            .frame(width: Metrics.tapTargetMin, height: Metrics.expandChevronLayoutHeight)
            .accessibilityHidden(true)
    }
}
