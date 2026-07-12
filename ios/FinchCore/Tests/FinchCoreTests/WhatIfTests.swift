import XCTest
@testable import FinchCore

final class WhatIfTests: XCTestCase {
    private func tx(_ id: String, _ amount: Double, _ date: String,
                    cat: String? = "food", kind: String = "expense",
                    pending: Bool = false, ledger: String = "personal") -> Tx {
        Tx(id: id, merchant: "m", category: cat, amount: amount, account: "cc", date: date,
           pending: pending, ledgerId: ledger, kind: kind)
    }

    func test_averagesOverTrailingCompleteMonths() {
        let txns = [
            tx("1", -999, "2026-05-03"),                          // partial anchor month — excluded
            tx("2", -90, "2026-04-10"),
            tx("3", -30, "2026-04-12", cat: "transport"),
            tx("4", -110, "2026-03-15"),
            tx("5", 500, "2026-03-20", cat: "salary", kind: "income"),
        ]
        let b = Selectors.whatIfBaseline(txns, "personal", "2026-05")!
        XCTAssertEqual(b.months, ["2026-03", "2026-04"])
        XCTAssertEqual(b.categories[0], .init(categoryId: "food", avgMonthly: 100))      // (110+90)/2
        XCTAssertEqual(b.categories[1], .init(categoryId: "transport", avgMonthly: 15))  // 30/2
        XCTAssertEqual(b.avgSpend, 115)      // (110+90+30)/2
        XCTAssertEqual(b.avgIncome, 250)     // 500/2
    }

    func test_fallsBackToAnchorMonthWhenNoCompleteMonthHasSpend() {
        let b = Selectors.whatIfBaseline([tx("1", -80, "2026-05-03")], "personal", "2026-05")!
        XCTAssertEqual(b.months, ["2026-05"])
        XCTAssertEqual(b.categories, [.init(categoryId: "food", avgMonthly: 80)])
    }

    func test_nilWithoutSpend_pendingAndOtherLedgersIgnored() {
        XCTAssertNil(Selectors.whatIfBaseline([], "personal", "2026-05"))
        XCTAssertNil(Selectors.whatIfBaseline([tx("1", -10, "2026-04-10", pending: true)], "personal", "2026-05"))
        XCTAssertNil(Selectors.whatIfBaseline([tx("1", -10, "2026-04-10", ledger: "family")], "personal", "2026-05"))
        XCTAssertNil(Selectors.whatIfBaseline(
            [tx("1", 100, "2026-04-02", cat: "salary", kind: "income")], "personal", "2026-05"))
    }

    func test_topNCapSortedDesc_refundsNetAgainstSpend() {
        var txns: [Tx] = []
        for (i, cat) in ["a", "b", "c", "d", "e", "f"].enumerated() {
            txns.append(tx("c\(i)", Double(-(600 - i * 100)), "2026-04-05", cat: cat))   // a:600 … f:100
        }
        txns.append(tx("r", 50, "2026-04-20", cat: "a", kind: "refund"))                  // nets a → 550
        let b = Selectors.whatIfBaseline(txns, "personal", "2026-05", topN: 5)!
        XCTAssertEqual(b.categories.count, 5)
        XCTAssertEqual(b.categories.first, .init(categoryId: "a", avgMonthly: 550))
        XCTAssertEqual(b.categories.map(\.categoryId), ["a", "b", "c", "d", "e"])         // f (100) dropped
    }
}
