import XCTest
import FinchCore
@testable import FinchApp

/// `accountSplitArgs` is the boundary where `SplitAllocation`'s always-positive
/// row magnitudes become the SIGNED, explicitly-currencied `accounts` args the
/// engine actually reads. Both bugs this guards against only showed up in the
/// ARGS the sheet builds — `SplitAllocationTests` never touches a sign or a
/// currency key, which is exactly how a reviewer caught what testing the model
/// instead of the payload let through.
final class AccountSplitArgsTests: XCTestCase {

    private func twoFundedRows(_ a: Double, _ b: Double, total: Double) -> SplitAllocation {
        var alloc = SplitAllocation(total: total)
        alloc.tick("a2")
        alloc.tick("a1")
        alloc.setAmount("a2", a)
        alloc.setAmount("a1", b)
        return alloc
    }

    private func shareAmounts(_ args: [String: JSONValue]) -> [Double] {
        guard case .array(let shares)? = args["accounts"] else { return [] }
        return shares.compactMap {
            guard case .object(let o) = $0, case .double(let amt)? = o["amount"] else { return nil }
            return amt
        }
    }

    /// THE regression this guards: an expense's `signed` amount is NEGATIVE, and
    /// the engine compares the accounts' sum against it directly (both
    /// sign-preserving through `convertToBase`) — an unsigned share sent
    /// alongside a negative `amount` fails that comparison for every expense
    /// split. Shape matches the engine's own test data
    /// (`MultiAccountAddTests.swift:20-26`): a $100 expense split -60/-40.
    func test_expenseSplit_emitsNegativeSharesSummingToTheSignedAmount() {
        let alloc = twoFundedRows(60, 40, total: 100)
        let args = AddTransactionSheet.accountSplitArgs(accountAlloc: alloc, signed: -100, currency: "USD")
        let amounts = shareAmounts(args)
        XCTAssertEqual(amounts.count, 2)
        XCTAssertTrue(amounts.allSatisfy { $0 < 0 }, "every share must be negative for an expense, got \(amounts)")
        XCTAssertEqual(amounts.reduce(0, +), -100, accuracy: 0.0001)
    }

    /// Income and refund pass a POSITIVE `signed` amount — shares must follow.
    func test_incomeOrRefundSplit_emitsPositiveShares() {
        let alloc = twoFundedRows(60, 40, total: 100)
        let args = AddTransactionSheet.accountSplitArgs(accountAlloc: alloc, signed: 100, currency: "USD")
        let amounts = shareAmounts(args)
        XCTAssertEqual(amounts.count, 2)
        XCTAssertTrue(amounts.allSatisfy { $0 > 0 }, "every share must be positive for income/refund, got \(amounts)")
        XCTAssertEqual(amounts.reduce(0, +), 100, accuracy: 0.0001)
    }

    /// The engine defaults an OMITTED `currency` to the ledger BASE — wrong the
    /// moment the transaction's own currency differs from base. `currency` must
    /// ride along whenever `accounts` does, not just when it differs from the
    /// single account's own currency (the rule the non-split path uses).
    func test_currencyIsAlwaysPresentWhenSplitting() {
        let alloc = twoFundedRows(60, 40, total: 100)
        let args = AddTransactionSheet.accountSplitArgs(accountAlloc: alloc, signed: -100, currency: "EUR")
        XCTAssertEqual(args["currency"], .string("EUR"))
    }

    /// One funded row is not a split — the plain `accountId` above already
    /// carries it, so neither `accounts` nor `currency` should appear.
    func test_oneFundedRow_yieldsNoArgs() {
        var alloc = SplitAllocation(total: 100)
        alloc.tick("a1")
        let args = AddTransactionSheet.accountSplitArgs(accountAlloc: alloc, signed: -100, currency: "USD")
        XCTAssertTrue(args.isEmpty)
    }

    /// The accountId each share carries must survive unchanged — only the sign
    /// of the amount is a function of this boundary.
    func test_accountIdsRideAlongWithSignedAmounts() {
        let alloc = twoFundedRows(60, 40, total: 100)
        let args = AddTransactionSheet.accountSplitArgs(accountAlloc: alloc, signed: -100, currency: "USD")
        guard case .array(let shares)? = args["accounts"] else { return XCTFail("accounts missing") }
        let ids = Set(shares.compactMap { share -> String? in
            guard case .object(let o) = share, case .string(let id)? = o["accountId"] else { return nil }
            return id
        })
        XCTAssertEqual(ids, ["a1", "a2"])
    }
}
