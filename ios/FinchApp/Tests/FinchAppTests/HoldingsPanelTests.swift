import XCTest
import FinchCore
@testable import FinchApp

/// The rule deciding when an account screen shows investment positions.
///
/// Worth its own tests because it is the one piece of this feature that two screens
/// share, and because two of the four cases are the reason the rule is not simply
/// "is it an investment account" — the shape the web uses.
final class HoldingsPanelTests: XCTestCase {

    // MARK: visibility

    func testInvestmentAccountShowsThePanelWithNoPositions() {
        // The load-bearing case. The Add row lives INSIDE this section, so hiding the
        // section on an empty investment account leaves no way to add a first position
        // — the feature would be unreachable on exactly the accounts that need it.
        XCTAssertTrue(HoldingsPanel.isVisible(accountType: "investment", hasHoldings: false))
    }

    func testInvestmentAccountShowsThePanelWithPositions() {
        XCTAssertTrue(HoldingsPanel.isVisible(accountType: "investment", hasHoldings: true))
    }

    func testNonInvestmentAccountCarryingPositionsStillShowsThem() {
        // Reachable: two schema triggers stop holdings being ADDED to a non-investment
        // account, but nothing stops `updateAccount` changing the type out from under
        // existing ones. A type-only gate would strand those rows — visible nowhere,
        // deletable nowhere. This is the case the web gets wrong.
        XCTAssertTrue(HoldingsPanel.isVisible(accountType: "cash", hasHoldings: true))
    }

    func testOrdinaryAccountHasNoPanel() {
        for type in ["savings", "credit_card", "cash", "fx", "virtual"] {
            XCTAssertFalse(HoldingsPanel.isVisible(accountType: type, hasHoldings: false),
                           "\(type) with no positions should not show a Holdings section")
        }
    }

    func testMissingTypeIsNotAnInvestmentAccount() {
        // `AccountRow.type` is optional; absent is not investment.
        XCTAssertFalse(HoldingsPanel.isVisible(accountType: nil, hasHoldings: false))
        XCTAssertFalse(HoldingsPanel.allowsAdding(accountType: nil))
        // ...but positions on it still surface, for the same reason as above.
        XCTAssertTrue(HoldingsPanel.isVisible(accountType: nil, hasHoldings: true))
    }

    // MARK: the Add row

    func testOnlyInvestmentAccountsOfferToAddAPosition() {
        XCTAssertTrue(HoldingsPanel.allowsAdding(accountType: "investment"))
        // The stranded-positions account shows what it has but must not offer to add:
        // `tr_holdings_investment_only_insert` would reject the write, so the row would
        // only ever produce an error alert.
        for type in ["savings", "credit_card", "cash", "fx", "virtual"] {
            XCTAssertFalse(HoldingsPanel.allowsAdding(accountType: type))
        }
    }

    // MARK: unrealized total

    func testUnrealizedTotalIsNilWhenNothingHasAPrice() throws {
        // Not zero — a zero would read as "you are exactly even", which is a claim the
        // data cannot support. The caller drops the line instead.
        XCTAssertNil(HoldingsPanel.unrealizedTotal([try holding(shares: 10, cost: 1_000, price: nil)]))
        XCTAssertNil(HoldingsPanel.unrealizedTotal([]))
    }

    func testUnrealizedTotalSumsOnlyThePricedPositions() throws {
        let priced = try holding(id: "h1", shares: 10, cost: 1_000, price: 150)  // 1500 - 1000 = +500
        let unpriced = try holding(id: "h2", shares: 5, cost: 900, price: nil)   // no gain/loss
        let total = HoldingsPanel.unrealizedTotal([priced, unpriced])
        XCTAssertEqual(try XCTUnwrap(total), 500, accuracy: 0.001)
    }

    func testUnrealizedTotalGoesNegativeOnALoss() throws {
        let loser = try holding(shares: 10, cost: 2_000, price: 150)             // 1500 - 2000 = -500
        XCTAssertEqual(try XCTUnwrap(HoldingsPanel.unrealizedTotal([loser])), -500, accuracy: 0.001)
    }

    // MARK: helper

    /// `Holding`'s memberwise init is internal to `FinchCore`, so build one the way the
    /// app itself does — decoded. `Codable` is part of its public surface.
    private func holding(id: String = "h", shares: Double, cost: Double, price: Double?) throws -> Holding {
        var obj: [String: Any] = [
            "id": id, "ledgerId": "l1", "accountId": "a1", "symbol": "VTI",
            "shares": shares, "costBasis": cost, "currency": "USD",
        ]
        if let price {
            obj["lastPrice"] = price
            obj["lastPriceDate"] = "2026-08-08"
        }
        return try JSONDecoder().decode(
            Holding.self, from: JSONSerialization.data(withJSONObject: obj))
    }
}
