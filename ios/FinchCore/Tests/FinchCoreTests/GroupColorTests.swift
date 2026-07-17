import XCTest
import GRDB
@testable import FinchCore

/// Group `color` column (first post-baseline migration, 2026-07-17):
/// create/update round-trips through the projection, and the migration is
/// present + duplicate-column tolerant (imported web packs may already carry
/// the column while lacking GRDB's bookkeeping table).
final class GroupColorTests: XCTestCase {

    func test_createBudgetGroupWithColorRoundTripsThroughProjection() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "createBudgetGroup",
                        args: Args(["id": .string("bg1"), "ledgerId": .string("l1"),
                                    "name": .string("Essentials"), "color": .string("#EF4444")]))
        // No color → nil (column is nullable; old callers unchanged).
        try Apply.apply(dbQueue: q, action: "createBudgetGroup",
                        args: Args(["id": .string("bg2"), "ledgerId": .string("l1"),
                                    "name": .string("Fun")]))
        let groups = try Projection.budgetGroups(dbQueue: q, ledgerId: "l1")
        XCTAssertEqual(groups.first { $0.id == "bg1" }?.color, "#EF4444")
        XCTAssertNil(groups.first { $0.id == "bg2" }?.color)
    }

    func test_updateBudgetGroupColorPatchRoundTrips() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "createBudgetGroup",
                        args: Args(["id": .string("bg1"), "ledgerId": .string("l1"),
                                    "name": .string("Essentials")]))
        try Apply.apply(dbQueue: q, action: "updateBudgetGroup",
                        args: Args(["id": .string("bg1"), "patch": .object(["color": .string("#3B82F6")])]))
        var groups = try Projection.budgetGroups(dbQueue: q, ledgerId: "l1")
        XCTAssertEqual(groups.first { $0.id == "bg1" }?.color, "#3B82F6")
        // Explicit null clears the color.
        try Apply.apply(dbQueue: q, action: "updateBudgetGroup",
                        args: Args(["id": .string("bg1"), "patch": .object(["color": .null])]))
        groups = try Projection.budgetGroups(dbQueue: q, ledgerId: "l1")
        XCTAssertNil(groups.first { $0.id == "bg1" }?.color)
    }

    func test_accountGroupColorRoundTrips() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "createAccountGroup",
                        args: Args(["id": .string("ag1"), "ledgerId": .string("l1"),
                                    "name": .string("Cash"), "color": .string("#22C55E")]))
        let groups = try Projection.accountGroups(dbQueue: q, ledgerId: "l1")
        XCTAssertEqual(groups.first { $0.id == "ag1" }?.color, "#22C55E")
    }

    func test_migratorProducesColorColumnAndAlterToleranceHolds() throws {
        // Fresh DB: full migrator (baseline already carries `color`, so the
        // 2026-07-17 migration's ALTER hits "duplicate column" and must be
        // swallowed — runAll succeeding at all exercises the tolerance path).
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.read { db in
            for table in ["budget_groups", "account_groups"] {
                let cols = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
                    .compactMap { $0["name"] as String? }
                XCTAssertTrue(cols.contains("color"), "\(table) should have a color column")
            }
            // The migration re-stamps db_metadata to the new shared version.
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT schema_version FROM db_metadata WHERE id = 1"),
                           "2026-07-17T00:00:00Z")
        }
        // Running the tolerant ALTER again (the migration's exact idiom) must not throw.
        try q.write { db in
            for table in ["budget_groups", "account_groups"] {
                do { try db.execute(sql: "ALTER TABLE \(table) ADD COLUMN color TEXT") }
                catch { if !"\(error)".contains("duplicate column") { throw error } }
            }
        }
    }
}
