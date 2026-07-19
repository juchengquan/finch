import SwiftUI
import FinchCore

/// Multi-select tag picker rendered as wrapping toggle chips (replaces the
/// one-tag-per-row checklist). Selected chips fill in the tag's color; tapping
/// toggles. A "Show all (N)" / "Show less" control caps the collapsed height for
/// large tag sets — but every SELECTED tag is always visible (never hidden).
struct TagChipFlow: View {
    let tags: [TagRow]
    @Binding var selected: Set<String>
    var cap: Int = 10
    @State private var expanded = false

    /// Collapsed visible set: every selected tag, plus unselected tags in order
    /// up to `cap`, preserving original order and without duplicates.
    static func collapsedVisible(tags: [TagRow], selected: Set<String>, cap: Int) -> [TagRow] {
        var unselectedBudget = cap
        var out: [TagRow] = []
        for t in tags {
            if selected.contains(t.id) { out.append(t) }
            else if unselectedBudget > 0 { out.append(t); unselectedBudget -= 1 }
        }
        return out
    }

    private var visible: [TagRow] { expanded ? tags : Self.collapsedVisible(tags: tags, selected: selected, cap: cap) }
    private var hiddenCount: Int { tags.count - visible.count }

    var body: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            ForEach(visible) { tag in
                chip(tag)
            }
            if !expanded, hiddenCount > 0 {
                Button { expanded = true } label: { pill("Show all (\(tags.count))", filled: false, tint: .secondary) }
                    .buttonStyle(.plain)
            } else if expanded, tags.count > cap {
                Button { expanded = false } label: { pill("Show less", filled: false, tint: .secondary) }
                    .buttonStyle(.plain)
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private func chip(_ tag: TagRow) -> some View {
        let isOn = selected.contains(tag.id)
        let tint = Color(hex: tag.color ?? "") ?? .accentColor
        return Button {
            if isOn { selected.remove(tag.id) } else { selected.insert(tag.id) }
        } label: {
            pill(tag.name, filled: isOn, tint: tint)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func pill(_ text: String, filled: Bool, tint: Color) -> some View {
        Text(text)
            .font(.callout)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundStyle(filled ? Color.white : tint)
            .background(filled ? tint : tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(filled ? 0 : 0.4)))
    }
}
