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

    /// Builds a chain exactly `maxDepth` deep, then proves the next level is refused.
    /// Written against the constant rather than a literal so raising the limit does
    /// not silently turn this into a test of nothing — it would otherwise keep
    /// passing while asserting a depth the engine no longer cares about.
    func test_createBeyondMaxDepth_rejected() throws {
        let q = try seeded()
        var parent: String?
        for level in 0..<Categories.maxDepth {
            let id = "c\(level)"
            try mkCat(q, id, parent: parent)
            parent = id
        }
        assertI18n("error.category.depthCap") {
            try mkCat(q, "oneTooDeep", parent: parent)
        }
    }

    /// The level BEFORE the cap must still be allowed — otherwise a guard that
    /// rejected everything would pass the test above.
    func test_createAtMaxDepth_allowed() throws {
        let q = try seeded()
        var parent: String?
        for level in 0..<(Categories.maxDepth - 1) {
            let id = "c\(level)"
            try mkCat(q, id, parent: parent)
            parent = id
        }
        try mkCat(q, "atCap", parent: parent)   // lands exactly at maxDepth
    }

    /// The cap counts the MOVING subtree's own height, not just where it lands: a
    /// 2-level subtree needs two levels of headroom. Built from `maxDepth` so it
    /// keeps testing the boundary wherever the limit is set.
    func test_moveSubtreeExceedingCap_rejected() throws {
        let q = try seeded()
        // A 2-level subtree: a → b.
        try mkCat(q, "a")
        try mkCat(q, "b", parent: "a")
        // A chain deep enough that adding 2 more levels overflows.
        var parent: String?
        for level in 0..<(Categories.maxDepth - 1) {
            let id = "p\(level)"
            try mkCat(q, id, parent: parent)
            parent = id
        }
        // depth(parent) = maxDepth - 1, subtreeDepth(a) = 2 → maxDepth + 1 > maxDepth.
        assertI18n("error.category.depthCap") {
            try Apply.apply(dbQueue: q, action: "updateCategory",
                            args: Args(["id": .string("a"), "patch": .object(["parentId": .string(parent!)])]))
        }
    }

    /// One level shallower must succeed, so the test above is proving the boundary
    /// rather than a guard that refuses everything.
    func test_moveSubtreeThatExactlyFits_allowed() throws {
        let q = try seeded()
        try mkCat(q, "a")
        try mkCat(q, "b", parent: "a")
        var parent: String?
        for level in 0..<(Categories.maxDepth - 2) {
            let id = "p\(level)"
            try mkCat(q, id, parent: parent)
            parent = id
        }
        // depth(parent) = maxDepth - 2, subtreeDepth(a) = 2 → exactly maxDepth.
        try Apply.apply(dbQueue: q, action: "updateCategory",
                        args: Args(["id": .string("a"), "patch": .object(["parentId": .string(parent!)])]))
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
