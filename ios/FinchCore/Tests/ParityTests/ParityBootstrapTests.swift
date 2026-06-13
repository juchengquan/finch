import XCTest
@testable import FinchCore

/// Bootstrap placeholder so the `ParityTests` target has a compilable source.
/// Task 5 replaces/extends this with the real selector + audit parity tests
/// that decode the Task-0 fixtures from `Bundle.module` (`Fixtures/selectors/*`,
/// `Fixtures/audit/*`).
final class ParityBootstrapTests: XCTestCase {
    func test_fixturesBundleResolves() throws {
        // `Bundle.module` exists because this target declares a `Fixtures` resource.
        let fixturesURL = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures", withExtension: nil),
            "ParityTests should bundle the Task-0 Fixtures/ directory"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixturesURL.appendingPathComponent("selectors").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixturesURL.appendingPathComponent("audit").path))
    }
}
