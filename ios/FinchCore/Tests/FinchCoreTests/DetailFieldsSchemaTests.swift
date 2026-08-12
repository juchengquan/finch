import XCTest
import GRDB
@testable import FinchCore

/// The detail columns added 2026-08-12: on `accounts` — `icon`, `notes`,
/// `statement_day`, `due_day`, `credit_limit`, `institution`, `account_last4`;
/// on `budgets` — `notes`, `icon`, `color`.
///
/// This is the migration that runs against a real device's existing database, so
/// the cases that matter are the ones a fresh-DB test would never reach: a
/// database that PREDATES the columns must gain them, and one that already has
/// them must not throw.
final class DetailFieldsSchemaTests: XCTestCase {

    private static let newColumns = ["icon", "notes", "statement_day", "due_day",
                                     "credit_limit", "institution", "account_last4"]

    private func columns(_ db: Database, _ table: String) throws -> [String] {
        try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))").compactMap { $0["name"] as String? }
    }

    func test_freshDatabaseCarriesTheColumns() throws {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.read { db in
            let cols = try columns(db, "accounts")
            for c in Self.newColumns {
                XCTAssertTrue(cols.contains(c), "fresh accounts table should have \(c)")
            }
        }
    }

    /// The real upgrade path: a database built from the accounts table as it was
    /// BEFORE this change, then migrated. A fresh-DB test cannot cover this,
    /// because the baseline DDL already contains the columns and the migration
    /// is recorded as applied before it could do any work.
    func test_preExistingDatabaseGainsTheColumns() throws {
        let q = try DatabaseQueue()
        try q.write { db in
            try db.execute(sql: """
                CREATE TABLE accounts (
                  id TEXT PRIMARY KEY,
                  ledger_id TEXT NOT NULL,
                  name TEXT NOT NULL,
                  type TEXT NOT NULL,
                  currency TEXT NOT NULL DEFAULT 'SGD',
                  current_balance REAL NOT NULL DEFAULT 0,
                  created_at TEXT NOT NULL,
                  updated_at TEXT NOT NULL
                )
                """)
            // The migration touches budgets too, so a realistic pre-change
            // database has to carry it — a fixture with only `accounts` would
            // fail on "no such table", which the ALTERs deliberately do NOT
            // swallow (only "duplicate column" is tolerated).
            try db.execute(sql: """
                CREATE TABLE budgets (
                  id TEXT PRIMARY KEY,
                  ledger_id TEXT NOT NULL,
                  kind TEXT NOT NULL,
                  amount REAL NOT NULL,
                  frequency TEXT NOT NULL,
                  start_date TEXT NOT NULL,
                  created_at TEXT NOT NULL,
                  updated_at TEXT NOT NULL
                )
                """)
            try db.execute(sql: """
                INSERT INTO accounts (id, ledger_id, name, type, created_at, updated_at)
                VALUES ('a1', 'l1', 'Amex', 'credit_card', '2026-01-01', '2026-01-01')
                """)
        }

        try q.write { db in try Migrations.addDetailFields(db) }

        try q.read { db in
            let cols = try columns(db, "accounts")
            for c in Self.newColumns {
                XCTAssertTrue(cols.contains(c), "migrated accounts table should have \(c)")
            }
            let budgetCols = try columns(db, "budgets")
            for c in ["notes", "icon", "color"] {
                XCTAssertTrue(budgetCols.contains(c), "migrated budgets table should have \(c)")
            }
            // The existing row survives and reads as "unset" — nullable columns,
            // no backfill, so nothing had to be invented for rows that predate them.
            let row = try Row.fetchOne(db, sql: "SELECT * FROM accounts WHERE id = 'a1'")
            XCTAssertEqual(row?["name"] as String?, "Amex")
            XCTAssertNil(row?["icon"] as String?)
            XCTAssertNil(row?["notes"] as String?)
            XCTAssertNil(row?["statement_day"] as Int?)
            XCTAssertNil(row?["due_day"] as Int?)
            XCTAssertNil(row?["credit_limit"] as Double?)
        }
    }

    /// Imported web packs can already carry the columns while lacking GRDB's
    /// bookkeeping, so the ALTERs must swallow "duplicate column" — the same
    /// tolerance every earlier additive migration relies on.
    func test_runningTheAltersTwiceDoesNotThrow() throws {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        XCTAssertNoThrow(try q.write { db in try Migrations.addDetailFields(db) })
        XCTAssertNoThrow(try q.write { db in try Migrations.addDetailFields(db) })
    }

    /// The whole chain: createAccount writes the fields, the projection reads
    /// them back, updateAccount patches them, and an explicit null clears one.
    func test_fieldsRoundTripThroughApplyAndProjection() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "createAccount",
                        args: Args(["id": .string("cc1"), "ledgerId": .string("l1"),
                                    "name": .string("Amex"), "type": .string("credit_card"),
                                    "icon": .string("creditcard"), "notes": .string("main card"),
                                    "statementDay": .double(15), "dueDay": .double(5),
                                    "creditLimit": .double(10_000)]))
        var acct = try XCTUnwrap(Projection.accounts(dbQueue: q, ledgerId: "l1").first { $0.id == "cc1" })
        XCTAssertEqual(acct.icon, "creditcard")
        XCTAssertEqual(acct.notes, "main card")
        XCTAssertEqual(acct.statementDay, 15)
        XCTAssertEqual(acct.dueDay, 5)
        XCTAssertEqual(acct.creditLimit, 10_000)

        try Apply.apply(dbQueue: q, action: "updateAccount",
                        args: Args(["id": .string("cc1"),
                                    "patch": .object(["dueDay": .double(28), "notes": .null])]))
        acct = try XCTUnwrap(Projection.accounts(dbQueue: q, ledgerId: "l1").first { $0.id == "cc1" })
        XCTAssertEqual(acct.dueDay, 28)
        XCTAssertNil(acct.notes, "an explicit null must clear the note, not be ignored")
        XCTAssertEqual(acct.statementDay, 15, "untouched fields survive a partial patch")
    }

    /// Budgets gained a note plus their own icon and colour — budget GROUPS
    /// already had a colour, the budgets themselves did not.
    func test_budgetFieldsRoundTripThroughApplyAndProjection() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "createBudget",
                        args: Args(["id": .string("b-new"), "ledgerId": .string("l1"),
                                    "name": .string("Groceries"), "amount": .double(500),
                                    "notes": .string("weekly shop"), "icon": .string("cart"),
                                    "color": .string("#22C55E")]))
        var b = try XCTUnwrap(Projection.budgets(dbQueue: q, ledgerId: "l1").first { $0.id == "b-new" })
        XCTAssertEqual(b.notes, "weekly shop")
        XCTAssertEqual(b.icon, "cart")
        XCTAssertEqual(b.color, "#22C55E")

        try Apply.apply(dbQueue: q, action: "updateBudget",
                        args: Args(["id": .string("b-new"),
                                    "patch": .object(["color": .null, "notes": .string("moved to fortnightly")])]))
        b = try XCTUnwrap(Projection.budgets(dbQueue: q, ledgerId: "l1").first { $0.id == "b-new" })
        XCTAssertNil(b.color, "an explicit null clears the colour")
        XCTAssertEqual(b.notes, "moved to fortnightly")
        XCTAssertEqual(b.icon, "cart", "untouched fields survive a partial patch")
    }

    /// An account created the old way — no detail fields — still works, and
    /// reads as unset rather than as zeros.
    func test_accountCreatedWithoutTheFieldsReadsAsUnset() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "createAccount",
                        args: Args(["id": .string("plain"), "ledgerId": .string("l1"),
                                    "name": .string("Cash"), "type": .string("cash")]))
        let acct = try XCTUnwrap(Projection.accounts(dbQueue: q, ledgerId: "l1").first { $0.id == "plain" })
        XCTAssertNil(acct.icon)
        XCTAssertNil(acct.notes)
        XCTAssertNil(acct.statementDay)
        XCTAssertNil(acct.creditLimit, "unknown limit is nil, never 0 — 0 would read as a real limit")
    }

    /// The columns hold what they claim to. `credit_limit` is REAL rather than an
    /// integer count of cents because every other money column in this schema is,
    /// and the day columns are INTEGER day-of-month, not dates.
    func test_theColumnsRoundTripTheirValues() throws {
        let q = try TestSeed.base()   // accounts.ledger_id is a real FK — needs a ledger
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts
                  (id, ledger_id, name, type, currency, icon, notes,
                   statement_day, due_day, credit_limit, created_at, updated_at)
                VALUES ('acct-cc','l1','Amex','credit_card','SGD','creditcard','main card',
                        15, 5, 10000.50, '2026-01-01', '2026-01-01')
                """)
        }
        try q.read { db in
            let row = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT * FROM accounts WHERE id = 'acct-cc'"))
            XCTAssertEqual(row["icon"] as String?, "creditcard")
            XCTAssertEqual(row["notes"] as String?, "main card")
            XCTAssertEqual(row["statement_day"] as Int?, 15)
            XCTAssertEqual(row["due_day"] as Int?, 5)
            XCTAssertEqual(row["credit_limit"] as Double?, 10000.50)
        }
    }
}
