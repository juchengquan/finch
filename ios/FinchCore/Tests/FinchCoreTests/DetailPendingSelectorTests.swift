import XCTest
@testable import FinchCore

/// The three "entity → its transactions" selectors behind the Category / Tag /
/// Merchant detail pages. They used to DISAGREE about pending: category and tag
/// excluded it, merchant included it — so the merchant detail list and its Total
/// counted pending while the Merchants page pill (counterpartyTxCounts, which is
/// documented non-pending) did not. All three now exclude by default and take an
/// explicit opt-in, used to surface pending in its own "To confirm" section.
final class DetailPendingSelectorTests: XCTestCase {

    private let cps = [Counterparty(id: "cp1", name: "Starbucks", isVerified: false)]

    private func txns() -> [Tx] {
        [
            Tx(id: "confirmed", merchant: "Starbucks", category: "cat1", amount: -5, account: "a1",
               date: "2026-06-01", pending: false, ledgerId: "l1", counterpartyId: "cp1", tags: ["tag1"]),
            Tx(id: "pending", merchant: "Starbucks", category: "cat1", amount: -7, account: "a1",
               date: "2026-06-02", pending: true, ledgerId: "l1", counterpartyId: "cp1", tags: ["tag1"]),
        ]
    }

    func test_allThreeExcludePendingByDefault() {
        let t = txns()
        XCTAssertEqual(Selectors.categoryTransactions(t, "cat1", "l1").map(\.id), ["confirmed"])
        XCTAssertEqual(Selectors.tagTransactions(t, "tag1", "l1").map(\.id), ["confirmed"])
        XCTAssertEqual(Selectors.merchantTransactions(t, cps, "cp1", "l1").map(\.id), ["confirmed"],
                       "merchant used to include pending here — that was the inconsistency")
    }

    func test_allThreeIncludePendingWhenAskedTo() {
        let t = txns()
        // newest-first, so the pending 06-02 row leads
        XCTAssertEqual(Selectors.categoryTransactions(t, "cat1", "l1", includePending: true).map(\.id),
                       ["pending", "confirmed"])
        XCTAssertEqual(Selectors.tagTransactions(t, "tag1", "l1", includePending: true).map(\.id),
                       ["pending", "confirmed"])
        XCTAssertEqual(Selectors.merchantTransactions(t, cps, "cp1", "l1", includePending: true).map(\.id),
                       ["pending", "confirmed"])
    }

    /// The merchant list must now agree with the pill on the Merchants page.
    func test_merchantListAgreesWithItsCountBadge() {
        let t = txns()
        let listed = Selectors.merchantTransactions(t, cps, "cp1", "l1").count
        let badge = Selectors.counterpartyTxCounts(t, cps, "l1")["cp1"] ?? 0
        XCTAssertEqual(listed, badge)
    }
}
