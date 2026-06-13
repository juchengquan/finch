import XCTest
import GRDB
@testable import FinchCore

final class AuditTests: XCTestCase {
    func test_emptyDbPasses() throws {
        let dbQueue = try DatabaseQueue()
        try Migrations.runAll(on: dbQueue)
        let problems = try Audit.run(on: dbQueue)
        XCTAssertTrue(problems.isEmpty, "An empty DB should have 0 audit problems")
    }

    // NOTE: the fixture-driven cases (loading Task 0's corrupt `.sqlite3` via
    // Bundle.module) live in `ParityTests/AuditParityTests.swift` — `Bundle.module`
    // only exists for a target that declares resources, and `FinchCoreTests` has
    // none. AuditParityTests covers all 10 corruption fixtures, incl. `unbalanced`.
}
