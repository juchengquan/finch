import SwiftUI
import FinchCore

/// Holdings (investment positions) — the 7th write screen, reached from the
/// Accounts tab. Lists each position with shares, market value, and unrealized
/// gain/loss; add a position, update its price, or delete it. createHolding /
/// setHoldingPrice / deleteHolding through FinchStore.apply.
///
/// `HoldingRow` and the two sheets it presents now live in `HoldingComponents.swift`
/// — the account detail screen shows the same positions with the same affordances.
struct HoldingsView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var pendingDelete: Holding?   // holding awaiting delete confirmation
    @State private var showingAdd = false
    @State private var pricing: Holding?
    @State private var errorMessage: String?

    private var investmentAccounts: [AccountRow] {
        store.accounts.filter { $0.type == "investment" }
    }

    var body: some View {
        Group {
            if store.holdings.isEmpty {
                ContentUnavailableView {
                    Label("No holdings", systemImage: "chart.bar")
                } description: {
                    Text(investmentAccounts.isEmpty
                         ? "Add an investment account first (import a pack with one)."
                         : "Tap + to add a position.")
                }
            } else {
                List {
                    ForEach(store.holdings, id: \.id) { h in
                        Button { pricing = h } label: { HoldingRow(holding: h).contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                // Not role: .destructive — fake removal animation pre-confirm.
                                Button { pendingDelete = h } label: { Label("Delete", systemImage: "trash") }.tint(.red)
                            }
                            .contextMenu {
                                Button(role: .destructive) { pendingDelete = h } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                }
            }
        }
        .navigationTitle("Holdings")
        // Centered ALERT (window-level) — see ActivityTab's delete alert.
        .alert("Delete holding?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete) { h in
            Button("Delete", role: .destructive) { delete(h) }
            Button("Cancel", role: .cancel) {}
        } message: { h in
            Text("\(h.symbol) is removed from this account.")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add Holding")
                    .disabled(investmentAccounts.isEmpty)
            }
        }
        .sheet(isPresented: $showingAdd) { AddHoldingSheet(accounts: investmentAccounts) }
        .sheet(item: $pricing) { SetHoldingPriceSheet(holding: $0) }
        .errorAlert($errorMessage)
    }

    private func delete(_ h: Holding) {
        do { try store.apply(.deleteHolding, Args(["id": .string(h.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
}
