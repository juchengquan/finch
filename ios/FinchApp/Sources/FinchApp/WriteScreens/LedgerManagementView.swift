import SwiftUI
import FinchCore

/// Ledger CRUD (Settings › Manage ledgers). List with set-default, delete, and
/// per-ledger edit (rename + change base currency); a '+' creates a ledger.
/// All writes route FinchStore.apply. createLedger / changeLedgerBase /
/// setDefaultLedger / updateLedger / deleteLedger.
struct LedgerManagementView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var showingAdd = false
    @State private var editing: Ledger?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            ForEach(store.ledgers) { ledger in
                Button { editing = ledger } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ledger.name).foregroundStyle(.primary)
                            Text(ledger.base).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if ledger.id == store.activeLedgerId {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { delete(ledger) } label: { Label("Delete", systemImage: "trash") }
                        .disabled(store.ledgers.count <= 1)
                }
            }
        }
        .navigationTitle("Ledgers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add Ledger")
            }
        }
        .sheet(isPresented: $showingAdd) { AddLedgerSheet() }
        .sheet(item: $editing) { EditLedgerSheet(ledger: $0) }
    }

    private func delete(_ ledger: Ledger) {
        errorMessage = nil
        do { try store.apply(.deleteLedger, Args(["id": .string(ledger.id)])) }
        catch let e as I18nError { errorMessage = e.message } catch { errorMessage = "\(error)" }
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create", action: create).bold() }
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
        } catch let e as I18nError { errorMessage = e.message } catch { errorMessage = "\(error)" }
    }
}

/// Edit a ledger: rename, change base currency (re-derives every entry's
/// amount_base), and make it the active/default ledger.
struct EditLedgerSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let ledger: Ledger
    @State private var name: String
    @State private var base: String
    @State private var errorMessage: String?
    @State private var confirmingBaseChange = false

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
        } catch let e as I18nError { errorMessage = e.message } catch { errorMessage = "\(error)" }
    }

    private func run(_ action: ActionName, _ args: [String: JSONValue], then: () -> Void) {
        errorMessage = nil
        do { try store.apply(action, Args(args)); then(); dismiss() }
        catch let e as I18nError { errorMessage = e.message } catch { errorMessage = "\(error)" }
    }
}
