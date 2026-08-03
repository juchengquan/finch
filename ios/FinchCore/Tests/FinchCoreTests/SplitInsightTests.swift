import XCTest
@testable import FinchCore

/// The insight, digest and duplicate-check surfaces, which counted `Tx` rows as
/// transactions the same way the selectors did — plus two that go further wrong:
/// "biggest expense" ranked a leg against a whole purchase, and the duplicate
/// warning never fired for a split purchase at all.
final class SplitInsightTests: XCTestCase {

    private func leg(_ id: String, _ entry: String, _ amount: Double, account: String,
                     merchant: String = "Market", category: String? = "c1",
                     date: String = "2026-05-14", pending: Bool = false) -> Tx {
        Tx(id: id, merchant: merchant, category: category, amount: amount, account: account,
           date: date, pending: pending, ledgerId: "l1", kind: "expense", entryId: entry)
    }

    /// A $200 purchase paid $120 + $80, against an unsplit $150. The margins
    /// matter: each leg alone ($120, $80) loses to $150, so before the fix the
    /// smaller purchase won "biggest". Only a purchase-sized comparison gets it
    /// right, which is what makes this the adversarial case rather than a split
    /// that would have won either way.
    func test_weeklyDigest_countsPurchases_andRanksTheWholePurchaseAsBiggest() {
        let txns = [
            leg("p1", "e1", -120, account: "a1"),
            leg("p2", "e1", -80, account: "a2"),
            leg("p3", "e2", -150, account: "a1", merchant: "Sofa"),
        ]
        let digest = try! XCTUnwrap(Selectors.weeklyDigest(txns, "l1", "2026-05-20"))
        XCTAssertEqual(digest.txCount, 2, "two purchases, not three payment legs")
        XCTAssertEqual(digest.spent, 350, accuracy: 0.001, "the total was always right and must stay right")
        XCTAssertEqual(digest.biggestExpense?.merchant, "Market", "a $200 purchase outranks a $150 one")
        XCTAssertEqual(digest.biggestExpense?.amount ?? 0, 200, accuracy: 0.001, "at its true size")
    }

    /// A habitually-split merchant otherwise gets double weight in the vote.
    func test_suggestCategory_weighsAPurchaseOnce() {
        let txns = [
            leg("p1", "e1", -60, account: "a1", category: "food"),
            leg("p2", "e1", -40, account: "a2", category: "food"),
            leg("p3", "e2", -50, account: "a1", category: "shop"),
        ]
        let s = try! XCTUnwrap(Selectors.suggestCategory(txns, "l1", "Market"))
        XCTAssertEqual(s.count, 1, "the split purchase votes once")
        XCTAssertEqual(s.confidence, 0.5, accuracy: 0.001, "one vote each, so it is a tie — not 2:1")
    }

    func test_pendingInsight_countsPurchases() {
        let txns = [
            leg("p1", "e1", -60, account: "a1", pending: true),
            leg("p2", "e1", -40, account: "a2", pending: true),
        ]
        let insights = Selectors.generateInsights(InsightContext(
            txns: txns, accounts: [], budgets: [], categories: [],
            ledgerId: "l1", month: "2026-05", today: "2026-05-20"), fmt: { "$\($0)" })
        let pending = insights.first { $0.title.contains("pending to review") }
        XCTAssertEqual(pending?.title, "1 pending to review", "one purchase awaits confirmation, not two payments")
    }

    /// The Watch can only write a single-card transaction, so a purchase paid on
    /// two cards cannot be repeated in one tap. Offering it twice ate two of three
    /// slots; offering it once would silently book the whole amount to one card.
    func test_recentExpenses_omitsSplitPurchasesEntirely() {
        var split1 = leg("p1", "e1", -60, account: "a1"); split1.accountLegCount = 2
        var split2 = leg("p2", "e1", -40, account: "a2"); split2.accountLegCount = 2
        var plain = leg("p3", "e2", -4, account: "a1", merchant: "Coffee"); plain.accountLegCount = 1
        let out = Selectors.recentExpenses([split1, split2, plain], "l1", 3)
        XCTAssertEqual(out.map(\.merchant), ["Coffee"], "no shortcut for a purchase a shortcut cannot make")
    }

    /// Re-adding a purchase that already exists as two payments got no warning at
    /// all, because the check compared the draft against a single leg.
    func test_findDuplicate_matchesAPurchaseByItsTotal_onAnyPayingCard() {
        let existing = [leg("p1", "e1", -60, account: "a1"), leg("p2", "e1", -40, account: "a2")]

        let onFirstCard = Selectors.findDuplicate(existing, "l1", DuplicateDraft(
            merchant: "Market", amount: -100, accountId: "a1", date: "2026-05-14", excludeId: nil))
        XCTAssertNotNil(onFirstCard, "a $100 Market purchase already exists as $60 + $40")

        let onSecondCard = Selectors.findDuplicate(existing, "l1", DuplicateDraft(
            merchant: "Market", amount: -100, accountId: "a2", date: "2026-05-14", excludeId: nil))
        XCTAssertNotNil(onSecondCard, "either paying card counts — a split has no single account")

        let unrelatedCard = Selectors.findDuplicate(existing, "l1", DuplicateDraft(
            merchant: "Market", amount: -100, accountId: "a9", date: "2026-05-14", excludeId: nil))
        XCTAssertNil(unrelatedCard, "a card that paid nothing towards it is not a match")

        let justALeg = Selectors.findDuplicate(existing, "l1", DuplicateDraft(
            merchant: "Market", amount: -60, accountId: "a1", date: "2026-05-14", excludeId: nil))
        XCTAssertNil(justALeg, "$60 is a payment, not the purchase — not the same thing")
    }

    /// Editing one leg of a split must not make the sheet warn about the purchase
    /// being edited. `excludeId` arrives as a posting id, so it has to exclude the
    /// whole purchase, not just that one row.
    func test_findDuplicate_excludesTheWholePurchaseBeingEdited() {
        let existing = [leg("p1", "e1", -60, account: "a1"), leg("p2", "e1", -40, account: "a2")]
        let m = Selectors.findDuplicate(existing, "l1", DuplicateDraft(
            merchant: "Market", amount: -100, accountId: "a1", date: "2026-05-14", excludeId: "p2"))
        XCTAssertNil(m, "excluding any leg excludes the purchase it belongs to")
    }
}
