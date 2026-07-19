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
            TagPickerSheet(selected: $selected)
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

/// The multi-select tag sheet: toggle tags, then Confirm to apply (Cancel
/// discards). Searchable; reads `store.tags` LIVE so a tag created mid-sheet
/// shows up at once. Like the Merchant picker, the search box doubles as tag
/// entry: typing a name with no match surfaces a "Create ‹text›" row that opens
/// the shared `TagEditSheet` (name prefilled + color). On save the new tag is
/// created and auto-selected. Rows share `TagSwatch` with the Settings Tags list.
private struct TagPickerSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Binding var selected: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var staged: Set<String>
    @State private var creating: NewTagName?     // non-nil → present the editor

    init(selected: Binding<Set<String>>) {
        self._selected = selected
        self._staged = State(initialValue: selected.wrappedValue)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var filtered: [TagRow] {
        trimmedQuery.isEmpty ? store.tags
            : store.tags.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }
    }
    /// Offer "Create ‹query›" only when the typed text isn't already a tag name.
    private var showCreate: Bool {
        !trimmedQuery.isEmpty
            && !store.tags.contains { $0.name.caseInsensitiveCompare(trimmedQuery) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List {
                if showCreate {
                    let name = trimmedQuery
                    CreateTagRow(name: name) { creating = NewTagName(name: name); query = "" }
                }
                ForEach(filtered) { tag in
                    Button {
                        if staged.contains(tag.id) { staged.remove(tag.id) } else { staged.insert(tag.id) }
                    } label: {
                        HStack(spacing: 10) {
                            TagSwatch(hex: tag.color)
                            Text(tag.name).foregroundStyle(.primary)
                            Spacer()
                            if staged.contains(tag.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $query, prompt: "Search or add")
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
            // "Create ‹x›" opens the full tag editor (name prefilled + color); the
            // new tag is created on its Save and auto-selected here.
            .sheet(item: $creating) { new in
                TagEditSheet(tag: nil, prefillName: new.name, onCreated: { id in staged.insert(id) })
                    #if os(iOS)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    #endif
            }
        }
    }
}

/// Identifies a pending "Create ‹name›" so it can drive `.sheet(item:)`.
private struct NewTagName: Identifiable { let id = UUID(); let name: String }

/// The "Create ‹name›" row. It lives in its own view so it can read the
/// `dismissSearch` action — only available *inside* the `.searchable` scope (a
/// descendant of the modified List). Tapping it collapses the search field
/// (so the toolbar ✓ Confirm returns) and opens the tag editor.
private struct CreateTagRow: View {
    let name: String
    let onCreate: () -> Void
    @Environment(\.dismissSearch) private var dismissSearch

    var body: some View {
        Button {
            dismissSearch()
            onCreate()
        } label: {
            Label("Create “\(name)”", systemImage: "plus.circle").foregroundStyle(.tint)
        }
    }
}
