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
/// discards). Searchable for large tag sets. Like the Merchant picker, the search
/// box doubles as tag entry: typing a name with no match surfaces a "Create ‹text›"
/// row that STAGES a new tag (shown as a pending chip). Pending tags are created
/// on Confirm only — Cancel discards them, nothing is written.
private struct TagPickerSheet: View {
    @EnvironmentObject private var store: FinchStore
    let tags: [TagRow]
    @Binding var selected: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var staged: Set<String>       // existing tag ids toggled on
    @State private var newNames: [String] = []    // pending new tag names (staged)

    init(tags: [TagRow], selected: Binding<Set<String>>) {
        self.tags = tags
        self._selected = selected
        self._staged = State(initialValue: selected.wrappedValue)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var filtered: [TagRow] {
        trimmedQuery.isEmpty ? tags : tags.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }
    }
    /// Offer "Create ‹query›" only when the typed text isn't already an existing
    /// tag name or a pending new one.
    private var showCreate: Bool {
        !trimmedQuery.isEmpty
            && !tags.contains { $0.name.caseInsensitiveCompare(trimmedQuery) == .orderedSame }
            && !newNames.contains { $0.caseInsensitiveCompare(trimmedQuery) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List {
                if showCreate {
                    let name = trimmedQuery
                    CreateTagRow(name: name) {
                        newNames.append(name)
                        query = ""
                    }
                }
                // Pending new tags (not yet written) — tap to unstage.
                ForEach(newNames, id: \.self) { name in
                    Button { newNames.removeAll { $0 == name } } label: {
                        HStack {
                            Circle().fill(Color.accentColor).frame(width: 10, height: 10)
                            Text(name).foregroundStyle(.primary)
                            Text("new").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                ForEach(filtered) { tag in
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
            }
            .searchable(text: $query, prompt: "Search or add")
            .navigationTitle("Tags")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button { confirm() } label: { Image(systemName: "checkmark") }.accessibilityLabel("Confirm").confirmCheckmarkStyle()
                }
            }
        }
    }

    /// Create each pending tag (client-generated id) and apply the full selection.
    /// A name that already exists (created meanwhile) reuses that tag's id.
    private func confirm() {
        var ids = staged
        for name in newNames {
            if let existing = store.tags.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                ids.insert(existing.id); continue
            }
            let id = "tag-\(UUID().uuidString.prefix(8).lowercased())"
            do {
                try store.apply(.createTag, Args([
                    "id": .string(id), "ledgerId": .string(store.activeLedgerId), "name": .string(name)]))
                ids.insert(id)
            } catch { /* skip a tag that fails to create (e.g. duplicate) */ }
        }
        selected = ids
        dismiss()
    }
}

/// The "Create ‹name›" row. It lives in its own view so it can read the
/// `dismissSearch` action — which is only available *inside* the `.searchable`
/// scope (a descendant of the modified List). Tapping it stages the tag and
/// collapses the search field, so the toolbar's ✓ Confirm (hidden by iOS while
/// search is active) comes back into reach.
private struct CreateTagRow: View {
    let name: String
    let onCreate: () -> Void
    @Environment(\.dismissSearch) private var dismissSearch

    var body: some View {
        Button {
            onCreate()
            dismissSearch()
        } label: {
            Label("Create “\(name)”", systemImage: "plus.circle").foregroundStyle(.tint)
        }
    }
}
