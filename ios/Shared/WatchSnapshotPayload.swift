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
    /// CP3 composer — the entry catalog (default account + top categories) the
    /// watch composer picks from. Optional for the same wire back-compat.
    var quickAdd: WatchQuickAddCatalog? = nil

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

/// CP3 composer — the entry catalog the phone ships inside the snapshot so the
/// watch composer needs zero FinchCore: the default posting account + the top
/// expense categories (≤ 6) for the active ledger.
struct WatchQuickAddCatalog: Codable, Equatable {
    struct Item: Codable, Equatable {
        var id: String
        var name: String
    }
    var ledgerId: String
    var accountId: String        // default posting account
    var accountName: String
    var categories: [Item]
}

/// CP3 — the watch→phone quick-add message body (templates AND the composer —
/// one up-wire type, one receive path). `id` is client-minted so the phone can
/// drop `transferUserInfo` redeliveries. `createdAt` stamps the tap time so an
/// overnight-queued add books on the day it was tapped (optional: absent on
/// pre-composer senders → the phone falls back to its own today).
struct WatchQuickAddRequest: Codable, Equatable {
    var id: String
    var item: WatchQuickAddItem
    var createdAt: Date? = nil

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data) -> WatchQuickAddRequest? {
        try? JSONDecoder().decode(WatchQuickAddRequest.self, from: data)
    }
}
