import XCTest
@testable import FinchCore

final class SelectTransactionsTagTests: XCTestCase {
    private let txns = [
        Tx(id: "e1", merchant: "A", amount: -5, account: "a1", date: "2026-06-01", ledgerId: "l1", tags: ["t1"]),
        Tx(id: "e2", merchant: "B", amount: -5, account: "a1", date: "2026-06-02", ledgerId: "l1", tags: ["t2"]),
        Tx(id: "e3", merchant: "C", amount: -5, account: "a1", date: "2026-06-03", ledgerId: "l1", tags: nil),
        Tx(id: "e4", merchant: "D", amount: -5, account: "a1", date: "2026-06-04", ledgerId: "l1", tags: ["t1", "t2"]),
    ]

    func test_anyTag_default() {
        let out = Selectors.selectTransactions(txns, ListOptions(ledgerId: "l1", tagIds: ["t1", "t2"]))
        XCTAssertEqual(Set(out.map(\.id)), ["e1", "e2", "e4"])   // any of t1/t2
    }

    func test_allTags() {
        let out = Selectors.selectTransactions(txns, ListOptions(ledgerId: "l1", tagIds: ["t1", "t2"], tagsMatchAll: true))
        XCTAssertEqual(out.map(\.id), ["e4"])                    // both t1 AND t2
    }

    func test_noTagFilter_unchanged() {
        let out = Selectors.selectTransactions(txns, ListOptions(ledgerId: "l1"))
        XCTAssertEqual(Set(out.map(\.id)), ["e1", "e2", "e3", "e4"])
    }
}
