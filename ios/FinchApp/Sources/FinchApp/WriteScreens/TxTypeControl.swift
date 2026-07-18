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

    /// The focused item: a raised frosted "crystal" pill (the bottom tab bar's
    /// selection look). A neutral Liquid Glass capsule alone is invisible over
    /// the white form (glass is translucent — nothing to refract), so the pill is
    /// a bright frosted material with a soft shadow for elevation/contrast, and
    /// the colour lives on the glyph, not the glass.
    @ViewBuilder private var selectedThumb: some View {
        Capsule()
            .fill(.regularMaterial)
            .shadow(color: .black.opacity(0.16), radius: 2.5, y: 0.5)
            .padding(2)
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
