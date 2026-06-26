import XCTest
@testable import FinchCore

final class LedgerNetWorthTests: XCTestCase {
    private func acct(_ id: String, _ bal: Double, ledger: String, ccy: String = "USD",
                      inNW: Int = 1, active: Bool = true) -> AccountRow {
        AccountRow(id: id, balance: bal, ledgerId: ledger, currency: ccy,
                   includeInNetWorth: inNW, isActive: active)
    }

    func test_sumsOnlyEligibleAccountsForTheLedger() {
        let accounts = [
            acct("a", 100, ledger: "L1"),
            acct("b", 250, ledger: "L1"),
            acct("c", 999, ledger: "L2"),            // other ledger — excluded
            acct("d", 500, ledger: "L1", inNW: 0),   // excluded from net worth
            acct("e", 500, ledger: "L1", active: false), // archived — excluded
        ]
        XCTAssertEqual(Selectors.ledgerNetWorth(accounts, "L1"), 350, accuracy: 0.001)
    }

    func test_appliesToBaseConversion() {
        let accounts = [acct("a", 100, ledger: "L1", ccy: "EUR")]
        // toBase doubles EUR balances
        let nw = Selectors.ledgerNetWorth(accounts, "L1") { amt, ccy in ccy == "EUR" ? amt * 2 : amt }
        XCTAssertEqual(nw, 200, accuracy: 0.001)
    }
}
