import XCTest
import GRDB
@testable import FinchCore

/// Mirror of the web `select-budgets` / `select.test.ts` budget-matching cases
/// (INCOME_BUDGET_MATCHING): income goals sum real matched inflows on top of the
/// `saved` offset, match by tag/merchant (AND across dims, OR within, empty =
/// unconstrained), and count incoming transfer legs — while expense budgets keep
/// excluding transfers. Plus an end-to-end create/patch/projection round-trip for
/// the new `tag_ids`/`counterparty_ids` columns.
final class BudgetMatchingTests: XCTestCase {

    // A one-shot income goal by default (mirrors the web `bgt` helper).
    private func bgt(type: String = "income", isRecurring: Int = 0, saved: Double = 0,
                     amount: Double = 1000, accountIds: [String] = [], categoryIds: [String] = [],
                     tagIds: [String] = [], counterpartyIds: [String] = [],
                     startDate: String = "2026-01-01", frequency: String = "monthly") -> BudgetRow {
        BudgetRow(id: "b1", ledgerId: "personal", groupId: nil, name: "Goal", type: type,
                  amount: amount, saved: saved, carryForward: 0, frequency: frequency,
                  startDate: startDate, endDate: nil, isRecurring: isRecurring, rollover: 0,
                  rolloverLimit: nil, pendingAmount: nil, lastRolledPeriod: nil,
                  accountIds: accountIds, categoryIds: categoryIds,
                  tagIds: tagIds, counterpartyIds: counterpartyIds, warningPct: 80)
    }

    private func tx(_ amount: Double, _ date: String, account: String = "chk", category: String? = nil,
                    kind: String? = nil, tags: [String]? = nil, counterpartyId: String? = nil,
                    pending: Bool? = nil) -> Tx {
        Tx(id: UUID().uuidString, merchant: "M", category: category, amount: amount,
           account: account, date: date, pending: pending, ledgerId: "personal",
           kind: kind, counterpartyId: counterpartyId, tags: tags)
    }

    // (a) one-shot income goal = saved offset + Σ matched inflows.
    func test_oneShotIncomeGoal_savedOffsetPlusMatchedInflows() {
        let budget = bgt(type: "income", isRecurring: 0, saved: 50, categoryIds: ["salary"])
        let txns = [
            tx(30, "2026-03-01", category: "salary", kind: "income"),
            tx(20, "2026-04-01", category: "salary", kind: "income"),
            tx(999, "2026-04-02", category: "other", kind: "income"),   // wrong category, ignored
            tx(-400, "2026-04-03", category: "salary", kind: "income"), // outflow ignored for income
        ]
        XCTAssertEqual(Selectors.budgetProgress(budget, txns, "2026-06-01").used, 100, accuracy: 0.001) // 50+30+20
    }

    // (b) tag filter: OR-within, AND-across other dims; empty dims unconstrained.
    func test_tagFilter_orWithin_andAcross_emptyUnconstrained() {
        let budget = bgt(type: "income", isRecurring: 0, saved: 0, accountIds: ["chk"], tagIds: ["work", "bonus"])
        let txns = [
            tx(40, "2026-03-01", account: "chk", kind: "income", tags: ["work"]),   // tag ok, acct ok
            tx(15, "2026-03-02", account: "chk", kind: "income", tags: ["bonus"]),  // OR-within
            tx(70, "2026-03-03", account: "sav", kind: "income", tags: ["work"]),   // wrong account (AND-across)
            tx(60, "2026-03-04", account: "chk", kind: "income", tags: ["misc"]),   // no matching tag
            tx(25, "2026-03-05", account: "chk", kind: "income"),                    // no tags at all
        ]
        XCTAssertEqual(Selectors.budgetProgress(budget, txns, "2026-06-01").used, 55, accuracy: 0.001) // 40+15

        // Empty tag dim is unconstrained: an account-only goal counts every inflow.
        let acctOnly = bgt(type: "income", isRecurring: 0, saved: 0, accountIds: ["chk"])
        XCTAssertEqual(Selectors.budgetProgress(acctOnly, txns, "2026-06-01").used, 140, accuracy: 0.001) // 40+15+60+25
    }

