import XCTest
import GRDB
@testable import FinchCore

/// The ledger list's order, and the two things that used to move it.
///
/// The list used to sort `is_default DESC, name`, which made activating a ledger
/// jump its row to the top — the list rearranged itself under the finger that tapped
/// it. That sort was also the only thing telling the app WHICH ledger is the default:
/// two call sites read `ledgers.first`. So the fix is a pair, and both halves are
/// asserted here — the order no longer reacts to activation, and `isDefault` still
/// answers what position used to.
final class LedgerOrderTests: XCTestCase {

    private func seeded(_ names: [(String, String)]) throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            for (i, pair) in names.enumerated() {
                try db.execute(sql: """
                    INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at)
                    VALUES (?,?,'USD',?,datetime('now'),datetime('now'))
                    """, arguments: [pair.0, pair.1, i == 0 ? 1 : 0])
            }
        }
        return q
    }

    private func ids(_ q: DatabaseQueue) throws -> [String] {
        try Projection.ledgers(dbQueue: q).map(\.id)
    }

    // MARK: the reported bug — activating must not reorder

    /// Activating each ledger in turn must leave the sequence identical every time.
    ///
    /// Written as a loop over EVERY ledger rather than one switch: the old sort was
    /// stable for whichever ledger already sat first, so a single-case test could pass
    /// against the very bug it was meant to catch.
    func testActivatingAnyLedgerLeavesTheOrderUnchanged() throws {
        let q = try seeded([("b", "Business"), ("a", "Alpha"), ("c", "Cash")])
        let before = try ids(q)
        XCTAssertEqual(before, ["a", "b", "c"], "no manual order yet → by name")

        for target in before {
            try q.write { db in try Ledgers.setDefault(db, Args(["id": .string(target)])) }
            XCTAssertEqual(try ids(q), before, "activating \(target) moved the rows")
        }
    }

    /// …and the same holds once a manual order exists: activation must not pull a row
    /// out of the order the user dragged it into.
    func testActivatingDoesNotDisturbTheManualOrder() throws {
        let q = try seeded([("b", "Business"), ("a", "Alpha"), ("c", "Cash")])
        try q.write { db in
            try AppDomain.setLedgerOrder(db, Args(["ledgerIds": .array([.string("c"), .string("b"), .string("a")])]))
            try Ledgers.setDefault(db, Args(["id": .string("a")]))
        }
        XCTAssertEqual(try ids(q), ["c", "b", "a"])
    }

    /// The half that pays for the sort change: with `is_default` gone from the ORDER BY,
    /// the flag has to travel on the row instead. `FinchStore.defaultLedgerId` reads it
    /// to pick the ledger to activate on a fresh launch and after an import.
    func testIsDefaultTravelsOnTheRowNotAsPositionZero() throws {
        let q = try seeded([("b", "Business"), ("a", "Alpha"), ("c", "Cash")])
        try q.write { db in try Ledgers.setDefault(db, Args(["id": .string("c")])) }

        let ledgers = try Projection.ledgers(dbQueue: q)
        XCTAssertEqual(ledgers.first?.id, "a", "still name-ordered")
        XCTAssertEqual(ledgers.filter(\.isDefault).map(\.id), ["c"],
                       "exactly one default, and it is NOT the first row")
    }

    // MARK: the manual order

    func testSetLedgerOrderDrivesTheProjection() throws {
        let q = try seeded([("a", "Alpha"), ("b", "Business"), ("c", "Cash")])
        try q.write { db in
            try AppDomain.setLedgerOrder(db, Args(["ledgerIds": .array([.string("c"), .string("a"), .string("b")])]))
        }
        XCTAssertEqual(try ids(q), ["c", "a", "b"])
    }

    /// A ledger created after the last drag is unknown to the stored order. It must not
    /// vanish, and it must not silently take someone else's slot — it goes last, keeping
    /// its name position among the other newcomers. Same rule as `applyBudgetOrder`.
    func testLedgersMissingFromTheOrderSortLastByName() throws {
        let q = try seeded([("a", "Alpha"), ("b", "Business")])
        try q.write { db in
            try AppDomain.setLedgerOrder(db, Args(["ledgerIds": .array([.string("b"), .string("a")])]))
            try db.execute(sql: """
                INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at)
                VALUES ('z','Aardvark','USD',0,datetime('now'),datetime('now')),
                       ('y','Zebra','USD',0,datetime('now'),datetime('now'))
                """)
        }
        XCTAssertEqual(try ids(q), ["b", "a", "z", "y"],
                       "ordered ones first; newcomers after, in name order")
    }

    /// A stale id (its ledger deleted) must not leave a hole or drop a live row.
    func testStaleIdsInTheOrderAreIgnored() throws {
        let q = try seeded([("a", "Alpha"), ("b", "Business")])
        try q.write { db in
            try AppDomain.setLedgerOrder(db,
                Args(["ledgerIds": .array([.string("gone"), .string("b"), .string("also-gone"), .string("a")])]))
        }
        XCTAssertEqual(try ids(q), ["b", "a"])
    }

    func testEmptyOrderFallsBackToName() throws {
        let q = try seeded([("b", "Business"), ("a", "Alpha")])
        try q.write { db in try AppDomain.setLedgerOrder(db, Args(["ledgerIds": .array([])])) }
        XCTAssertEqual(try ids(q), ["a", "b"])
    }

    /// The order survives a round trip through the action chokepoint, which is how the
    /// UI writes it — not just the handler called directly.
    func testOrderPersistsThroughApply() throws {
        let q = try seeded([("a", "Alpha"), ("b", "Business")])
        try Apply.apply(dbQueue: q, action: "setLedgerOrder",
                        args: Args(["ledgerIds": .array([.string("b"), .string("a")])]))
        XCTAssertEqual(try ids(q), ["b", "a"])
        let raw = try q.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM app_state WHERE key = 'ledgerOrder'")
        }
        XCTAssertEqual(raw, #"["b","a"]"#)
    }

    // MARK: the pure sort

    /// `LedgerOrder.sorted` is total: it never drops, duplicates or invents a row,
    /// whatever the stored order says. Asserted over the awkward inputs together
    /// because each one alone is a plausible-looking special case.
    func testSortedIsTotal() {
        let l = ["a", "b", "c"].map { Ledger(id: $0, name: $0, base: "USD", color: nil, tagline: nil) }
        for order in [[], ["c"], ["c", "a", "b"], ["x", "y"], ["a", "a", "b"], ["b", "b", "b"]] {
            let out = LedgerOrder.sorted(l, order: order)
            XCTAssertEqual(out.count, l.count, "order \(order) changed the row count")
            XCTAssertEqual(Set(out.map(\.id)), Set(l.map(\.id)), "order \(order) changed the row set")
        }
    }
}
