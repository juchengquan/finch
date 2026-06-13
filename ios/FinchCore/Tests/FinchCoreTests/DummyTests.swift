import XCTest
@testable import FinchCore

final class DummyTests: XCTestCase {
    func test_versionIsSet() {
        XCTAssertFalse(FinchCore.version.isEmpty)
        XCTAssertEqual(FinchCore.packFormatVersion, "1")
    }
}
