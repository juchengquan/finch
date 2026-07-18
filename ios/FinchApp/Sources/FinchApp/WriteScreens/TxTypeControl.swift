import SwiftUI

/// The transaction-type switcher shared by the Add and Edit sheets' nav bars.
/// The whole control is one interactive Liquid Glass capsule (so it has the glass
/// rim + press reaction of the toolbar pods / tab bar), and the SELECTED segment
/// is a bright accent thumb that SLIDES between segments (matched-geometry). Tap a
/// segment or scrub-anywhere. `enabled` limits the kinds the user may switch TO
/// (empty → fully locked; Edit shows Transfer as present-but-locked for line items).
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

    @Namespace private var glassNS
    private let width: CGFloat = 190
    private let height: CGFloat = 34

    var body: some View {
        let seg = width / CGFloat(Kind.allCases.count)
        HStack(spacing: 0) {
            ForEach(Kind.allCases) { k in
                ZStack {
                    if k == selected {
                        // `.tint` (not Color.accentColor) so the thumb blue matches
                        // the app's other interactive blues (USD picker, checkmarks,
                        // links, tab-bar selection), which all use the tint.
                        Capsule().fill(.tint)
                            .padding(2)
                            .matchedGeometryEffect(id: "txTypeThumb", in: glassNS)
                    }
                    Image(systemName: k.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color(for: k))
                }
                .frame(width: seg, height: height)
                .contentShape(Rectangle())
                .onTapGesture { pick(k) }
                .accessibilityLabel(k.label)
                .accessibilityAddTraits(k == selected ? .isSelected : [])
            }
        }
        .frame(width: width, height: height)
        .glassCapsule()
        .animation(.snappy(duration: 0.3), value: selected)
        #if os(iOS)
        // Scrub-anywhere: drag picks whichever segment is under the finger.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).onChanged { v in
                let all = Kind.allCases
                let idx = max(0, min(all.count - 1, Int(v.location.x / seg)))
                pick(all[idx])
            }
        )
        #endif
    }

    private func pick(_ k: Kind) {
        guard k != selected, enabled.contains(k) else { return }
        withAnimation(.snappy(duration: 0.3)) { onSelect(k) }
    }

    private func color(for k: Kind) -> Color {
        if k == selected { return .white }
        return enabled.contains(k) ? .primary : Color.secondary.opacity(0.4)
    }
}

private extension View {
    /// The control itself as an interactive Liquid Glass capsule on OS 26+ (glass
    /// rim + press reaction, like the ✕/✓ pods); a soft material capsule before.
    @ViewBuilder func glassCapsule() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self.background(Capsule().fill(.thinMaterial))
        }
    }
}
