import XCTest
@testable import FinchCore

/// `query` matching widened beyond the merchant text to what the feed row
/// displays: category title (incl. split categories) and tag names, via the
/// optional id→name lookups. Mirrors the web's lib/select.test.ts cases.
final class SelectTransactionsQueryTests: XCTestCase {
    private let categoryNames = ["food": "Groceries", "fun": "Entertainment"]
    private let tagNames = ["t1": "vacation"]

    private var txns: [Tx] {
        [
            Tx(id: "byMerchant", merchant: "Grocer Joe", category: nil, amount: -5, account: "a1", date: "2026-06-01", ledgerId: "l1"),
            Tx(id: "byCategory", merchant: "", category: "food", amount: -5, account: "a1", date: "2026-06-02", ledgerId: "l1"),
            Tx(id: "bySplit", merchant: "", category: nil, amount: -5, account: "a1", date: "2026-06-03", ledgerId: "l1",
               splits: [TxSplit(id: "s1", categoryId: "food", amount: -5, amountBase: -5, description: nil)]),
            Tx(id: "byTag", merchant: "", category: "fun", amount: -5, account: "a1", date: "2026-06-04", ledgerId: "l1", tags: ["t1"]),
            Tx(id: "noMatch", merchant: "Cafe", category: "fun", amount: -5, account: "a1", date: "2026-06-05", ledgerId: "l1"),
        ]
    }

    func test_query_matchesMerchantCategoryAndSplit() {
        let out = Selectors.selectTransactions(txns, ListOptions(ledgerId: "l1", query: "gro"),
                                               categoryNames: categoryNames, tagNames: tagNames)
        XCTAssertEqual(Set(out.map(\.id)), ["byMerchant", "byCategory", "bySplit"])
    }

    func test_query_matchesTagName() {
        let out = Selectors.selectTransactions(txns, ListOptions(ledgerId: "l1", query: "vac"),
                                               categoryNames: categoryNames, tagNames: tagNames)
        XCTAssertEqual(out.map(\.id), ["byTag"])
    }

    func test_query_caseInsensitive() {
        let out = Selectors.selectTransactions(txns, ListOptions(ledgerId: "l1", query: "GROCERIES"),
                                               categoryNames: categoryNames, tagNames: tagNames)
        XCTAssertEqual(Set(out.map(\.id)), ["byCategory", "bySplit"])
    }

    func test_query_withoutNameMaps_staysMerchantOnly() {
        let out = Selectors.selectTransactions(txns, ListOptions(ledgerId: "l1", query: "gro"))
        XCTAssertEqual(out.map(\.id), ["byMerchant"])
    }
}
