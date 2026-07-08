import XCTest
@testable import FinchApp

final class QuickAddDedupeTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.quickAddDedupe.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func test_firstSeen_trueOncePerId() {
        let d = QuickAddDedupe(defaults: defaults)
        XCTAssertTrue(d.firstSeen("a"))
        XCTAssertFalse(d.firstSeen("a"))
        XCTAssertTrue(d.firstSeen("b"))
    }

    func test_persistsAcrossInstances() {
        XCTAssertTrue(QuickAddDedupe(defaults: defaults).firstSeen("a"))
        XCTAssertFalse(QuickAddDedupe(defaults: defaults).firstSeen("a"))
    }

    func test_evictsBeyondCapacity() {
        let d = QuickAddDedupe(defaults: defaults, capacity: 3)
        for i in 0..<4 { XCTAssertTrue(d.firstSeen("id-\(i)")) }
        // id-0 was evicted by id-3 → seen "again".
        XCTAssertTrue(d.firstSeen("id-0"))
        // Recent ids are still guarded.
        XCTAssertFalse(d.firstSeen("id-3"))
    }
}
