import XCTest
import GRDB
@testable import FinchCore

/// Task 2 of the "post now for a scheduled occurrence" change: `occurrenceDate`
/// must survive the `SimpleEntryInput` → `NewEntry` hand-off and land in
/// `entries.occurrence_date`, while staying NULL for every existing/manual
/// posting path that doesn't set it.
final class EntriesOccurrenceTests: XCTestCase {
    func test_postSimple_persistsOccurrenceDate() throws {
        let q = try TestSeed.base()
        try q.write { db in
            try Entries.postSimple(db, .init(ledgerId: "l1", accountId: "a1", amount: -10,
                                             date: "2026-07-21", description: "Gym",
                                             categoryId: nil, kind: .expense, skipRules: true,
                                             sourceTemplateId: "s1", occurrenceDate: "2026-07-15"))
        }
        try q.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT occurrence_date FROM entries WHERE source_template_id = 's1'")
            XCTAssertEqual(row?["occurrence_date"], "2026-07-15")
        }
    }

    func test_postSimple_withoutOccurrenceDate_leavesItNull() throws {
        let q = try TestSeed.base()
        try q.write { db in
            try Entries.postSimple(db, .init(ledgerId: "l1", accountId: "a1", amount: -10,
                                             date: "2026-07-21", description: "Manual",
                                             categoryId: nil, kind: .expense, skipRules: true))
        }
        try q.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT occurrence_date FROM entries WHERE description = 'Manual'")
            XCTAssertNil(row?["occurrence_date"] as String?)
        }
    }
}
