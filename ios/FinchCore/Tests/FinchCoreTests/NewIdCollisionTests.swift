import XCTest
@testable import FinchCore

/// `Entries.newId` is the ID source for every write path in the store, and its
/// only defence against a duplicate PRIMARY KEY is the random suffix — the
/// millisecond timestamp is shared by everything created in the same
/// millisecond, which on a bulk path (statement import, a seeded test, a split
/// with many legs) is most of a batch.
final class NewIdCollisionTests: XCTestCase {
    /// Generating a batch as fast as the machine can must not repeat an ID.
    ///
    /// This is the regression test for a REAL failure, not a hypothetical:
    /// `InsightsRulesTests.test_quietest_day` hit
    /// `UNIQUE constraint failed: postings.id` in CI while seeding 28
    /// transactions in a loop.
    ///
    /// With the old 4-hex-character suffix (65_536 values) this fails
    /// essentially always: a tight loop emits ~1000 IDs per millisecond, and by
    /// the birthday bound a single millisecond of that batch collides with
    /// probability ~99.9%. It is not a flaky test that happens to catch a flaky
    /// bug — at this batch size the old code cannot pass it.
    func testABatchOfIdsIsUnique() {
        let n = 100_000
        var seen = Set<String>(minimumCapacity: n)
        for _ in 0..<n { seen.insert(Entries.newId("pst")) }
        XCTAssertEqual(seen.count, n, "newId repeated an ID within a batch of \(n)")
    }

    /// The same batch under TWO prefixes must not collide either — prefixes
    /// partition the ID space, so this pins that they really are independent
    /// and a `pst-` can never equal an `ent-`.
    func testPrefixesDoNotOverlap() {
        var seen = Set<String>()
        for _ in 0..<10_000 {
            seen.insert(Entries.newId("pst"))
            seen.insert(Entries.newId("ent"))
        }
        XCTAssertEqual(seen.count, 20_000)
    }

    /// The shape callers rely on: `prefix-timestamp-random`, with the prefix
    /// recoverable. Nothing in the app PARSES an ID (every `split(separator:
    /// "-")` in the tree is on a date or a backup filename), so this pins the
    /// format loosely on purpose — the suffix width is free to grow again.
    func testTheShapeIsPrefixTimestampRandom() {
        let id = Entries.newId("pst")
        let parts = id.split(separator: "-")
        XCTAssertEqual(parts.count, 3, "expected prefix-timestamp-random, got \(id)")
        XCTAssertEqual(parts.first.map(String.init), "pst")
        XCTAssertTrue(parts.last?.allSatisfy { $0.isHexDigit && !$0.isUppercase } ?? false,
                      "random suffix should be lowercase hex, got \(id)")
    }
}
