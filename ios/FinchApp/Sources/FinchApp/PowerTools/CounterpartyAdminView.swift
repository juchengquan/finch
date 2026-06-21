import SwiftUI
import FinchCore

/// Merchants / counterparties admin — list, search, add, rename, verify/unverify,
/// delete. The whole domain previously had no iOS UI. Routes FinchStore.apply.
struct CounterpartyAdminView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var search = ""
    @State private var showingAdd = false
    @State private var editing: Counterparty?
    @State private var errorMessage: String?

    private var filtered: [Counterparty] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? store.merchants : store.merchants.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        Group {
            if store.merchants.isEmpty {
                ContentUnavailableView("No merchants", systemImage: "person.crop.circle",
                                       description: Text("Merchants appear as you add transactions, or add one with +."))
            } else {
                List {
                    ForEach(filtered) { cp in
                        HStack {
                            Text(cp.name)
                            if cp.isVerified {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(.tint)
                                    .accessibilityLabel("Verified")
                            }
                            Spacer()
                            Button(cp.isVerified ? "Unverify" : "Verify") { toggleVerify(cp) }
                                .font(.caption).buttonStyle(.bordered)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(cp) } label: { Label("Delete", systemImage: "trash") }
                            Button { editing = cp } label: { Label("Rename", systemImage: "pencil") }.tint(.blue)
                        }
                        .contextMenu {
                            Button { editing = cp } label: { Label("Rename", systemImage: "pencil") }
                            Button { toggleVerify(cp) } label: { Label(cp.isVerified ? "Unverify" : "Verify", systemImage: "checkmark.seal") }
                            Button(role: .destructive) { delete(cp) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
                .searchable(text: $search)
            }
        }
        .navigationTitle("Merchants")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add Merchant")
            }
        }
        .sheet(isPresented: $showingAdd) { CounterpartyNameSheet(counterparty: nil) }
        .sheet(item: $editing) { CounterpartyNameSheet(counterparty: $0) }
        .errorAlert($errorMessage)
    }

    private func toggleVerify(_ cp: Counterparty) {
        do { try store.apply(cp.isVerified ? .unverifyCounterparty : .verifyCounterparty, Args(["id": .string(cp.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
    private func delete(_ cp: Counterparty) {
        do { try store.apply(.deleteCounterparty, Args(["id": .string(cp.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
}

/// Add or rename a counterparty (name only).
struct CounterpartyNameSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let counterparty: Counterparty?
    @State private var name: String
    @State private var errorMessage: String?

    init(counterparty: Counterparty?) {
        self.counterparty = counterparty
        _name = State(initialValue: counterparty?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle(counterparty == nil ? "Add Merchant" : "Rename Merchant")
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
            if let counterparty {
                try store.apply(.updateCounterparty, Args(["id": .string(counterparty.id), "patch": .object(["name": .string(trimmed)])]))
            } else {
                try store.apply(.createCounterparty, Args(["ledgerId": .string(store.activeLedgerId), "name": .string(trimmed)]))
            }
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
