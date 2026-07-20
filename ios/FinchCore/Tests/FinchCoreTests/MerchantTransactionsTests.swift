import XCTest
@testable import FinchCore

final class MerchantTransactionsTests: XCTestCase {
    private let cps = [
        Counterparty(id: "cp1", name: "Starbucks", isVerified: false),
        Counterparty(id: "cp2", name: "Other", isVerified: false),
    ]
    private let txns = [
        Tx(id: "a", merchant: "Starbucks", amount: -5, account: "a1", date: "2026-06-01", ledgerId: "l1", counterpartyId: "cp1"), // linked
        Tx(id: "b", merchant: "starbucks", amount: -6, account: "a1", date: "2026-06-03", ledgerId: "l1"),                         // name match
        Tx(id: "c", merchant: "Starbucks", amount: -7, account: "a1", date: "2026-06-02", ledgerId: "l1", counterpartyId: "cp2"), // linked elsewhere
        Tx(id: "d", merchant: "Starbucks", amount: -8, account: "a1", date: "2026-06-04", ledgerId: "l2"),                         // other ledger
    ]

    func test_matchesByIdAndName_excludesOthers_newestFirst() {
        let out = Selectors.merchantTransactions(txns, cps, "cp1", "l1")
        XCTAssertEqual(out.map(\.id), ["b", "a"])   // date-desc: 06-03 then 06-01; c (cp2) + d (l2) excluded
    }
}
