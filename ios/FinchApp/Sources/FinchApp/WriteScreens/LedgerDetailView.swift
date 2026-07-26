import SwiftUI
import FinchCore

/// Ledger drill-in (layer 2 of the two-layer Ledger tab): per-ledger summary
/// (net worth + this-month) and actions (make active / edit / delete). Reads any
/// ledger by id — the active one from live state, others from a fresh read — so a
/// non-active ledger can be previewed without switching the app. The full activity
/// feed appears only for the active ledger. Pops if the ledger is deleted.
struct LedgerDetailView: View {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var gate: BiometricGate
    #if os(iOS)
    @EnvironmentObject private var router: DeepLinkRouter
    #endif
    @Environment(\.dismiss) private var dismiss
    let ledgerId: String

    @State private var summary: FinchStore.LedgerSummary?
    @State private var editing: Ledger?
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    private var ledger: Ledger? { store.ledgers.first { $0.id == ledgerId } }
    private var isActive: Bool { ledgerId == store.activeLedgerId }

    var body: some View {
        Group {
            if let ledger {
                List {
                    summarySection
                    accountsSection
                    currencySection
                    actionsSection(ledger)
                    if isActive {
                        Section {
                            #if os(iOS)
                            Button {
                                pushViaUIKit(ActivityFeedView(), store: store, router: router, gate: gate)
                            } label: {
                                Label("View all activity", systemImage: "list.bullet")
                            }
                            #else
                            NavigationLink { ActivityFeedView() } label: {
                                Label("View all activity", systemImage: "list.bullet")
                            }
                            #endif
                        }
                    }
                }
                .navigationTitle(ledger.name)
                .navigationBarTitleDisplayMode(.inline)
                .errorAlert($errorMessage)
                .sheet(item: $editing) { EditLedgerSheet(ledger: $0) }
                .task(id: ledgerId) { summary = store.ledgerSummary(ledgerId) }
                .onChange(of: store.txns) { _, _ in summary = store.ledgerSummary(ledgerId) }
            } else {
                Color.clear.onAppear { dismiss() }   // ledger removed elsewhere
            }
        }
    }

    @ViewBuilder private var summarySection: some View {
        if let s = summary {
            Section {
                HStack {
                    Text("Net worth").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(store.displayMoney(s.netWorth, forLedger: ledgerId)).font(.headline)
                }
                StatusSummaryRow(leadingLabel: "Income",
                                 leadingValue: store.displayMoney(s.monthIncome, forLedger: ledgerId),
                                 trailingLabel: "Expense",
                                 trailingValue: store.displayMoney(s.monthExpense, forLedger: ledgerId))
            } header: { Text("This month") }
        }
    }

    @ViewBuilder private var accountsSection: some View {
        if let s = summary, !s.accounts.isEmpty {
            let base = store.baseCurrency(forLedger: ledgerId)
            Section("Accounts") {
                ForEach(s.accounts) { a in
                    HStack {
                        Text(a.name ?? "—")
                        Spacer()
                        Text(store.displayMoney(store.toBase(a.balance, from: a.currency, ledgerBase: base), forLedger: ledgerId))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var currencySection: some View {
        Section {
            Picker("Display currency", selection: Binding(
                get: { store.displayCurrency(forLedger: ledgerId) },
                set: { store.setDisplayCurrency($0, ledgerId: ledgerId); summary = store.ledgerSummary(ledgerId) })) {
                ForEach(store.availableDisplayCurrencies(forLedger: ledgerId), id: \.self) { Text($0).tag($0) }
            }
        }
    }

    @ViewBuilder private func actionsSection(_ ledger: Ledger) -> some View {
        Section {
            if !isActive {
                Button("Make active ledger") {
                    do {
                        try store.apply(.setDefaultLedger, Args(["id": .string(ledgerId)]))
                        store.activeLedgerId = ledgerId
                    } catch { errorMessage = i18nMessage(error) }
                }
            }
            Button("Edit") { editing = ledger }
            Button("Delete", role: .destructive) { confirmingDelete = true }
                .disabled(store.ledgers.count <= 1)
                // Anchored on the button (iOS 26 positions popouts at their source).
                .confirmationDialog("Delete this ledger?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { delete(ledger) }
                }
        }
    }

    private func delete(_ ledger: Ledger) {
        errorMessage = nil
        // Deleting a ledger destroys its data — gate it like the other sensitive actions.
        Task {
            guard await gate.confirmSensitive() else { return }
            do {
                try store.apply(.deleteLedger, Args(["id": .string(ledger.id)]))
                if store.activeLedgerId == ledger.id {   // reassign active if we deleted it
                    store.activeLedgerId = store.ledgers.first?.id ?? ""
                }
                dismiss()
            } catch { errorMessage = i18nMessage(error) }
        }
    }
}
