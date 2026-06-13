import Foundation
import FinchCore

/// Phase 7 — the read-side data a future WidgetKit extension + Watch app render.
/// Computed in-app from the projected state (the widget/Watch have no DB access;
/// they read this JSON snapshot). The WidgetKit/Watch *targets* + the App Group
/// container they'd read from are deferred infra (see open-questions); this is
/// the data layer they depend on. Snapshot is written to a JSON file after each
/// backup so it's always current.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var netWorth: Double
    public var currency: String
    public var budgetUsedPct: Int      // 0…100 across all budgets this period
    public var weeklySpent: Double
    public var generatedAt: String

    public init(netWorth: Double, currency: String, budgetUsedPct: Int, weeklySpent: Double, generatedAt: String) {
        self.netWorth = netWorth; self.currency = currency
        self.budgetUsedPct = budgetUsedPct; self.weeklySpent = weeklySpent; self.generatedAt = generatedAt
    }

    /// Net worth in base currency — sum of `includeInNetWorth` account balances,
    /// each converted account-currency → base. Pure (testable).
    public static func netWorth(_ accounts: [AccountRow], toBase: (Double, String?) -> Double) -> Double {
        accounts.filter { ($0.includeInNetWorth ?? 1) == 1 }
            .reduce(0.0) { $0 + toBase($1.balance, $1.currency) }
    }

    /// Aggregate budget usage % across budgets this period (used / base). Pure.
    public static func budgetUsedPct(_ budgets: [BudgetRow], _ txns: [Tx], _ today: String,
                                     _ categories: [CategoryNode]) -> Int {
        var used = 0.0, base = 0.0
        for b in budgets {
            let p = Selectors.budgetProgress(b, txns, today, categories)
            used += p.used; base += p.base
        }
        guard base > 0 else { return 0 }
        return Int((used / base * 100).rounded())
    }
}

@MainActor
public enum WidgetSnapshotWriter {
    /// Where the snapshot lives. (Future: the App Group container so the widget
    /// extension can read it; for now Application Support — App Group is Phase 6.5
    /// deferred infra.)
    public static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("widget_snapshot.json")
    }

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
        if let data = try? JSONEncoder().encode(snap) { try? data.write(to: url) }
    }
}
