import XCTest
@testable import FinchApp

final class WatchSnapshotDisplayTests: XCTestCase {
    private func payload(generatedAt: Date = .now) -> WatchSnapshotPayload {
        WatchSnapshotPayload(netWorth: 0, currency: "USD", budgetUsedPct: 0,
                             weeklySpent: 0, generatedAt: generatedAt)
    }

    func test_shortMoney_belowThousand_noDecimals() {
        XCTAssertEqual(payload().shortMoney(842.4), "$842")
    }

    func test_shortMoney_thousands_oneDecimal() {
        XCTAssertEqual(payload().shortMoney(12_340), "$12.3K")
    }

    func test_shortMoney_respectsCurrency() {
        var p = payload(); p.currency = "JPY"
        XCTAssertEqual(p.shortMoney(1_200_000), "¥1.2M")
    }

    func test_isStale_boundary24h() {
        XCTAssertFalse(payload(generatedAt: Date(timeIntervalSinceNow: -23 * 3600)).isStale)
        XCTAssertTrue(payload(generatedAt: Date(timeIntervalSinceNow: -25 * 3600)).isStale)
    }

    func test_storeConstants() {
        XCTAssertEqual(WatchStore.suite, "group.com.juchengquan.finch")
        XCTAssertEqual(WatchStore.key, "watchSnapshot")
    }
}
