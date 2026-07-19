import SwiftUI
import FinchCore

/// The tag field on the Add/Edit forms: a single labeled row ("Tags") whose
/// value shows the SELECTED tags as colored chips that WRAP across as many rows
/// as needed (via the custom `FlowLayout`) — the row grows vertically to hold
/// them all, no "+N" cap. "None" when nothing is selected. Tapping anywhere
/// opens the full-height multi-select bottom sheet (Confirm/Cancel).
struct TagField: View {
    let tags: [TagRow]
    @Binding var selected: Set<String>
    @State private var presented = false

    /// Selected tags in `tags` order (unknown ids ignored). Pure — unit-tested.
    static func selectedRows(tags: [TagRow], selected: Set<String>) -> [TagRow] {
        tags.filter { selected.contains($0.id) }
    }

    var body: some View {
        let chosen = Self.selectedRows(tags: tags, selected: selected)
        Button { presented = true } label: {
            HStack(alignment: .top, spacing: 12) {
                Text("Tags").foregroundStyle(.primary)
                if chosen.isEmpty {
                    Spacer()
                    Text("None").foregroundStyle(.secondary)
                } else {
                    // Chips fill the space to the right of the label and wrap;
                    // the row height follows the number of selected tags.
                    FlowLayout(spacing: 8, rowSpacing: 8) {
                        ForEach(chosen) { tag in chip(tag.name, tint: Color(hex: tag.color ?? "") ?? .accentColor) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
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
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button { selected = staged; dismiss() } label: { Image(systemName: "checkmark") }.accessibilityLabel("Confirm").confirmCheckmarkStyle()
                }
            }
        }
    }
}
