import XCTest
@testable import FinchCore

final class SelectTransactionsTagTests: XCTestCase {
    private let txns = [
        Tx(id: "e1", merchant: "A", amount: -5, account: "a1", date: "2026-06-01", ledgerId: "l1", tags: ["t1"]),
        Tx(id: "e2", merchant: "B", amount: -5, account: "a1", date: "2026-06-02", ledgerId: "l1", tags: ["t2"]),
        Tx(id: "e3", merchant: "C", amount: -5, account: "a1", date: "2026-06-03", ledgerId: "l1", tags: nil),
    ]

    func test_tagFilter_keepsOnlyTagged() {
        let out = Selectors.selectTransactions(txns, ListOptions(ledgerId: "l1", tagId: "t1"))
        XCTAssertEqual(out.map(\.id), ["e1"])
    }

    func test_noTagFilter_unchanged() {
        let out = Selectors.selectTransactions(txns, ListOptions(ledgerId: "l1"))
        XCTAssertEqual(Set(out.map(\.id)), ["e1", "e2", "e3"])
    }
}
