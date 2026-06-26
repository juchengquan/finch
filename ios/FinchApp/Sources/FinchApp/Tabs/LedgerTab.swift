import SwiftUI
import FinchCore

/// The Ledger tab (home, slot #1) — a lean ledger overview: active ledger +
/// switcher, net worth, display currency, and this-month income/expense, with a
/// "View all activity" link into the full feed (the feed itself also lives in the
/// Accounts summary). Top-right overflow menu manages ledgers.
struct LedgerTab: View {
    @State private var showingManage = false

    var body: some View {
        NavigationStack {
            List {
                LedgerHeaderSection()
                Section {
                    NavigationLink {
                        ActivityFeedView()
                    } label: {
                        Label("View all activity", systemImage: "list.bullet")
                    }
                }
            }
            .navigationTitle("Ledger")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) { SettingsBarButton() }   // .topBarLeading is iOS-only; gear is compact-only anyway (macOS uses the sidebar)
                #endif
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showingManage = true } label: { Label("Manage ledgers", systemImage: "books.vertical") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .navigationDestination(isPresented: $showingManage) { LedgerManagementView() }
            .settingsPush()
        }
    }
}

/// Ledger-context summary at the top of the Ledger tab: active ledger name with
/// a switcher menu, net worth, display currency, and this-month income/expense.
/// (Manage-ledgers lives in the tab's top-right overflow menu.)
private struct LedgerHeaderSection: View {
    @EnvironmentObject private var store: FinchStore
    private var activeName: String { store.ledgers.first { $0.id == store.activeLedgerId }?.name ?? "Ledger" }

    private var thisMonth: (inc: Double, exp: Double) {
        let p = Selectors.monthlyCashflow(store.txns, store.activeLedgerId, String(store.today.prefix(7)), 1).first
        return (p?.inc ?? 0, p?.exp ?? 0)
    }

    var body: some View {
        Group {
            Section {
                HStack {
                    Menu {
                        ForEach(store.ledgers) { l in
                            Button {
                                if l.id != store.activeLedgerId { store.activeLedgerId = l.id }
                            } label: {
                                if l.id == store.activeLedgerId { Label(l.name, systemImage: "checkmark") }
                                else { Text(l.name) }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(activeName).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Net worth").font(.caption2).foregroundStyle(.secondary)
                        Text(store.netWorthDisplay).font(.headline)
                    }
                }
                Picker("Display currency", selection: Binding(
                    get: { store.displayCurrency },
                    set: { store.setDisplayCurrency($0) })) {
                    ForEach(store.availableDisplayCurrencies, id: \.self) { Text($0).tag($0) }
                }
            }
            Section("This month") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Income").font(.caption2).foregroundStyle(.secondary)
                        Text(store.displayMoneyBase(thisMonth.inc)).foregroundStyle(.green)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Expense").font(.caption2).foregroundStyle(.secondary)
                        Text(store.displayMoneyBase(thisMonth.exp)).foregroundStyle(.red)
                    }
                }
            }
        }
    }
}
