import SwiftUI
import FinchCore

/// Phase 4 — apply one category to many selected transactions via the
/// bulkRecategorize chokepoint action (rebuilds each single-category entry's
/// category leg; multi-split entries are skipped by the engine).
struct BulkRecategorizeSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let ids: [String]
    let onDone: () -> Void
    @State private var categoryId = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Category", selection: $categoryId) {
                        ForEach(store.pickableCategories) { Text($0.name).tag($0.id) }
                    }
                } footer: {
                    Text("Applies to \(ids.count) selected transaction\(ids.count == 1 ? "" : "s").")
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Recategorize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply", action: apply).bold() }
            }
            .onAppear { if categoryId.isEmpty { categoryId = store.pickableCategories.first?.id ?? "" } }
        }
    }

    private func apply() {
        errorMessage = nil
        guard !categoryId.isEmpty else { errorMessage = "Pick a category."; return }
        do {
            try store.apply(.bulkRecategorize, Args([
                "ids": .array(ids.map { .string($0) }), "categoryId": .string(categoryId)]))
            onDone()
            dismiss()
        } catch let e as I18nError { errorMessage = e.message } catch { errorMessage = "\(error)" }
    }
}
