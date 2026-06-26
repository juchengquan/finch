import SwiftUI
import FinchCore

/// The Ledger tab (home, slot #1) — a compact ledger-context header (active
/// ledger + switcher, net worth, manage) atop the full activity feed for the
/// active ledger. Reuses `ActivityFeedView` with a header section, since a
/// ledger *is* the container for its transactions.
struct LedgerTab: View {
    var body: some View {
        NavigationStack {
            ActivityFeedView(navTitle: "Ledger", headerSection: AnyView(LedgerHeaderSection()))
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .topBarLeading) { SettingsBarButton() }   // .topBarLeading is iOS-only; gear is compact-only anyway (macOS uses the sidebar)
                    #endif
                }
                .settingsPush()
        }
    }
}

/// Ledger-context summary at the top of the Ledger tab: active ledger name with
/// a switcher menu, net worth + trend sparkline, this-month income/expense, and
/// a Manage-ledgers drill-in.
private struct LedgerHeaderSection: View {
    @EnvironmentObject private var store: FinchStore
    private var activeName: String { store.ledgers.first { $0.id == store.activeLedgerId }?.name ?? "Ledger" }

    private var netWorthTrend: [Double] {
        Selectors.netWorthSeries(store.txns, store.accounts, store.activeLedgerId) { amt, ccy in
            Money.convert(amt, from: ccy ?? store.baseCurrency, to: store.baseCurrency, rates: store.rateMap) ?? amt
        }
    }
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
                let trend = netWorthTrend
                if trend.count > 1 {
                    Sparkline(values: trend).frame(height: 40)
                }
                Picker("Display currency", selection: Binding(
                    get: { store.displayCurrency },
                    set: { store.setDisplayCurrency($0) })) {
                    ForEach(store.availableDisplayCurrencies, id: \.self) { Text($0).tag($0) }
                }
                NavigationLink {
                    LedgerManagementView()
                } label: {
                    Label("Manage ledgers", systemImage: "books.vertical")
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