    // (c) counterparty filter matches only listed merchants.
    func test_counterpartyFilter_matchesOnlyListedMerchants() {
        let budget = bgt(type: "income", isRecurring: 0, saved: 0, counterpartyIds: ["c1"])
        let txns = [
            tx(50, "2026-03-01", kind: "income", counterpartyId: "c1"),
            tx(80, "2026-03-02", kind: "income", counterpartyId: "c2"), // wrong merchant
            tx(30, "2026-03-03", kind: "income"),                        // no merchant
        ]
        XCTAssertEqual(Selectors.budgetProgress(budget, txns, "2026-06-01").used, 50, accuracy: 0.001)
    }

    // (d) income goals count incoming transfer legs; expense budgets exclude transfers.
    func test_incomeGoalsCountTransferLegs_expenseExcludesThem() {
        let transfer = tx(200, "2026-03-10", account: "sav", category: nil, kind: "transfer")
        let spend = tx(-40, "2026-03-11", account: "sav", category: "food", kind: "expense")

        let goal = bgt(type: "income", isRecurring: 0, saved: 0, accountIds: ["sav"])
        XCTAssertEqual(Selectors.budgetProgress(goal, [transfer, spend], "2026-03-15").used, 200, accuracy: 0.001)

        let expense = bgt(type: "expense", isRecurring: 1, amount: 500, accountIds: ["sav"])
        XCTAssertEqual(Selectors.budgetProgress(expense, [transfer, spend], "2026-03-15").used, 40, accuracy: 0.001)

        // The goal's matched-transactions list surfaces the incoming transfer leg;
        // the expense budget's list does not.
        XCTAssertEqual(Selectors.budgetMatchedTransactions(goal, [transfer, spend], "2026-03-15").map(\.amount), [200])
        XCTAssertEqual(Selectors.budgetMatchedTransactions(expense, [transfer, spend], "2026-03-15").map(\.amount), [-40])
    }

    // End-to-end: createBudget persists tag_ids/counterparty_ids, the projection
    // parses them back, and updateBudget patches them (mirrors the web columns).
    func test_createAndPatch_tagAndCounterpartyIds_roundTrip() throws {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
        }
        try Apply.apply(dbQueue: q, action: "createBudget", args: Args([
            "id": .string("b1"), "ledgerId": .string("l1"), "name": .string("Paychecks"),
            "type": .string("income"), "amount": .double(5000), "startDate": .string("2026-01-01"),
            "tagIds": .array([.string("work"), .string("bonus")]),
            "counterpartyIds": .array([.string("acme")]),
        ]))
        // Stored as JSON-array text (idsToJson), empty list → NULL.
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT tag_ids FROM budgets WHERE id='b1'"), "[\"work\",\"bonus\"]")
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT counterparty_ids FROM budgets WHERE id='b1'"), "[\"acme\"]")
        }
        var b = try Projection.budgets(dbQueue: q, ledgerId: "l1").first { $0.id == "b1" }!
        XCTAssertEqual(b.tagIds, ["work", "bonus"])
        XCTAssertEqual(b.counterpartyIds, ["acme"])

        // Patch both array dims + the saved offset.
        try Apply.apply(dbQueue: q, action: "updateBudget", args: Args(["id": .string("b1"), "patch": .object([
            "tagIds": .array([.string("work")]), "counterpartyIds": .array([]), "saved": .double(1200),
        ])]))
        b = try Projection.budgets(dbQueue: q, ledgerId: "l1").first { $0.id == "b1" }!
        XCTAssertEqual(b.tagIds, ["work"])
        XCTAssertEqual(b.counterpartyIds, [])   // emptied → NULL → []
        XCTAssertEqual(b.saved, 1200, accuracy: 0.001)
    }
}
