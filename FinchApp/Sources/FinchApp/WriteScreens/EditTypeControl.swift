import SwiftUI

/// The Edit sheet's top type control — the Add sheet's icon-segment language,
/// but with per-segment enable/disable (a system segmented Picker can't
/// disable individual segments, and Edit must show Transfer as present-but-
/// locked for line items). Selection highlight = soft neutral pill; selected
/// glyph tints accent; disabled glyphs dim.
struct EditTypeControl: View {
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

    private let width: CGFloat = 190   // matches AddTransactionSheet.typeControlWidth
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
    }

    private func color(for k: Kind) -> Color {
        if k == selected { return .accentColor }
        return enabled.contains(k) ? .primary : Color.secondary.opacity(0.4)
    }
}
