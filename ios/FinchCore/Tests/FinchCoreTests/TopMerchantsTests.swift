import XCTest
import GRDB
@testable import FinchCore

final class TopMerchantsTests: XCTestCase {
    @discardableResult
    private func add(_ q: DatabaseQueue, _ amount: Double, _ merchant: String,
                     _ date: String = "2026-05-10", pending: Bool = false) throws -> String {
        var a: [String: JSONValue] = ["ledgerId": .string("l1"), "accountId": .string("a1"),
            "amount": .double(amount), "merchant": .string(merchant), "categoryId": .string("c1"),
            "date": .string(date), "skipRules": .bool(true)]
        if pending { a["status"] = .string("pending") }
        return try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args(a))!
    }
    private func txns(_ q: DatabaseQueue) throws -> [Tx] { try Projection.run(dbQueue: q, ledgerId: "l1") }

    func test_ranks_by_total_and_respects_limit() throws {
        let q = try TestSeed.base()
        try add(q, -50, "Cafe"); try add(q, -30, "Cafe")
        try add(q, -60, "Grocer")
        try add(q, -5, "Kiosk")
        let rows = Selectors.topMerchants(try txns(q), "l1", "2026-05", limit: 2)
        XCTAssertEqual(rows.map(\.name), ["Cafe", "Grocer"])
        XCTAssertEqual(rows.map(\.total), [80, 60])
    }

    func test_merges_by_normalized_name_skips_pending_and_other_months() throws {
        let q = try TestSeed.base()
        try add(q, -20, "Cafe")
        try add(q, -10, "  cafe ")                    // same key after trim + lowercase
        try add(q, -99, "Cafe", "2026-04-10")         // other month
        try add(q, -99, "Cafe", pending: true)        // pending
        let rows = Selectors.topMerchants(try txns(q), "l1", "2026-05")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].total, 30)
    }

    func test_refunds_net_and_fully_refunded_merchants_drop() throws {
        let q = try TestSeed.base()
        let store = try add(q, -40, "Store")
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(15),
            "merchant": .string("Store"), "categoryId": .string("c1"), "date": .string("2026-05-12"),
            "kind": .string("refund"), "refundedTransactionId": .string(store)]))
        let zeroed = try add(q, -10, "Zeroed")
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(10),
            "merchant": .string("Zeroed"), "categoryId": .string("c1"), "date": .string("2026-05-13"),
            "kind": .string("refund"), "refundedTransactionId": .string(zeroed)]))
        let rows = Selectors.topMerchants(try txns(q), "l1", "2026-05")
        XCTAssertEqual(rows.map(\.name), ["Store"])   // refund netted; Zeroed dropped at 0
        XCTAssertEqual(rows[0].total, 25)
    }
}
