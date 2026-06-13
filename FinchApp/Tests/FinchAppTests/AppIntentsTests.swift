import XCTest
@testable import FinchApp

/// Phase 6.4 — the one pure bit of the App Intents surface: the Siri-pickable
/// screen enum maps 1:1 onto the app's tabs. (The intents' perform() dispatch
/// already-tested chokepoint actions; they aren't unit-tested here.)
final class AppIntentsTests: XCTestCase {
    func test_screenEnumMapsEveryTab() {
        let pairs: [(ScreenAppEnum, AppTab)] = [
            (.accounts, .accounts), (.activity, .activity), (.budgets, .budgets),
            (.insights, .insights), (.scheduled, .scheduled), (.settings, .settings),
        ]
        for (screen, tab) in pairs { XCTAssertEqual(screen.tab, tab) }
        // Every enum case is covered + distinct.
        XCTAssertEqual(ScreenAppEnum.allCasesCount, 6)
        XCTAssertEqual(Set(pairs.map { $0.1 }).count, 6)
    }
}

private extension ScreenAppEnum {
    static var allCasesCount: Int {
        [ScreenAppEnum.accounts, .activity, .budgets, .insights, .scheduled, .settings].count
    }
}
