import Foundation

/// Watch sub-project CP1 — the phone→watch wire format. Foundation-only and
/// compiled into BOTH FinchApp and FinchWatch so the two sides agree on the shape
/// without the watch depending on FinchCore. Sent via
/// `WCSession.updateApplicationContext(["snapshot": data])`.
struct WatchSnapshotPayload: Codable, Equatable {
    var netWorth: Double
    var currency: String
    var budgetUsedPct: Int
    var weeklySpent: Double
    var generatedAt: Date
    /// CP3 — up to 3 recent-expense quick-add templates. Optional so CP1/CP2-era
    /// payloads (and receivers) stay compatible in both directions.
    var recents: [WatchQuickAddItem]? = nil

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data) -> WatchSnapshotPayload? {
        try? JSONDecoder().decode(WatchSnapshotPayload.self, from: data)
    }
}

/// CP3 — one quick-add template (a mirror of FinchCore's `RecentExpense`, plus
/// the ledger stamped at snapshot-build time, since the phone's active ledger
/// can change between push and tap). `amount` is a positive magnitude in the
/// item's native `currency`.
struct WatchQuickAddItem: Codable, Equatable {
    var merchant: String
    var amount: Double
    var currency: String
    var ledgerId: String
    var accountId: String
    var categoryId: String?
}

/// CP3 — the watch→phone quick-add message body. `id` is client-minted so the
/// phone can drop `transferUserInfo` redeliveries.
struct WatchQuickAddRequest: Codable, Equatable {
    var id: String
    var item: WatchQuickAddItem

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data) -> WatchQuickAddRequest? {
        try? JSONDecoder().decode(WatchQuickAddRequest.self, from: data)
    }
}
