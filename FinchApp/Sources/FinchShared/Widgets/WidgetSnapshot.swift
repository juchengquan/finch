import Foundation
import FinchCore

/// Phase 7 — builds the `WidgetSnapshot` (defined in FinchCore) from the app's
/// projected state and writes it to the shared App Group container, where the
/// WidgetKit extension + Watch app read it. Called after each backup.
@MainActor
public enum WidgetSnapshotWriter {
    public static func build(from store: FinchStore) -> WidgetSnapshot {
        let nw = WidgetSnapshot.netWorth(store.accounts) { store.baseAmount($0, from: $1) }
        let pct = WidgetSnapshot.budgetUsedPct(store.budgets, store.txns, store.today, store.categoryNodes)
        let weekly = Selectors.weeklyDigest(store.txns, store.activeLedgerId, store.today)?.spent ?? 0
        let stamp = ISO8601DateFormatter().string(from: Date())
        let accts = store.accounts.map {
            AccountSnapshotItem(id: $0.id, name: $0.name ?? "Account", balance: $0.balance, currency: $0.currency ?? store.displayCurrency)
        }
        let buds = store.budgets.map {
            BudgetSnapshotItem(id: $0.id, name: $0.name, usedPct: Selectors.budgetProgress($0, store.txns, store.budgetToday, store.categoryNodes).pct)
        }
        return WidgetSnapshot(netWorth: nw, currency: store.displayCurrency,
                              budgetUsedPct: pct, weeklySpent: weekly, generatedAt: stamp,
                              accounts: accts, budgets: buds)
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
