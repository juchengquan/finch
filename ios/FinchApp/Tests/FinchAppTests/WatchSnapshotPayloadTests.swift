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

    func test_roundTrip_withRecents() throws {
        var p = WatchSnapshotPayload(netWorth: 1, currency: "USD", budgetUsedPct: 1,
                                     weeklySpent: 1, generatedAt: Date(timeIntervalSince1970: 0))
        p.recents = [WatchQuickAddItem(merchant: "Cafe", amount: 4.5, currency: "USD",
                                       ledgerId: "l1", accountId: "a1", categoryId: "c1")]
        let back = try XCTUnwrap(WatchSnapshotPayload.decode(XCTUnwrap(p.encoded())))
        XCTAssertEqual(back, p)
        XCTAssertEqual(back.recents?.first?.merchant, "Cafe")
    }

    func test_decode_cp1PayloadWithoutRecents_isNilRecents() throws {
        // A CP1/CP2-era payload has no `recents` key — must still decode.
        let legacy = #"{"netWorth":10,"currency":"USD","budgetUsedPct":5,"weeklySpent":2,"generatedAt":0}"#
        let p = try XCTUnwrap(WatchSnapshotPayload.decode(Data(legacy.utf8)))
        XCTAssertNil(p.recents)
        XCTAssertEqual(p.netWorth, 10)
    }

    func test_quickAddArgs_mapsExpenseSignAndFields() {
        let req = WatchQuickAddRequest(id: "r1", item: WatchQuickAddItem(
            merchant: "Cafe", amount: 4.5, currency: "USD",
            ledgerId: "l1", accountId: "a1", categoryId: "c1"))
        let args = PhoneWatchLink.quickAddArgs(req, date: "2026-07-07")
        XCTAssertEqual(args["amount"], .double(-4.5))
        XCTAssertEqual(args["ledgerId"], .string("l1"))
        XCTAssertEqual(args["accountId"], .string("a1"))
        XCTAssertEqual(args["categoryId"], .string("c1"))
        XCTAssertEqual(args["date"], .string("2026-07-07"))
        XCTAssertEqual(args["merchant"], .string("Cafe"))
    }

    func test_quickAddArgs_omitsNilCategory() {
        let req = WatchQuickAddRequest(id: "r2", item: WatchQuickAddItem(
            merchant: "Kiosk", amount: 2, currency: "USD",
            ledgerId: "l1", accountId: "a1", categoryId: nil))
        XCTAssertNil(PhoneWatchLink.quickAddArgs(req, date: "2026-07-07")["categoryId"])
    }

    func test_quickAddRequest_roundTrip() throws {
        let req = WatchQuickAddRequest(id: "r1", item: WatchQuickAddItem(
            merchant: "Cafe", amount: 4.5, currency: "USD",
            ledgerId: "l1", accountId: "a1", categoryId: nil))
        let back = try XCTUnwrap(WatchQuickAddRequest.decode(XCTUnwrap(req.encoded())))
        XCTAssertEqual(back, req)
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
