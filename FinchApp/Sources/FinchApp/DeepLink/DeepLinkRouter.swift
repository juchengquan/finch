import SwiftUI

/// The 6 shipped tabs, in display order (the canonical list reconciled in #160).
public enum AppTab: String, Hashable, CaseIterable, Identifiable, Sendable {
    case ledger, accounts, activity, budgets, insights, scheduled, settings
    public var id: Self { self }
    public var title: String {
        switch self {
        case .ledger: return String(localized: "Ledger")
        case .accounts: return String(localized: "Accounts")
        case .activity: return String(localized: "Activity")
        case .budgets: return String(localized: "Budgets")
        case .insights: return String(localized: "Insights")
        case .scheduled: return String(localized: "Scheduled")
        case .settings: return String(localized: "Settings")
        }
    }
    public var icon: String {
        switch self {
        case .ledger: return "books.vertical"
        case .accounts: return "wallet.pass"; case .activity: return "list.bullet"
        case .budgets: return "chart.pie"; case .insights: return "chart.line.uptrend.xyaxis"
        case .scheduled: return "calendar"; case .settings: return "gear"
        }
    }
}

/// Phase 6.1 — routes a deep link (a tapped Spotlight result; later: App Intents,
/// notifications) to the owning tab. Detail-screen pushes await Phase 3/4; until
/// then a tapped entity switches to its tab and the id is stashed in `focusedId`
/// for a future detail/filter consumer.
@MainActor
public final class DeepLinkRouter: ObservableObject {
    /// Shared instance so App Intents / notifications (which run outside the
    /// SwiftUI tree) drive the same router the UI observes.
    public static let shared = DeepLinkRouter()

    @Published public var selectedTab: AppTab = .ledger   // Ledger is the home/first tab
    @Published public var focusedId: String? = nil
    @Published var pendingFilter: TxFilter?   // one-shot: consumed by the Activity feed
    @Published public var showCommandPalette = false   // ⌘K (Phase 3 / Mac)
    @Published public var showAddTransaction = false    // ⌘N
    @Published public var exportRequested = false       // File ▸ Export .finch… (⌘⇧E)
    @Published public var showSettings = false          // top-left gear (compact, prototype)

    public init() {}

    /// Identifier shape: `tx:<id>`, `account:<id>`, `category:<id>`,
    /// `counterparty:<id>`, `budget:<id>`.
    public func route(to identifier: String) {
        let parts = identifier.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return }
        focusedId = String(parts[1])
        switch String(parts[0]) {
        case "tx", "counterparty": selectedTab = .activity
        case "account": selectedTab = .accounts
        case "category", "budget": selectedTab = .budgets
        case "insights": selectedTab = .insights
        case "scheduled": selectedTab = .scheduled
        default: break
        }
    }

    /// Switch directly to a tab (App Intents "open screen", notifications).
    public func open(_ tab: AppTab) { selectedTab = tab }

    /// Handle a `finch://…` deep link (e.g. a widget tap). `finch://add` opens the Add sheet.
    public func handle(_ url: URL) {
        switch url.host {
        case "add": showAddTransaction = true
        default: break
        }
    }
}
