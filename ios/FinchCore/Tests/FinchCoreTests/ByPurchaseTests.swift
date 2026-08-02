import XCTest
@testable import FinchCore

/// The two primitives every counting fix is built on.
///
/// `purchaseKey` groups a purchase's payment legs; `byPurchase` collapses them
/// into one row carrying the true total. Sites that only count use the first;
/// sites computing a mean, a variance, a z-score or a "biggest" need the second,
/// because a leg's amount is a fraction of what was actually spent.
final class ByPurchaseTests: XCTestCase {

    private func tx(_ id: String, _ entry: String?, _ amount: Double,
                    account: String = "a1", currency: String? = nil,
                    native: Double? = nil, splits: [TxSplit]? = nil) -> Tx {
        Tx(id: id, merchant: "Market", amount: amount, account: account,
           date: "2026-05-14", currency: currency, nativeAmount: native,
           entryId: entry, splits: splits)
    }

    func test_purchaseKey_groupsLegsOfOnePurchase_andSeparatesDistinctOnes() {
        let a = tx("p1", "e1", -120), b = tx("p2", "e1", -80), c = tx("p3", "e2", -50)
        XCTAssertEqual(Set([a, b, c].map(\.purchaseKey)).count, 2, "two purchases, three payment legs")
        XCTAssertEqual(a.purchaseKey, b.purchaseKey)
        XCTAssertNotEqual(a.purchaseKey, c.purchaseKey)
    }

    /// A row whose `entryId` is absent — an older parity fixture, say — must
    /// degrade to counting itself, which is the pre-fix behaviour, rather than
    /// collapsing every such row together under a shared nil key.
    func test_purchaseKey_fallsBackToPostingId_whenEntryIdIsMissing() {
        let one = tx("p9", nil, -10), two = tx("p10", nil, -20)
        XCTAssertEqual(one.purchaseKey, "p9")
        XCTAssertEqual(Set([one, two].map(\.purchaseKey)).count, 2, "must not all collapse under nil")
    }

    func test_byPurchase_sumsPaymentLegsIntoOneRow() {
        let out = Selectors.byPurchase([tx("p1", "e1", -120), tx("p2", "e1", -80, account: "a2")])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].amount, -200, accuracy: 0.001, "the purchase, not a leg")
    }

    func test_byPurchase_isIdentityForOrdinarySingleLegRows() {
        let c = tx("p3", "e2", -50)
        XCTAssertEqual(Selectors.byPurchase([c]), [c], "must not perturb the ordinary case")
    }

    /// `categorySpend` reads `t.splits` in preference to `t.category`, so losing
    /// them here would silently re-attribute a category-split purchase to its
    /// dominant category alone. One row in, one row out — but the splits have to
    /// survive the trip.
    func test_byPurchase_preservesSplitsOnACategorySplitPurchase() {
        let s = [TxSplit(id: "c1p", categoryId: "c1", amount: 70, amountBase: 70, description: nil),
                 TxSplit(id: "c2p", categoryId: "c2", amount: 30, amountBase: 30, description: nil)]
        let out = Selectors.byPurchase([tx("p1", "e1", -100, splits: s)])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].splits?.count, 2, "a category split must survive collapsing")
    }

    /// Split tender is explicitly multi-currency, and the consumers all read
    /// `abs(nativeAmount ?? amount)`. Summing raw natives across currencies would
    /// hand them a number that is not money in any unit — worse than the base
    /// amount they would otherwise fall back to.
    func test_byPurchase_dropsNativeAmount_whenLegCurrenciesDiffer() {
        let out = Selectors.byPurchase([
            tx("p1", "e1", -60, currency: "EUR", native: -55),
            tx("p2", "e1", -40, account: "a2", currency: "USD", native: -40),
        ])
        XCTAssertEqual(out.count, 1)
        XCTAssertNil(out[0].nativeAmount, "EUR + USD is not a number")
        XCTAssertNil(out[0].currency, "and no single currency describes the result")
        XCTAssertEqual(out[0].amount, -100, accuracy: 0.001, "the base total still holds")
    }

    func test_byPurchase_keepsNativeAmount_whenLegsShareACurrency() {
        let out = Selectors.byPurchase([
            tx("p1", "e1", -60, currency: "EUR", native: -55),
            tx("p2", "e1", -40, account: "a2", currency: "EUR", native: -37),
        ])
        XCTAssertEqual(out[0].nativeAmount ?? 0, -92, accuracy: 0.001, "one currency, so the native total is real")
        XCTAssertEqual(out[0].currency, "EUR")
    }
}
