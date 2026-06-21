import XCTest
@testable import FinchApp

final class BudgetGroupCollapseTests: XCTestCase {
    private let suite = "test.BudgetGroupCollapse"
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
        XCTAssertTrue(BudgetGroupCollapse.collapsed(defaults).isEmpty)
        XCTAssertFalse(BudgetGroupCollapse.isCollapsed("Bills", defaults))
    }

    func test_setCollapsedTrue() {
        BudgetGroupCollapse.setCollapsed("Bills", true, defaults)
        XCTAssertTrue(BudgetGroupCollapse.isCollapsed("Bills", defaults))
        XCTAssertEqual(BudgetGroupCollapse.collapsed(defaults), ["Bills"])
    }

    func test_setCollapsedFalseRemoves() {
        BudgetGroupCollapse.setCollapsed("Bills", true, defaults)
        BudgetGroupCollapse.setCollapsed("Bills", false, defaults)
        XCTAssertFalse(BudgetGroupCollapse.isCollapsed("Bills", defaults))
        XCTAssertTrue(BudgetGroupCollapse.collapsed(defaults).isEmpty)
    }

    func test_multipleGroupsIndependent() {
        BudgetGroupCollapse.setCollapsed("A", true, defaults)
        BudgetGroupCollapse.setCollapsed("B", true, defaults)
        BudgetGroupCollapse.setCollapsed("A", false, defaults)
        XCTAssertFalse(BudgetGroupCollapse.isCollapsed("A", defaults))
        XCTAssertTrue(BudgetGroupCollapse.isCollapsed("B", defaults))
    }

    func test_setCollapsedTrueIdempotent() {
        BudgetGroupCollapse.setCollapsed("A", true, defaults)
        BudgetGroupCollapse.setCollapsed("A", true, defaults)
        XCTAssertEqual(BudgetGroupCollapse.collapsed(defaults), ["A"])
    }
}
