import XCTest
@testable import FinchApp

final class AccountGroupCollapseTests: XCTestCase {
    private let suite = "test.AccountGroupCollapse"
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
        XCTAssertTrue(AccountGroupCollapse.collapsed(defaults).isEmpty)
        XCTAssertFalse(AccountGroupCollapse.isCollapsed("Savings", defaults))
    }

    func test_setCollapsedTrue() {
        AccountGroupCollapse.setCollapsed("Savings", true, defaults)
        XCTAssertTrue(AccountGroupCollapse.isCollapsed("Savings", defaults))
        XCTAssertEqual(AccountGroupCollapse.collapsed(defaults), ["Savings"])
    }

    func test_setCollapsedFalseRemoves() {
        AccountGroupCollapse.setCollapsed("Savings", true, defaults)
        AccountGroupCollapse.setCollapsed("Savings", false, defaults)
        XCTAssertFalse(AccountGroupCollapse.isCollapsed("Savings", defaults))
        XCTAssertTrue(AccountGroupCollapse.collapsed(defaults).isEmpty)
    }

    func test_multipleGroupsIndependent() {
        AccountGroupCollapse.setCollapsed("A", true, defaults)
        AccountGroupCollapse.setCollapsed("B", true, defaults)
        AccountGroupCollapse.setCollapsed("A", false, defaults)
        XCTAssertFalse(AccountGroupCollapse.isCollapsed("A", defaults))
        XCTAssertTrue(AccountGroupCollapse.isCollapsed("B", defaults))
    }

    func test_setCollapsedTrueIdempotent() {
        AccountGroupCollapse.setCollapsed("A", true, defaults)
        AccountGroupCollapse.setCollapsed("A", true, defaults)
        XCTAssertEqual(AccountGroupCollapse.collapsed(defaults), ["A"])
    }
}
