import XCTest
@testable import FinchApp

final class AccountGroupCollapseTests: XCTestCase {
    private let suite = "test.AccountGroupCollapse"
    private let lg = "l1"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func test_defaultIsExpanded() {
        XCTAssertTrue(AccountGroupCollapse.collapsed(ledger: lg, defaults).isEmpty)
        XCTAssertFalse(AccountGroupCollapse.isCollapsed("Savings", ledger: lg, defaults))
    }

    func test_setCollapsedTrue() {
        AccountGroupCollapse.setCollapsed("Savings", true, ledger: lg, defaults)
        XCTAssertTrue(AccountGroupCollapse.isCollapsed("Savings", ledger: lg, defaults))
        XCTAssertEqual(AccountGroupCollapse.collapsed(ledger: lg, defaults), ["Savings"])
    }

    func test_setCollapsedFalseRemoves() {
        AccountGroupCollapse.setCollapsed("Savings", true, ledger: lg, defaults)
        AccountGroupCollapse.setCollapsed("Savings", false, ledger: lg, defaults)
        XCTAssertFalse(AccountGroupCollapse.isCollapsed("Savings", ledger: lg, defaults))
        XCTAssertTrue(AccountGroupCollapse.collapsed(ledger: lg, defaults).isEmpty)
    }

    func test_multipleGroupsIndependent() {
        AccountGroupCollapse.setCollapsed("A", true, ledger: lg, defaults)
        AccountGroupCollapse.setCollapsed("B", true, ledger: lg, defaults)
        AccountGroupCollapse.setCollapsed("A", false, ledger: lg, defaults)
        XCTAssertFalse(AccountGroupCollapse.isCollapsed("A", ledger: lg, defaults))
        XCTAssertTrue(AccountGroupCollapse.isCollapsed("B", ledger: lg, defaults))
    }

    func test_setCollapsedTrueIdempotent() {
        AccountGroupCollapse.setCollapsed("A", true, ledger: lg, defaults)
        AccountGroupCollapse.setCollapsed("A", true, ledger: lg, defaults)
        XCTAssertEqual(AccountGroupCollapse.collapsed(ledger: lg, defaults), ["A"])
    }

    func test_perLedgerIsolation() {   // same group name, different ledgers — independent
        AccountGroupCollapse.setCollapsed("Savings", true, ledger: "l1", defaults)
        XCTAssertTrue(AccountGroupCollapse.isCollapsed("Savings", ledger: "l1", defaults))
        XCTAssertFalse(AccountGroupCollapse.isCollapsed("Savings", ledger: "l2", defaults))
    }
}
