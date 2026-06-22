import XCTest
@testable import FinchApp

final class BudgetGroupCollapseTests: XCTestCase {
    private let suite = "test.BudgetGroupCollapse"
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
        XCTAssertTrue(BudgetGroupCollapse.collapsed(ledger: lg, defaults).isEmpty)
        XCTAssertFalse(BudgetGroupCollapse.isCollapsed("Bills", ledger: lg, defaults))
    }

    func test_setCollapsedTrue() {
        BudgetGroupCollapse.setCollapsed("Bills", true, ledger: lg, defaults)
        XCTAssertTrue(BudgetGroupCollapse.isCollapsed("Bills", ledger: lg, defaults))
        XCTAssertEqual(BudgetGroupCollapse.collapsed(ledger: lg, defaults), ["Bills"])
    }

    func test_setCollapsedFalseRemoves() {
        BudgetGroupCollapse.setCollapsed("Bills", true, ledger: lg, defaults)
        BudgetGroupCollapse.setCollapsed("Bills", false, ledger: lg, defaults)
        XCTAssertFalse(BudgetGroupCollapse.isCollapsed("Bills", ledger: lg, defaults))
        XCTAssertTrue(BudgetGroupCollapse.collapsed(ledger: lg, defaults).isEmpty)
    }

    func test_multipleGroupsIndependent() {
        BudgetGroupCollapse.setCollapsed("A", true, ledger: lg, defaults)
        BudgetGroupCollapse.setCollapsed("B", true, ledger: lg, defaults)
        BudgetGroupCollapse.setCollapsed("A", false, ledger: lg, defaults)
        XCTAssertFalse(BudgetGroupCollapse.isCollapsed("A", ledger: lg, defaults))
        XCTAssertTrue(BudgetGroupCollapse.isCollapsed("B", ledger: lg, defaults))
    }

    func test_setCollapsedTrueIdempotent() {
        BudgetGroupCollapse.setCollapsed("A", true, ledger: lg, defaults)
        BudgetGroupCollapse.setCollapsed("A", true, ledger: lg, defaults)
        XCTAssertEqual(BudgetGroupCollapse.collapsed(ledger: lg, defaults), ["A"])
    }

    func test_perLedgerIsolation() {   // same group name, different ledgers — independent
        BudgetGroupCollapse.setCollapsed("Bills", true, ledger: "l1", defaults)
        XCTAssertTrue(BudgetGroupCollapse.isCollapsed("Bills", ledger: "l1", defaults))
        XCTAssertFalse(BudgetGroupCollapse.isCollapsed("Bills", ledger: "l2", defaults))
    }
}
