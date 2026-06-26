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
}
