import XCTest
@testable import FinchCore

/// Six selectors that counted `Tx` rows as transactions. A purchase paid from
/// several accounts is several rows, so each of these counted it more than once —
/// and the two that compute statistics were wrong twice over, because a leg's
/// amount is a fraction of what was actually spent.
///
/// `anomalyScore` is deliberately absent: it takes a single `Tx` and cannot see
/// sibling legs, so it cannot score a purchase. Its callers are fixed instead.
final class SplitCountingSelectorTests: XCTestCase {

    /// One $100 purchase paid $60 + $40, plus one ordinary $50 purchase.
    private func splitPlusOrdinary(
        merchant: String = "Market", category: String = "c1",
        tags: [String]? = nil, rules: [String]? = nil, date: String = "2026-05-14"
    ) -> [Tx] {
        [Tx(id: "p1", merchant: merchant, category: category, amount: -60, account: "a1",
            date: date, ledgerId: "l1", kind: "expense", entryId: "e1",
            tags: tags, appliedRuleIds: rules),
         Tx(id: "p2", merchant: merchant, category: category, amount: -40, account: "a2",
            date: date, ledgerId: "l1", kind: "expense", entryId: "e1",
            tags: tags, appliedRuleIds: rules),
         Tx(id: "p3", merchant: merchant, category: category, amount: -50, account: "a1",
            date: date, ledgerId: "l1", kind: "expense", entryId: "e2",
            tags: tags, appliedRuleIds: rules)]
    }

    /// Wrong twice over: the count is inflated AND each leg's magnitude is a
    /// fraction of the purchase, so the mean and standard deviation are distorted
    /// rather than merely rescaled. This feeds the "Unusual transaction" alert.
    func test_merchantStats_countsPurchases_andAveragesTheirRealAmounts() {
        let stats = Selectors.merchantStats(splitPlusOrdinary(), "l1")
        let s = try! XCTUnwrap(stats.values.first)
        XCTAssertEqual(s.count, 2, "two purchases, not three payment legs")
        XCTAssertEqual(s.mean, 75, accuracy: 0.001, "mean of 100 and 50 — not of 60, 40 and 50")
    }

    func test_counterpartyTxCounts_countsPurchases() {
        let cp = Counterparty(id: "cp1", name: "Market", isVerified: false)
        let counts = Selectors.counterpartyTxCounts(splitPlusOrdinary(), [cp], "l1")
        XCTAssertEqual(counts["cp1"], 2, "used twice, not three times")
    }

    func test_tagTxCounts_countsPurchases() {
        let counts = Selectors.tagTxCounts(splitPlusOrdinary(tags: ["t1"]), "l1")
        XCTAssertEqual(counts["t1"], 2, "a tag is entry-level; both legs carry it")
    }

    func test_categoryTxCounts_countsPurchases() {
        let counts = Selectors.categoryTxCounts(splitPlusOrdinary(), "l1")
        XCTAssertEqual(counts["c1"], 2, "the split entry's legs share one category leg")
    }

    func test_ruleMatchCounts_countsPurchases() {
        let counts = Selectors.ruleMatchCounts(splitPlusOrdinary(rules: ["r1"]), "l1")
        XCTAssertEqual(counts["r1"], 2, "appliedRuleIds is entry-level, copied onto every leg")
    }

    /// The case where the bug HIDES a real result rather than inflating one: a
    /// subscription paid across two cards has its amount halved and its occurrence
    /// count doubled, so the reported charge is wrong even when it is still found.
    func test_detectRecurring_reportsTheWholeSubscription_notHalfOfIt() {
        var txns: [Tx] = []
        for (i, day) in ["2026-03-14", "2026-04-14", "2026-05-14"].enumerated() {
            txns.append(Tx(id: "a\(i)", merchant: "Streamly", category: "c1", amount: -30,
                           account: "a1", date: day, ledgerId: "l1", kind: "expense", entryId: "e\(i)"))
            txns.append(Tx(id: "b\(i)", merchant: "Streamly", category: "c1", amount: -20,
                           account: "a2", date: day, ledgerId: "l1", kind: "expense", entryId: "e\(i)"))
        }
        let found = Selectors.detectRecurring(txns, "l1", "2026-05-20")
        let charge = try! XCTUnwrap(found.first, "a monthly subscription must still be detected")
        XCTAssertEqual(charge.occurrences, 3, "three monthly charges, not six payment legs")
        XCTAssertEqual(charge.averageAmount, 50, accuracy: 0.001, "the subscription costs 50, not 25")
    }

    /// The idiom the six merge-impact functions use, pinned here because they are
    /// `private` to their views and cannot be called directly.
    ///
    /// "N transactions will be combined" sits on a destructive confirmation, and it
    /// deduplicated by `Tx.id` — a POSTING id — so a purchase paid on two cards was
    /// counted twice in the number shown before someone merged two categories.
    func test_mergeImpactIdiom_dedupesByPurchase_notByPosting() {
        let txns = splitPlusOrdinary(category: "c1")
        let keys = Set(Selectors.categoryTransactions(txns, "c1", "l1").map(\.purchaseKey))
        XCTAssertEqual(keys.count, 2, "two purchases behind three payment rows")

        let byPostingId = Set(Selectors.categoryTransactions(txns, "c1", "l1").map(\.id))
        XCTAssertEqual(byPostingId.count, 3, "…which is what the posting-id version counted")
    }
}
