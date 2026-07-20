import XCTest
@testable import FinchCore

final class SchemaTests: XCTestCase {
    func test_schemaVersionIsSet() {
        XCTAssertFalse(Schema.version.isEmpty)
        // The current web `SCHEMA_VERSION` (lib/db/core/schema.ts:435). Phase 1.0
        // ships the post-DE schema; the version string is shared cross-app.
        // 2026-07-20: global merchants (counterparties.ledger_id dropped).
        XCTAssertEqual(Schema.version, "2026-07-20T00:00:00Z")
        XCTAssertEqual(Schema.appName, "finch")
    }
}
