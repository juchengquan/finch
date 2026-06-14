import XCTest
import GRDB
@testable import FinchCore

/// updateCategory / createCategory reparenting guards (port of _depth.ts):
/// self-parent, move-under-own-descendant (cycle), and the ≤3-level cap.
final class CategoryGuardTests: XCTestCase {
    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
        }
        return q
    }

    private func mkCat(_ q: DatabaseQueue, _ id: String, parent: String? = nil) throws {
        var args: [String: JSONValue] = ["id": .string(id), "ledgerId": .string("l1"), "name": .string(id)]
        if let parent { args["parentId"] = .string(parent) }
        try Apply.apply(dbQueue: q, action: "createCategory", args: Args(args))
    }

    private func assertI18n(_ code: String, _ body: () throws -> Void) {
        XCTAssertThrowsError(try body()) { err in
            guard let e = err as? I18nError else { return XCTFail("expected I18nError, got \(err)") }
            XCTAssertEqual(e.code, code)
        }
    }

    func test_selfParent_rejected() throws {
        let q = try seeded()
        try mkCat(q, "a")
        assertI18n("error.category.selfParent") {
            try Apply.apply(dbQueue: q, action: "updateCategory", args: Args(["id": .string("a"), "patch": .object(["parentId": .string("a")])]))
        }
    }

    func test_moveUnderOwnDescendant_rejected() throws {
        let q = try seeded()
        try mkCat(q, "a")
        try mkCat(q, "b", parent: "a")   // b is a child of a
        // Moving a under b would create a cycle a→b→a.
        assertI18n("error.category.underDescendant") {
            try Apply.apply(dbQueue: q, action: "updateCategory", args: Args(["id": .string("a"), "patch": .object(["parentId": .string("b")])]))
        }
    }

    func test_createUnderDepth3Parent_rejected() throws {
        let q = try seeded()
        try mkCat(q, "a")
        try mkCat(q, "b", parent: "a")
        try mkCat(q, "c", parent: "b")   // a→b→c is depth 3
        assertI18n("error.category.depthCap") {
            try mkCat(q, "d", parent: "c")   // would be depth 4
        }
    }

    func test_moveSubtreeExceedingCap_rejected() throws {
        let q = try seeded()
        try mkCat(q, "a")
        try mkCat(q, "b", parent: "a")   // a→b (subtree depth 2 under a)
        try mkCat(q, "x")
        try mkCat(q, "y", parent: "x")   // x→y (parent depth 2)
        // Moving a (subtree depth 2) under y (depth 2) → 2+2 = 4 > 3.
        assertI18n("error.category.depthCap") {
            try Apply.apply(dbQueue: q, action: "updateCategory", args: Args(["id": .string("a"), "patch": .object(["parentId": .string("y")])]))
        }
    }

    func test_validReparent_allowed() throws {
        let q = try seeded()
        try mkCat(q, "a")
        try mkCat(q, "b")
        try Apply.apply(dbQueue: q, action: "updateCategory", args: Args(["id": .string("b"), "patch": .object(["parentId": .string("a")])]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT parent_id FROM categories WHERE id = 'b'"), "a")
        }
    }
}
