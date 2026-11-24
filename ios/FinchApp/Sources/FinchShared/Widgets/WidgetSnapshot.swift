import Foundation
import FinchCore

/// Phase 7 — builds the `WidgetSnapshot` (defined in FinchCore) from the app's
/// projected state and writes it to the shared App Group container, where the
/// WidgetKit extension + Watch app read it. Called after every write (the ambient
/// round), and when hide-amounts or the active ledger changes.
@MainActor
public enum WidgetSnapshotWriter {
    public static func build(from store: FinchStore) -> WidgetSnapshot {
        // The figures are base amounts; the label is the currency they are SHOWN in.
        // Stamping the display currency on base figures made an SGD ledger shown in
        // USD read S$10,000 as "$10,000". Converted when a rate exists, else left in
        // base and labelled as base — never a figure in one currency under another's.
        let base = store.baseCurrency, display = store.displayCurrency
        let canConvert = Money.convert(1, from: base, to: display, rates: store.rateMap) != nil
        func shown(_ v: Double) -> Double {
            canConvert ? (Money.convert(v, from: base, to: display, rates: store.rateMap) ?? v) : v
        }
        let nw = shown(WidgetSnapshot.netWorth(store.accounts) { store.baseAmount($0, from: $1) })
        // budgetToday (the wall clock), like the per-budget items below: the data-
        // anchored `today` showed last month's figure on the 1st.
        let pct = WidgetSnapshot.budgetUsedPct(store.budgets, store.txns, store.budgetToday, store.categoryNodes)
        let weekly = shown(Selectors.spentThisWeek(store.txns, store.activeLedgerId, store.wallToday))
        let stamp = ISO8601DateFormatter().string(from: Date())
        let accts = store.accounts.map {
            AccountSnapshotItem(id: $0.id, name: $0.name ?? "Account", balance: $0.balance, currency: $0.currency ?? base)
        }
        let buds = store.budgets.map {
            BudgetSnapshotItem(id: $0.id, name: $0.name, usedPct: Selectors.budgetProgress($0, store.txns, store.budgetToday, store.categoryNodes).pct)
        }
        return WidgetSnapshot(netWorth: nw, currency: canConvert ? display : base,
                              budgetUsedPct: pct, weeklySpent: weekly, generatedAt: stamp,
                              accounts: accts, budgets: buds, masked: store.privacyMode)
    }

    public static func write(from store: FinchStore) {
        let snap = build(from: store)
        if let data = try? JSONEncoder().encode(snap) { try? data.write(to: AppGroup.widgetSnapshotURL) }
        #if os(iOS)
        var payload = WatchSnapshotPayload(widget: snap)
        // CP3: ride up to 3 quick-add templates along with the figures; the
        // ledger is stamped now because the active ledger can change before
        // the user taps on the watch.
        payload.recents = Selectors.recentExpenses(store.txns, store.activeLedgerId, 3).map {
            WatchQuickAddItem(merchant: $0.merchant, amount: $0.amount, currency: $0.currency,
                              ledgerId: store.activeLedgerId, accountId: $0.accountId, categoryId: $0.categoryId)
        }
        // CP3 composer: the entry catalog (default account + top categories).
        payload.quickAdd = QuickAddCatalogBuilder.build(
            ledgerId: store.activeLedgerId, accounts: store.accounts, txns: store.txns,
            categories: store.pickableCategories,
            since: QuickAddCatalogBuilder.sinceDate(daysBack: 90))
        PhoneWatchLink.shared.push(payload)
        #endif
    }
}
