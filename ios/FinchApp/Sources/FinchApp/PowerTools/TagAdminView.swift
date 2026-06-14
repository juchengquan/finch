import SwiftUI
import FinchCore

/// Phase 4 — tag admin: add / rename / delete tags (create/update/deleteTag).
struct TagAdminView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var showingAdd = false
    @State private var renaming: TagRow?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if store.tags.isEmpty { Text("No tags yet.").foregroundStyle(.secondary) }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            ForEach(store.tags) { tag in
                Button { renaming = tag } label: {
                    HStack {
                        Image(systemName: "tag").foregroundStyle(.secondary)
                        Text(tag.name).foregroundStyle(.primary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { delete(tag) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("Tags")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add tag")
            }
        }
        .sheet(isPresented: $showingAdd) { TagEditSheet(tag: nil) }
        .sheet(item: $renaming) { TagEditSheet(tag: $0) }
    }

    private func delete(_ t: TagRow) {
        do { try store.apply(.deleteTag, Args(["id": .string(t.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
}

struct TagEditSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let tag: TagRow?
    @State private var name: String
    @State private var errorMessage: String?

    init(tag: TagRow?) { self.tag = tag; _name = State(initialValue: tag?.name ?? "") }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle(tag == nil ? "New Tag" : "Rename Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
        }
    }

    private func save() {
        errorMessage = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { errorMessage = "Enter a name."; return }
        do {
            if let t = tag {
                try store.apply(.updateTag, Args(["id": .string(t.id), "patch": .object(["name": .string(trimmed)])]))
            } else {
                try store.apply(.createTag, Args(["ledgerId": .string(store.activeLedgerId), "name": .string(trimmed)]))
            }
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
