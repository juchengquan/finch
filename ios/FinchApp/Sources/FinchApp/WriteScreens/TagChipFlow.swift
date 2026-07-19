import SwiftUI
import FinchCore

/// The tag field on the Add/Edit forms: shows the SELECTED tags as wrapping
/// colored chips (display only), and opens a full-height multi-select bottom
/// sheet to edit the selection (Confirm/Cancel). Chips are capped for display
/// with a "+N" overflow so a heavily-tagged transaction stays compact.
struct TagField: View {
    let tags: [TagRow]
    @Binding var selected: Set<String>
    var displayCap: Int = 8
    @State private var presented = false

    /// Selected tags (in `tags` order) to render as chips, plus how many are
    /// hidden past the display cap. Pure — unit-tested.
    static func displayChips(tags: [TagRow], selected: Set<String>, cap: Int) -> (shown: [TagRow], overflow: Int) {
        let chosen = tags.filter { selected.contains($0.id) }
        if chosen.count <= cap { return (chosen, 0) }
        return (Array(chosen.prefix(cap)), chosen.count - cap)
    }

    var body: some View {
        let d = Self.displayChips(tags: tags, selected: selected, cap: displayCap)
        Button { presented = true } label: {
            if d.shown.isEmpty {
                HStack {
                    Text("Add tags").foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            } else {
                FlowLayout(spacing: 8, rowSpacing: 8) {
                    ForEach(d.shown) { tag in chip(tag.name, tint: Color(hex: tag.color ?? "") ?? .accentColor) }
                    if d.overflow > 0 { chip("+\(d.overflow)", tint: .secondary) }
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $presented) {
            TagPickerSheet(tags: tags, selected: $selected)
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
        }
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text).font(.callout)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.4)))
    }
}

/// The multi-select tag sheet: toggle any tags, then Confirm to apply (Cancel
/// discards). Searchable for large tag sets. List-only — tag creation stays in
/// the tag admin screen.
private struct TagPickerSheet: View {
    let tags: [TagRow]
    @Binding var selected: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var staged: Set<String>

    init(tags: [TagRow], selected: Binding<Set<String>>) {
        self.tags = tags
        self._selected = selected
        self._staged = State(initialValue: selected.wrappedValue)
    }

    private var filtered: [TagRow] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? tags : tags.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { tag in
                Button {
                    if staged.contains(tag.id) { staged.remove(tag.id) } else { staged.insert(tag.id) }
                } label: {
                    HStack {
                        Circle().fill(Color(hex: tag.color ?? "") ?? .accentColor).frame(width: 10, height: 10)
                        Text(tag.name).foregroundStyle(.primary)
                        Spacer()
                        if staged.contains(tag.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $query)
            .navigationTitle("Tags")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { selected = staged; dismiss() }.bold()
                }
            }
        }
    }
}
