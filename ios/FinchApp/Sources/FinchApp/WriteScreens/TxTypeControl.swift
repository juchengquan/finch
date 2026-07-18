import SwiftUI

/// The transaction-type switcher shared by the Add and Edit sheets' nav bars —
/// icon segments in a Liquid Glass capsule on iOS/macOS 26+ (so it matches the
/// ✕/✓ toolbar pods), bare segments on earlier systems (their toolbars have no
/// glass either). Tap a segment, or scrub-anywhere on iOS: the drag picks
/// whichever segment is under the finger from touch-down. `enabled` limits the
/// kinds the user may switch TO (empty → fully locked; Edit shows Transfer as
/// present-but-locked for line items). Selection highlight = soft neutral pill;
/// selected glyph tints accent; disabled glyphs dim.
struct TxTypeControl: View {
    /// Add-sheet kinds in Add-sheet order.
    enum Kind: String, CaseIterable, Identifiable {
        case expense, income, transfer, refund
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var iconName: String { TxnKindIcon.icon(for: rawValue) }
    }

    let selected: Kind
    /// Kinds the user may switch TO (empty → fully locked control).
    let enabled: Set<Kind>
    let onSelect: (Kind) -> Void

    private let width: CGFloat = 190
    private let height: CGFloat = 36

    var body: some View {
        let seg = width / CGFloat(Kind.allCases.count)
        HStack(spacing: 0) {
            ForEach(Kind.allCases) { k in
                Button { onSelect(k) } label: {
                    Image(systemName: k.iconName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(color(for: k))
                        .frame(width: seg, height: height)
                        .background(k == selected ? Color.primary.opacity(0.08) : Color.clear, in: Capsule())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(k == selected || !enabled.contains(k))
                .accessibilityLabel(k.label)
                .accessibilityAddTraits(k == selected ? .isSelected : [])
            }
        }
        .frame(width: width, height: height)
        .glassCapsule()
        #if os(iOS)
        // Scrub-anywhere (carried over from the Add sheet's segmented control):
        // simultaneous so plain taps still reach the segment buttons.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let all = Kind.allCases
                    let idx = max(0, min(all.count - 1, Int(v.location.x / seg)))
                    let k = all[idx]
                    if k != selected && enabled.contains(k) { onSelect(k) }
                }
        )
        #endif
    }

    private func color(for k: Kind) -> Color {
        if k == selected { return .accentColor }
        return enabled.contains(k) ? .primary : Color.secondary.opacity(0.4)
    }
}

private extension View {
    /// Liquid Glass capsule on OS 26+; unchanged (bare) rendering earlier.
    @ViewBuilder func glassCapsule() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self
        }
    }
}
