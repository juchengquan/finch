import SwiftUI
import FinchCore

/// Phase 4 — tag admin: add / rename / delete tags + per-tag color
/// (create/update/deleteTag). Color uses the shared web tag palette.
struct TagAdminView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var pendingDelete: TagRow?   // tag awaiting delete confirmation
    @State private var showingAdd = false
    @State private var renaming: TagRow?
    @State private var errorMessage: String?

    var body: some View {
        let counts = Selectors.tagTxCounts(store.txns, store.activeLedgerId)
        return List {
            if store.tags.isEmpty { Text("No tags yet.").foregroundStyle(.secondary) }
            ForEach(store.tags) { tag in
                Button { renaming = tag } label: {
                    HStack {
                        Circle().fill(Color(hex: tag.color ?? "") ?? .secondary)
                            .frame(width: 12, height: 12)
                        Text(tag.name).foregroundStyle(.primary)
                        if let n = counts[tag.id], n > 0 {
                            Text("\(n)×").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .accessibilityLabel("\(n) transactions")
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    // Not role: .destructive — fake removal animation pre-confirm.
                    Button { pendingDelete = tag } label: { Label("Delete", systemImage: "trash") }.tint(.red)
                }
                .contextMenu {
                    Button(role: .destructive) { pendingDelete = tag } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("Tags")
        // Centered ALERT (window-level) — see ActivityTab's delete alert.
        .alert("Delete tag?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete) { t in
            Button("Delete", role: .destructive) { delete(t) }
            Button("Cancel", role: .cancel) {}
        } message: { t in
            Text("\(t.name) is removed from all transactions.")
        }
        .errorAlert($errorMessage)
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
                        .accessibilityLabel("Save").bold()
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
