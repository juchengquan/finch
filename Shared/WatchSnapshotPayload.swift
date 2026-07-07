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

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data) -> WatchSnapshotPayload? {
        try? JSONDecoder().decode(WatchSnapshotPayload.self, from: data)
    }
}
