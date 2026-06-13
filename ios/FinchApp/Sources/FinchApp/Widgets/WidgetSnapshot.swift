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
        return WidgetSnapshot(netWorth: nw, currency: store.displayCurrency,
                              budgetUsedPct: pct, weeklySpent: weekly, generatedAt: stamp)
    }

    public static func write(from store: FinchStore) {
        let snap = build(from: store)
        if let data = try? JSONEncoder().encode(snap) { try? data.write(to: AppGroup.widgetSnapshotURL) }
    }
}
