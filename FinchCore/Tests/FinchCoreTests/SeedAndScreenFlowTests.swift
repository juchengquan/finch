import XCTest
import GRDB
@testable import FinchCore

/// Integration proxy for the Phase 2 write screens: replays the EXACT chokepoint
/// calls (action + arg shape) each screen issues, against a DB seeded the way
/// FinchStore.bootstrap seeds a fresh install. Guards against arg-name drift
/// between a screen and its handler (the kind of bug a pure UI build can't catch).
final class SeedAndScreenFlowTests: XCTestCase {
    /// Mirror of FinchStore.seedMinimalStarter, through the chokepoint.
    private func seededStarter() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try Apply.apply(dbQueue: q, action: "createLedger",
                        args: Args(["id": .string("personal"), "name": .string("Personal"), "base": .string("USD")]))
        try Apply.apply(dbQueue: q, action: "setDefaultLedger", args: Args(["id": .string("personal")]))
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "id": .string("cash"), "ledgerId": .string("personal"),
            "name": .string("Cash"), "type": .string("cash"), "currency": .string("USD")]))
        for (name, kind) in [("Food", "expense"), ("Income", "income")] {
            try Apply.apply(dbQueue: q, action: "createCategory",
                            args: Args(["ledgerId": .string("personal"), "name": .string(name), "type": .string(kind)]))
        }
        return q
    }

    private func firstCategory(_ q: DatabaseQueue, kind: String) throws -> String {
        try q.read { db in try String.fetchOne(db, sql: "SELECT id FROM categories WHERE ledger_id='personal' AND kind=? LIMIT 1", arguments: [kind])! }
    }
    private func lastAccountPosting(_ q: DatabaseQueue) throws -> String {
        try q.read { db in try String.fetchOne(db, sql: "SELECT id FROM postings WHERE account_id IS NOT NULL ORDER BY rowid DESC LIMIT 1")! }
    }

    /// AddTransactionSheet (expense) → EditTransactionSheet (header) → swipe delete.
    func test_addEditDeleteTransactionFlow() throws {
        let q = try seededStarter()
        let food = try firstCategory(q, kind: "expense")
        // Add (expense): amount signed negative, in the account currency.
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("personal"), "accountId": .string("cash"), "amount": .double(-12.5),
            "merchant": .string("Coffee"), "categoryId": .string(food), "date": .string("2026-05-01"), "time": .string("09:30")]))
        let txId = try lastAccountPosting(q)
        // Edit header (merchant/note/date) — the EditTransactionSheet patch.
        try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
            "id": .string(txId), "patch": .object(["merchant": .string("Latte"), "note": .string("am"), "date": .string("2026-05-02"), "time": .string("08:00")])]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT description FROM entries"), "Latte")
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='cash'") ?? 0, -12.5, accuracy: 0.001)
        }
        // Delete (swipe).
        try Apply.apply(dbQueue: q, action: "deleteTransaction", args: Args(["id": .string(txId)]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries"), 0)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='cash'") ?? 0, 0, accuracy: 0.001)
        }
    }

    /// Category edit (EditTransaction picker + bulk recategorize) via the
    /// bulkRecategorize action — re-points the category leg, balance unchanged.
    func test_recategorizeFlow() throws {
        let q = try seededStarter()
        let food = try firstCategory(q, kind: "expense")
        // add a second expense category to move into
        try Apply.apply(dbQueue: q, action: "createCategory", args: Args(["ledgerId": .string("personal"), "name": .string("Transport"), "type": .string("expense")]))
        let transport = try q.read { db in try String.fetchOne(db, sql: "SELECT id FROM categories WHERE name='Transport'")! }
        for (i, amt) in [(-10.0), (-20.0)].enumerated() {
            try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
                "ledgerId": .string("personal"), "accountId": .string("cash"), "amount": .double(amt),
                "merchant": .string("Tx\(i)"), "categoryId": .string(food), "date": .string("2026-05-0\(i+1)"), "skipRules": .bool(true)]))
        }
        let txIds = try q.read { db in try String.fetchAll(db, sql: "SELECT id FROM postings WHERE account_id='cash' ORDER BY rowid") }
        // single (EditTransaction path): move tx0 → Transport
        try Apply.apply(dbQueue: q, action: "bulkRecategorize", args: Args(["ids": .array([.string(txIds[0])]), "categoryId": .string(transport)]))
        // bulk (Activity multi-select): move both → Transport
        try Apply.apply(dbQueue: q, action: "bulkRecategorize", args: Args(["ids": .array(txIds.map { .string($0) }), "categoryId": .string(transport)]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE category_id=?", arguments: [transport]), 2)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE category_id=?", arguments: [food]), 0)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='cash'") ?? 0, -30, accuracy: 0.001)
        }
    }

    /// Pending review: add a pending tx, confirm-all → balance moves.
    func test_pendingConfirmFlow() throws {
        let q = try seededStarter()
        let food = try firstCategory(q, kind: "expense")
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("personal"), "accountId": .string("cash"), "amount": .double(-5),
            "merchant": .string("Pending"), "categoryId": .string(food), "date": .string("2026-05-01"), "status": .string("pending")]))
        XCTAssertEqual(try q.read { db in try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='cash'") ?? -1 }, 0, accuracy: 0.001)
        try Apply.apply(dbQueue: q, action: "confirmAllPending", args: Args([:]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE status='pending'"), 0)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='cash'") ?? 0, -5, accuracy: 0.001)
        }
    }

    /// AddBudgetSheet → BudgetsTab delete (removeBudget).
    func test_budgetCreateDeleteFlow() throws {
        let q = try seededStarter()
        let food = try firstCategory(q, kind: "expense")
        try Apply.apply(dbQueue: q, action: "createBudget", args: Args([
            "ledgerId": .string("personal"), "name": .string("Food"), "type": .string("expense"),
            "amount": .double(300), "frequency": .string("monthly"), "categoryIds": .array([.string(food)])]))
        let bid = try q.read { db in try String.fetchOne(db, sql: "SELECT id FROM budgets LIMIT 1")! }
        try q.read { db in XCTAssertEqual(try String.fetchOne(db, sql: "SELECT category_ids FROM budgets WHERE id=?", arguments: [bid]), "[\"\(food)\"]") }
        try Apply.apply(dbQueue: q, action: "removeBudget", args: Args(["id": .string(bid)]))
        XCTAssertEqual(try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM budgets") }, 0)
    }

    /// AddScheduledSheet → ScheduledTab Post-now (templateId) → Delete.
    func test_scheduledCreatePostDeleteFlow() throws {
        let q = try seededStarter()
        let food = try firstCategory(q, kind: "expense")
        try Apply.apply(dbQueue: q, action: "createScheduled", args: Args([
            "ledgerId": .string("personal"), "name": .string("Rent"), "type": .string("expense"),
            "amount": .double(1500), "accountId": .string("cash"), "frequency": .string("monthly"),
            "dayOfMonth": .double(1), "category": .string(food), "startDate": .string("2026-01-01")]))
        let sid = try q.read { db in try String.fetchOne(db, sql: "SELECT id FROM scheduled_templates LIMIT 1")! }
        try Apply.apply(dbQueue: q, action: "postScheduled", args: Args(["templateId": .string(sid)]))
        XCTAssertEqual(try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE source_template_id=?", arguments: [sid]) }, 1)
        try Apply.apply(dbQueue: q, action: "deleteScheduled", args: Args(["id": .string(sid)]))
        XCTAssertEqual(try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scheduled_templates") }, 0)
    }

    /// Tag admin (create/rename/delete) + reconcile (statement balance → adjustment).
    func test_tagAdminAndReconcileFlow() throws {
        let q = try seededStarter()
        try Apply.apply(dbQueue: q, action: "createTag", args: Args(["ledgerId": .string("personal"), "name": .string("work")]))
        let tags = try Projection.tags(dbQueue: q, ledgerId: "personal")
        XCTAssertEqual(tags.map(\.name), ["work"])
        try Apply.apply(dbQueue: q, action: "updateTag", args: Args(["id": .string(tags[0].id), "patch": .object(["name": .string("business")])]))
        XCTAssertEqual(try Projection.tags(dbQueue: q, ledgerId: "personal").first?.name, "business")
        try Apply.apply(dbQueue: q, action: "deleteTag", args: Args(["id": .string(tags[0].id)]))
        XCTAssertTrue(try Projection.tags(dbQueue: q, ledgerId: "personal").isEmpty)

        // Reconcile Cash (opening 0) to a $250 statement → posts a +250 adjustment.
        try Apply.apply(dbQueue: q, action: "reconcileAccount", args: Args([
            "accountId": .string("cash"), "statementBalance": .double(250),
            "statementDate": .string("2026-05-31"), "postAdjustment": .bool(true)]))
        XCTAssertEqual(try q.read { db in try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='cash'") ?? -1 }, 250, accuracy: 0.001)
    }

    /// LedgerManagementView: create → rename → change base → set default → delete.
    func test_ledgerCrudFlow() throws {
        let q = try seededStarter()
        try Apply.apply(dbQueue: q, action: "createLedger", args: Args(["id": .string("biz"), "name": .string("Biz"), "base": .string("USD")]))
        try Apply.apply(dbQueue: q, action: "updateLedger", args: Args(["id": .string("biz"), "patch": .object(["name": .string("Business")])]))
        try Apply.apply(dbQueue: q, action: "changeLedgerBase", args: Args(["ledgerId": .string("biz"), "newBase": .string("EUR")]))
        try Apply.apply(dbQueue: q, action: "setDefaultLedger", args: Args(["id": .string("biz")]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT name FROM ledgers WHERE id='biz'"), "Business")
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT base_currency FROM ledgers WHERE id='biz'"), "EUR")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT is_default FROM ledgers WHERE id='biz'"), 1)
        }
        try Apply.apply(dbQueue: q, action: "deleteLedger", args: Args(["id": .string("biz")]))
        XCTAssertNil(try q.read { db in try String.fetchOne(db, sql: "SELECT id FROM ledgers WHERE id='biz'") })
    }

    /// Holdings: add to an investment account → set price → delete.
    func test_holdingsFlow() throws {
        let q = try seededStarter()
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "id": .string("inv"), "ledgerId": .string("personal"),
            "name": .string("Brokerage"), "type": .string("investment"), "currency": .string("USD")]))
        try Apply.apply(dbQueue: q, action: "createHolding", args: Args([
            "ledgerId": .string("personal"), "accountId": .string("inv"),
            "symbol": .string("aapl"), "shares": .double(10), "costBasis": .double(1500), "lastPrice": .double(180)]))
        let hid = try q.read { db in try String.fetchOne(db, sql: "SELECT id FROM holdings LIMIT 1")! }
        try q.read { db in XCTAssertEqual(try String.fetchOne(db, sql: "SELECT symbol FROM holdings WHERE id=?", arguments: [hid]), "AAPL") }
        try Apply.apply(dbQueue: q, action: "setHoldingPrice", args: Args(["id": .string(hid), "price": .double(200), "date": .string("2026-05-01")]))
        XCTAssertEqual(try q.read { db in try Double.fetchOne(db, sql: "SELECT last_price FROM holdings WHERE id=?", arguments: [hid]) ?? 0 }, 200, accuracy: 0.001)
        try Apply.apply(dbQueue: q, action: "deleteHolding", args: Args(["id": .string(hid)]))
        XCTAssertEqual(try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM holdings") }, 0)
    }
}
