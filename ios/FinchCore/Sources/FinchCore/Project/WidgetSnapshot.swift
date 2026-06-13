import Foundation

/// Phase 7 — the read-side data the WidgetKit extension + Watch app render. They
/// have no DB access, so the app writes this snapshot to the shared App Group
/// container and the widget/Watch read it. Lives in FinchCore so both the app
/// and the extension targets can use it.
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

/// The shared App Group container (Phase 6.5 setup) — the cross-process scratch
/// space the Share Extension, Widget, and Watch use. Falls back to Application
/// Support when the App Group isn't available (e.g. an unsigned simulator build
/// without the container provisioned), so callers never crash.
public enum AppGroup {
    public static let identifier = "group.com.juchengquan.finch"

    public static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Where the widget snapshot is written/read.
    public static var widgetSnapshotURL: URL {
        containerURL.appendingPathComponent("widget_snapshot.json")
    }

    /// Decode the current widget snapshot (nil when none written yet).
    public static func readWidgetSnapshot() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: widgetSnapshotURL) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
