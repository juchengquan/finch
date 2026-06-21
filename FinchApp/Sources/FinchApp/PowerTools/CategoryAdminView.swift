import SwiftUI
import FinchCore

/// Phase 4 (categories admin) — rename / add / delete spending categories.
/// createCategory / updateCategory / deleteCategory through the chokepoint.
/// (Merge is not yet a chokepoint action — deferred, see open-questions.)
struct CategoryAdminView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var showingAdd = false
    @State private var renaming: CategoryRow?
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(store.pickableCategories) { cat in
                Button { renaming = cat } label: {
                    HStack {
                        Text(cat.name).foregroundStyle(.primary)
                        Spacer()
                        Text(cat.kind ?? "expense").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { delete(cat) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("Categories")
        .errorAlert($errorMessage)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add category")
            }
        }
        .sheet(isPresented: $showingAdd) { CategoryEditSheet(category: nil) }
        .sheet(item: $renaming) { CategoryEditSheet(category: $0) }
    }

    private func delete(_ c: CategoryRow) {
        errorMessage = nil
        do { try store.apply(.deleteCategory, Args(["id": .string(c.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
}

/// Add (category == nil) or rename an existing category.
struct CategoryEditSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let category: CategoryRow?
    @State private var name: String
    @State private var kind: String
    @State private var errorMessage: String?

    init(category: CategoryRow?) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _kind = State(initialValue: category?.kind ?? "expense")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                if category == nil {
                    Picker("Kind", selection: $kind) { Text("Expense").tag("expense"); Text("Income").tag("income") }
                        .pickerStyle(.segmented)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle(category == nil ? "New Category" : "Rename")
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
            if let c = category {
                try store.apply(.updateCategory, Args(["id": .string(c.id), "patch": .object(["name": .string(trimmed)])]))
            } else {
                try store.apply(.createCategory, Args(["ledgerId": .string(store.activeLedgerId), "name": .string(trimmed), "type": .string(kind)]))
            }
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
