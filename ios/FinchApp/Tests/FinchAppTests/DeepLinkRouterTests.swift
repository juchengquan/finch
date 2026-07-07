import XCTest
@testable import FinchApp

@MainActor
final class DeepLinkRouterTests: XCTestCase {
    func test_handle_add_url_sets_showAddTransaction() {
        let r = DeepLinkRouter()
        XCTAssertFalse(r.showAddTransaction)
        r.handle(URL(string: "finch://add")!)
        XCTAssertTrue(r.showAddTransaction)
    }

    func test_handle_unknown_url_is_ignored() {
        let r = DeepLinkRouter()
        r.handle(URL(string: "finch://bogus")!)
        XCTAssertFalse(r.showAddTransaction)
    }

    func test_handle_add_url_with_account_prefills() {
        let r = DeepLinkRouter()
        r.handle(URL(string: "finch://add?account=a1")!)
        XCTAssertTrue(r.showAddTransaction)
        XCTAssertEqual(r.pendingAddAccountId, "a1")
    }

    func test_handle_plain_add_clears_stale_prefill() {
        let r = DeepLinkRouter()
        r.handle(URL(string: "finch://add?account=a1")!)
        r.handle(URL(string: "finch://add")!)
        XCTAssertTrue(r.showAddTransaction)
        XCTAssertNil(r.pendingAddAccountId)
    }

    func test_defaultTabIsAccounts() {
        XCTAssertEqual(DeepLinkRouter().selectedTab, .accounts)
    }

    func test_ledgerRouteFlagDefaultsOff() {
        XCTAssertFalse(DeepLinkRouter().showLedger)
    }
}
