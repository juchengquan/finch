import XCTest
@testable import FinchApp

final class CompactTabRoutingTests: XCTestCase {
    func test_primaryTabsMapToOwnSlot() {
        XCTAssertEqual(CompactTabRouting.compactTab(for: .accounts), .accounts)
        XCTAssertEqual(CompactTabRouting.compactTab(for: .budgets), .budgets)
        XCTAssertEqual(CompactTabRouting.compactTab(for: .scheduled), .scheduled)
        XCTAssertEqual(CompactTabRouting.compactTab(for: .insights), .insights)
        XCTAssertEqual(CompactTabRouting.compactTab(for: .settings), .settings)
    }

    func test_activityMapsToAccounts() {   // the activity feed lives in the Accounts tab now
        XCTAssertEqual(CompactTabRouting.compactTab(for: .activity), .accounts)
    }

    func test_ledgerIsCornerPushedOverflow() {
        XCTAssertEqual(CompactTabRouting.compactTab(for: .ledger), .more)
    }

    func test_appTabForSlot() {
        XCTAssertEqual(CompactTabRouting.appTab(for: .accounts), .accounts)
        XCTAssertEqual(CompactTabRouting.appTab(for: .budgets), .budgets)
        XCTAssertEqual(CompactTabRouting.appTab(for: .scheduled), .scheduled)
        XCTAssertEqual(CompactTabRouting.appTab(for: .insights), .insights)
        XCTAssertEqual(CompactTabRouting.appTab(for: .settings), .settings)
        XCTAssertNil(CompactTabRouting.appTab(for: .more))
    }

    func test_overflowTab() {
        XCTAssertEqual(CompactTabRouting.overflowTab(for: .ledger), .ledger)
        XCTAssertNil(CompactTabRouting.overflowTab(for: .settings))   // now a primary tab
        XCTAssertNil(CompactTabRouting.overflowTab(for: .accounts))
    }

    func test_sync_primaryClearsPath() {
        let r = CompactTabRouting.sync(routerTab: .budgets, currentPath: [.ledger])
        XCTAssertEqual(r.selected, .budgets)
        XCTAssertEqual(r.path, [])
    }

    func test_sync_overflowPushesLedger() {
        let r = CompactTabRouting.sync(routerTab: .ledger, currentPath: [])
        XCTAssertEqual(r.selected, .more)
        XCTAssertEqual(r.path, [.ledger])
    }

    func test_sync_preservesExistingOverflowPath() {
        let r = CompactTabRouting.sync(routerTab: .ledger, currentPath: [.ledger])
        XCTAssertEqual(r.selected, .more)
        XCTAssertEqual(r.path, [.ledger])
    }

    func test_sync_primaryFromOverflowClearsPath() {
        let r = CompactTabRouting.sync(routerTab: .settings, currentPath: [.ledger])
        XCTAssertEqual(r.selected, .settings)
        XCTAssertEqual(r.path, [])
    }

    func test_routerTab_primaryWhenChanged() {
        XCTAssertEqual(CompactTabRouting.routerTab(forSelected: .budgets, current: .accounts), .budgets)
    }

    func test_routerTab_settingsWhenChanged() {
        XCTAssertEqual(CompactTabRouting.routerTab(forSelected: .settings, current: .accounts), .settings)
    }

    func test_routerTab_nilWhenUnchanged() {
        XCTAssertNil(CompactTabRouting.routerTab(forSelected: .accounts, current: .accounts))
    }

    func test_routerTab_nilForMore() {
        XCTAssertNil(CompactTabRouting.routerTab(forSelected: .more, current: .accounts))
    }
}
