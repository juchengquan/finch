import XCTest
@testable import FinchApp

final class CompactTabRoutingTests: XCTestCase {
    func test_primaryTabsMapToOwnSlot() {
        XCTAssertEqual(CompactTabRouting.compactTab(for: .accounts), .accounts)
        XCTAssertEqual(CompactTabRouting.compactTab(for: .budgets), .budgets)
        XCTAssertEqual(CompactTabRouting.compactTab(for: .scheduled), .scheduled)
        XCTAssertEqual(CompactTabRouting.compactTab(for: .insights), .insights)
    }

    func test_activityMapsToAccounts() {   // Activity feed now lives inside Accounts
        XCTAssertEqual(CompactTabRouting.compactTab(for: .activity), .accounts)
    }

    func test_overflowTabsMapToMore() {
        XCTAssertEqual(CompactTabRouting.compactTab(for: .settings), .more)
    }

    func test_appTabForSlot() {
        XCTAssertEqual(CompactTabRouting.appTab(for: .accounts), .accounts)
        XCTAssertEqual(CompactTabRouting.appTab(for: .scheduled), .scheduled)
        XCTAssertEqual(CompactTabRouting.appTab(for: .insights), .insights)
        XCTAssertNil(CompactTabRouting.appTab(for: .more))
    }

    func test_overflowTab() {
        XCTAssertEqual(CompactTabRouting.overflowTab(for: .settings), .settings)
        XCTAssertNil(CompactTabRouting.overflowTab(for: .scheduled))   // now a primary tab
        XCTAssertNil(CompactTabRouting.overflowTab(for: .accounts))
    }

    func test_sync_primaryClearsPath() {
        let r = CompactTabRouting.sync(routerTab: .budgets, currentPath: [.settings])
        XCTAssertEqual(r.selected, .budgets)
        XCTAssertEqual(r.path, [])
    }

    func test_sync_overflowPushesScreen() {
        let r = CompactTabRouting.sync(routerTab: .settings, currentPath: [])
        XCTAssertEqual(r.selected, .more)
        XCTAssertEqual(r.path, [.settings])
    }

    func test_sync_preservesExistingOverflowPath() {
        let r = CompactTabRouting.sync(routerTab: .settings, currentPath: [.settings])
        XCTAssertEqual(r.selected, .more)
        XCTAssertEqual(r.path, [.settings])
    }

    func test_sync_primaryFromOverflowClearsPath() {
        // Scheduled is now a primary slot: switching to it from the More tab
        // selects its own slot and clears the overflow push path.
        let r = CompactTabRouting.sync(routerTab: .scheduled, currentPath: [.settings])
        XCTAssertEqual(r.selected, .scheduled)
        XCTAssertEqual(r.path, [])
    }

    func test_routerTab_primaryWhenChanged() {
        XCTAssertEqual(CompactTabRouting.routerTab(forSelected: .budgets, current: .accounts), .budgets)
    }

    func test_routerTab_nilWhenUnchanged() {
        XCTAssertNil(CompactTabRouting.routerTab(forSelected: .accounts, current: .accounts))
    }

    func test_routerTab_nilForMore() {
        XCTAssertNil(CompactTabRouting.routerTab(forSelected: .more, current: .accounts))
    }
}
