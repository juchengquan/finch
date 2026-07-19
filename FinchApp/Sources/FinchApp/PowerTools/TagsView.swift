import SwiftUI
import FinchCore

/// Tags admin — a flat, color-only list (Settings top-level). Mirrors the
/// Categories page: search, color-swatch rows with a transaction-count pill,
/// tap → the tag's transactions, swipe Edit/Delete, + to add. All through the
/// existing chokepoints (create / update / deleteTag). Tags have no hierarchy,
/// kind, icon, or order — so no tree, kind picker, reorder, or merge here.
struct TagsView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var selectedTagId: String?          // tapped row → transactions
    @State private var creating = false
    @State private var editing: TagRow?
    @State private var deleting: TagRow?
    @State private var search = ""
    @State private var errorMessage: String?

    private var rows: [TagRow] {
        guard !search.isEmpty else { return store.tags }
        return store.tags.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        let counts = Selectors.tagTxCounts(store.txns, store.activeLedgerId)
        return List {
            if store.tags.isEmpty {
                emptyState
            } else {
                ForEach(rows) { tag in row(tag, counts) }
            }
        }
        .modifier(SearchableModifier(text: $search))
        .navigationTitle("Tags")
        .errorAlert($errorMessage)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New tag")
            }
        }
        .navigationDestination(item: $selectedTagId) { id in
            if let t = store.tags.first(where: { $0.id == id }) { TagDetailView(tag: t) }
        }
        .sheet(isPresented: $creating) { TagEditSheet(tag: nil) }
        .sheet(item: $editing) { TagEditSheet(tag: $0) }
        // Centered window-level alert (matches Categories/Activity deletes).
        .alert("Delete \(deleting?.name ?? "")?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting) { t in
            Button("Delete", role: .destructive) { delete(t) }
            Button("Cancel", role: .cancel) {}
        } message: { t in
            let n = counts[t.id] ?? 0
            if n > 0 { Text("\(t.name) is removed from \(n) transactions.") }
        }
    }

    /// A tag row: color swatch + name + count pill + a trailing chevron (every
    /// row navigates to its detail). Tap opens transactions; Edit/Delete are on
    /// the swipe (Edit is the full-swipe default) and context menu.
    @ViewBuilder private func row(_ tag: TagRow, _ counts: [String: Int]) -> some View {
        Button { selectedTagId = tag.id } label: {
            HStack(spacing: 10) {
                Circle().fill(Color(hex: tag.color ?? "") ?? .secondary).frame(width: 26, height: 26)
                Text(tag.name).foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let n = counts[tag.id], n > 0 {
                    Text("\(n)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                        .accessibilityLabel("\(n) transactions")
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            // Edit declared first ⇒ outer edge / full-swipe default (never delete).
            Button { editing = tag } label: { Label("Edit", systemImage: "pencil") }.tint(.accentColor)
            // Not role: .destructive — the alert confirms; matches Categories.
            Button { deleting = tag } label: { Label("Delete", systemImage: "trash") }.tint(.red)
        }
        .contextMenu {
            Button { editing = tag } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { deleting = tag } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tag").font(.largeTitle).foregroundStyle(.secondary)
            Text("No tags yet").font(.headline)
            Text("Tap + to add one.").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func delete(_ t: TagRow) {
        errorMessage = nil
        do { try store.apply(.deleteTag, Args(["id": .string(t.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
}

struct TagEditSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let tag: TagRow?
    @State private var name: String
    @State private var color: String     // "" = none
    @State private var errorMessage: String?

    init(tag: TagRow?) {
        self.tag = tag
        _name = State(initialValue: tag?.name ?? "")
        _color = State(initialValue: tag?.color ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Section("Color") {
                    HStack(spacing: 10) {
                        ForEach(TagPalette.hexes, id: \.self) { hex in
                            Circle().fill(Color(hex: hex) ?? .gray).frame(width: 26, height: 26)
                                .overlay(Circle().stroke(Color.primary, lineWidth: color == hex ? 2.5 : 0))
                                .contentShape(Circle())
                                .onTapGesture { color = (color == hex ? "" : hex) }
                                .accessibilityLabel("Color \(hex)")
                        }
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle(tag == nil ? "New Tag" : "Edit Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save")
                        .confirmCheckmarkStyle()
                }
            }
        }
    }

    private func save() {
        errorMessage = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { errorMessage = "Enter a name."; return }
        do {
            if let t = tag {
                let patch: [String: JSONValue] = [
                    "name": .string(trimmed),
                    "color": color.isEmpty ? .null : .string(color),
                ]
                try store.apply(.updateTag, Args(["id": .string(t.id), "patch": .object(patch)]))
            } else {
                var args: [String: JSONValue] = [
                    "ledgerId": .string(store.activeLedgerId), "name": .string(trimmed),
                ]
                if !color.isEmpty { args["color"] = .string(color) }
                try store.apply(.createTag, Args(args))
            }
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
