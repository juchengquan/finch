import SwiftUI

/// Transaction-type switcher shared by the Add + Edit sheets' nav bars. Models
/// the app's bottom tab bar: the SELECTED segment is a tinted "crystal" Liquid
/// Glass capsule (`glassEffect` + tint — a translucent frosted pill, not a solid
/// color chip) that SLIDES between segments (matched-geometry), over a subtle
/// material track. `enabled` limits the kinds the user may switch TO (empty →
/// fully locked; Edit shows Transfer as present-but-locked for line items). Tap a
/// segment or scrub-anywhere.
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
                        selectedThumb
                            .matchedGeometryEffect(id: "txTypeThumb", in: glassNS)
                    }
                    Image(systemName: k.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(iconStyle(for: k))
                }
                .frame(width: seg, height: height)
                .contentShape(Rectangle())
                .onTapGesture { pick(k) }
                .accessibilityLabel(k.label)
                .accessibilityAddTraits(k == selected ? .isSelected : [])
            }
        }
        .frame(width: width, height: height)
        .background(Capsule().fill(.quaternary))
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

    /// The focused item: a NEUTRAL (clear) "crystal" Liquid Glass capsule on
    /// OS 26+ — exactly the bottom tab bar's selection (frosted glass is the pill;
    /// the colour lives on the glyph, not the glass). A soft fill before.
    @ViewBuilder private var selectedThumb: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(2)
        } else {
            Capsule().fill(Color.primary.opacity(0.12)).padding(2)
        }
    }

    private func pick(_ k: Kind) {
        guard k != selected, enabled.contains(k) else { return }
        withAnimation(.snappy(duration: 0.3)) { onSelect(k) }
    }

    /// Selected glyph in the accent tint (like the tab bar's selected item);
    /// others primary, disabled dimmed.
    private func iconStyle(for k: Kind) -> AnyShapeStyle {
        if k == selected { return AnyShapeStyle(.tint) }
        return AnyShapeStyle(enabled.contains(k) ? Color.primary : Color.secondary.opacity(0.4))
    }
}
