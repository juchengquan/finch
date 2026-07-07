import XCTest
import FinchCore
@testable import FinchApp

final class WatchSnapshotPayloadTests: XCTestCase {
    func test_encodeDecodeRoundTrip() throws {
        let p = WatchSnapshotPayload(netWorth: 1234.5, currency: "USD",
                                     budgetUsedPct: 42, weeklySpent: 78.9,
                                     generatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try XCTUnwrap(p.encoded())
        let back = try XCTUnwrap(WatchSnapshotPayload.decode(data))
        XCTAssertEqual(p, back)
    }

    func test_decodeGarbageReturnsNil() {
        XCTAssertNil(WatchSnapshotPayload.decode(Data([0x00, 0x01, 0x02])))
    }

    func test_initFromWidgetSnapshot_copiesGlanceFields() {
        let snap = WidgetSnapshot(netWorth: 100, currency: "EUR", budgetUsedPct: 33,
                                  weeklySpent: 12, generatedAt: "x", accounts: nil, budgets: nil)
        let p = WatchSnapshotPayload(widget: snap)
        XCTAssertEqual(p.netWorth, 100)
        XCTAssertEqual(p.currency, "EUR")
        XCTAssertEqual(p.budgetUsedPct, 33)
        XCTAssertEqual(p.weeklySpent, 12)
    }
}
