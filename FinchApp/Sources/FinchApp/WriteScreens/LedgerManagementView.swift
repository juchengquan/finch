import SwiftUI
import FinchCore

/// Layer 1 of the Ledger tab: every ledger with its base + net worth and an
/// active marker. Tapping a row drills into `LedgerDetailView`; `+` adds; swipe
/// deletes (gated). Reuses the AddLedgerSheet/EditLedgerSheet below.
struct LedgerListView: View {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var gate: BiometricGate
    @State private var showingAdd = false
    @State private var errorMessage: String?
    @State private var pendingDelete: Ledger?   // ledger awaiting delete confirmation

    var body: some View {
        List {
            ForEach(store.ledgers) { ledger in
                NavigationLink(value: ledger.id) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ledger.name).foregroundStyle(.primary)
                            Text(ledger.base).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if ledger.id == store.activeLedgerId {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                        }
                        Text(store.displayMoney(store.netWorth(forLedger: ledger.id), forLedger: ledger.id))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { pendingDelete = ledger } label: { Label("Delete", systemImage: "trash") }
                        .disabled(store.ledgers.count <= 1)
                }
            }
        }
        .navigationTitle("Ledgers")
        .errorAlert($errorMessage)
        .confirmationDialog("Delete this ledger?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible, presenting: pendingDelete) { ledger in
            Button("Delete \(ledger.name)", role: .destructive) { delete(ledger) }
        } message: { ledger in
            Text("This permanently deletes \(ledger.name) and all its data.")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add Ledger")
            }
        }
        .sheet(isPresented: $showingAdd) { AddLedgerSheet() }
        .navigationDestination(for: String.self) { LedgerDetailView(ledgerId: $0) }
    }

    private func delete(_ ledger: Ledger) {
        errorMessage = nil
        Task {
            guard await gate.confirmSensitive() else { return }
            do {
                try store.apply(.deleteLedger, Args(["id": .string(ledger.id)]))
                if store.activeLedgerId == ledger.id {   // deleted the active ledger → switch to a remaining one
                    store.activeLedgerId = store.ledgers.first?.id ?? ""
                }
            } catch { errorMessage = i18nMessage(error) }
        }
    }
}

/// Create a ledger (createLedger requires a client-minted id).
struct AddLedgerSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var base = "USD"
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Base currency (e.g. USD)", text: $base)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("New Ledger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: create) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Create").bold()
                }
            }
        }
    }

    private func create() {
        errorMessage = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { errorMessage = "Enter a name."; return }
        let id = "ledger_" + UUID().uuidString.prefix(8).lowercased()
        do {
            try store.apply(.createLedger, Args([
                "id": .string(id), "name": .string(trimmed),
                "base": .string(base.trimmingCharacters(in: .whitespaces).uppercased()),
            ]))
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}

/// Edit a ledger: rename, change base currency (re-derives every entry's
/// amount_base), and make it the active/default ledger.
struct EditLedgerSheet: View {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var gate: BiometricGate
    @Environment(\.dismiss) private var dismiss
    let ledger: Ledger
    @State private var name: String
    @State private var base: String
    @State private var errorMessage: String?

    init(ledger: Ledger) {
        self.ledger = ledger
        _name = State(initialValue: ledger.name)
        _base = State(initialValue: ledger.base)
    }

    private var baseChanged: Bool {
        base.trimmingCharacters(in: .whitespaces).uppercased() != ledger.base
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Base currency", text: $base)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                } footer: {
                    if baseChanged {
                        Text("Changing the base currency re-derives every entry's base amount.")
                    }
                }
                Section {
                    Button("Make active ledger") {
                        run(.setDefaultLedger, ["id": .string(ledger.id)]) { store.activeLedgerId = ledger.id }
                    }.disabled(ledger.id == store.activeLedgerId)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle("Edit Ledger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save").bold()
                }
            }
        }
    }

    private func save() async {
        errorMessage = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { errorMessage = "Enter a name."; return }
        // Changing the base re-derives every entry — a sensitive action (Phase 6.3).
        if baseChanged, await !gate.confirmSensitive() { return }
        do {
            if trimmed != ledger.name {
                try store.apply(.updateLedger, Args(["id": .string(ledger.id), "patch": .object(["name": .string(trimmed)])]))
            }
            if baseChanged {
                try store.apply(.changeLedgerBase, Args([
                    "ledgerId": .string(ledger.id),
                    "newBase": .string(base.trimmingCharacters(in: .whitespaces).uppercased()),
                ]))
            }
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }

    private func run(_ action: ActionName, _ args: [String: JSONValue], then: () -> Void) {
        errorMessage = nil
        do { try store.apply(action, Args(args)); then(); dismiss() }
        catch { errorMessage = i18nMessage(error) }
    }
}
