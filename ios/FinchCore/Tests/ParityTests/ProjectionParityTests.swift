import XCTest
import GRDB
@testable import FinchCore

/// DESIGN §8.1 — the projection parity gate. Open Task 0's golden DB fixture, run
/// the Swift `Projection`, and assert the `Tx[]` equals the web `projectState`'s
/// output captured in the sibling JSON (same DB snapshot → same posting ids).
final class ProjectionParityTests: XCTestCase {
    func test_projectionMatchesWebOracle() throws {
        let dir = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
            .appendingPathComponent("projection")
        struct Fixture: Decodable { let expected: [Tx] }
        let fixture = try JSONDecoder().decode(
            Fixture.self, from: Data(contentsOf: dir.appendingPathComponent("projection.json")))

        let dbQueue = try DatabaseQueue(path: dir.appendingPathComponent("projection.sqlite3").path)
        // Migrate first, exactly as the app does with any database it opens —
        // including one imported from the web, which is what this fixture is. The
        // projection selects `entries.group_id`, an iOS-only column the web never
        // writes, so a web-generated database only has it after migration. This
        // does not weaken the comparison: the expected `[Tx]` is unchanged, and
        // `group_id` is NULL throughout, so every row still projects identically.
        try Migrations.runAll(on: dbQueue)
        let actual = try Projection.run(dbQueue: dbQueue)

        XCTAssertEqual(actual, fixture.expected)
        // Grain sanity: one Tx per account-leg posting, opening excluded.
        XCTAssertEqual(actual.count, 3)
        XCTAssertTrue(actual.allSatisfy { $0.category == "c1" && $0.ledgerId == "l1" })
        // rowCounts uses the 15 canonical tables.
        let counts = try Projection.rowCounts(dbQueue: dbQueue)
        XCTAssertEqual(counts.count, 15)
        XCTAssertEqual(counts["entries"], 3)
        XCTAssertEqual(counts["postings"], 6)  // 3 entries × (account leg + category leg)
    }
}
