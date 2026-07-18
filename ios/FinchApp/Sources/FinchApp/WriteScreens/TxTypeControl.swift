import SwiftUI

/// The transaction-type switcher shared by the Add and Edit sheets' nav bars.
/// Modeled on the app's bottom tab bar: the SELECTED segment sits in a real
/// Liquid Glass capsule (`glassEffect`) that SLIDES between segments on change
/// (matched-geometry morph) — so it reads as glass in light mode too, not just a
/// flat pill. `enabled` limits the kinds the user may switch TO (empty → fully
/// locked; Edit shows Transfer as present-but-locked for line items). Tap a
/// segment, or scrub-anywhere on iOS.
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
                        selectionThumb
                            .matchedGeometryEffect(id: "txTypeThumb", in: glassNS)
                    }
                    Image(systemName: k.iconName)
                        .font(.system(size: 15, weight: .medium))
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
        .background(track)
        // Slide the glass thumb whenever selection changes — including when a page
        // swipe in the Add sheet drives `kind` externally, not just tap/scrub.
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

    /// The sliding selected pill — a real glass capsule on OS 26+, a soft fill
    /// before (those toolbars have no glass anyway).
    @ViewBuilder private var selectionThumb: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(2)
        } else {
            Capsule().fill(Color.primary.opacity(0.14)).padding(2)
        }
    }

    /// The control's own capsule background (the "track" the thumb slides in),
    /// so the whole control reads as a pill like the tab bar.
    private var track: some View {
        Capsule().fill(Color.primary.opacity(0.05))
    }

    private func color(for k: Kind) -> Color {
        if k == selected { return .accentColor }
        return enabled.contains(k) ? .primary : Color.secondary.opacity(0.4)
    }
}
