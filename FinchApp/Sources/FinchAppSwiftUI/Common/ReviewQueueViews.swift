import SwiftUI

/// The review queue's three leaf views, shared by both feeds — `ActivityFeedVC`
/// hosts them in cells, `ActivityFeedView` puts them straight in its `List`. The
/// rules behind them (what the queue holds, when "Mark all" asks) live in
/// `ReviewQueue`; these only draw.

/// The way in: a chip at the head of the saved-search row, carrying the queue's size.
/// Filled while the queue is open, so the same chip reads as "you are here" and
/// closes it again.
struct ReviewQueueChip: View {
    let count: Int
    let selected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "text.badge.checkmark").imageScale(.small)
            // The count is dropped once it reaches zero — "Needs review · 0" reads as
            // an instruction with nothing to do. The chip only shows at zero while the
            // queue is open, where it is the way back out.
            if count > 0 { Text("Needs review · \(count)") } else { Text("Needs review") }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: Capsule())
        .foregroundStyle(selected ? Color.white : Color.primary)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("reviewQueueChip")
    }
}

/// Above the queue's rows: how many there are under the current search and filters,
/// and the action that clears them all. The count is the WHOLE filtered queue, not
/// the 50-row page, because that is what the button acts on.
struct ReviewQueueBar: View {
    let count: Int
    let onMarkAll: () -> Void

    var body: some View {
        HStack {
            Text("\(count) to review")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Mark all reviewed", action: onMarkAll)
                .font(.subheadline.weight(.medium))
                .buttonStyle(.borderless)
                .accessibilityIdentifier("markAllReviewed")
        }
    }
}

/// The queue, cleared. `remainingElsewhere` is the WHOLE ledger's count: non-zero
/// means the search or filters hid the rest, which "All caught up" alone would
/// misstate.
struct ReviewQueueEmpty: View {
    let remainingElsewhere: Int

    var body: some View {
        ContentUnavailableView {
            Label("All caught up", systemImage: "checkmark.circle")
        } description: {
            if remainingElsewhere == 0 {
                Text("Every transaction has been reviewed.")
            } else {
                Text("Nothing here needs review. Clear the search or filters to see the other \(remainingElsewhere).")
            }
        }
        .accessibilityIdentifier("reviewQueueEmpty")
    }
}
