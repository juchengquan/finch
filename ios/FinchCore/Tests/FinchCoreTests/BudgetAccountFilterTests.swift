import XCTest
import GRDB
@testable import FinchCore

final class BudgetAccountFilterTests: XCTestCase {
    func test_budget_account_scope_vs_all() throws {
        let q = try TestSeed.base()   // l1 / a1 / c1
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "id": .string("a2"), "ledgerId": .string("l1"), "name": .string("Savings"),
            "type": .string("savings"), "currency": .string("USD")]))

        let day = "2026-06-10"
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-100),
            "merchant": .string("M1"), "categoryId": .string("c1"), "date": .string(day), "skipRules": .bool(true)]))
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a2"), "amount": .double(-40),
            "merchant": .string("M2"), "categoryId": .string("c1"), "date": .string(day), "skipRules": .bool(true)]))

        // budget scoped to a1 only
        try Apply.apply(dbQueue: q, action: "createBudget", args: Args([
            "id": .string("b1"), "ledgerId": .string("l1"), "name": .string("A1 only"), "type": .string("expense"),
            "amount": .double(1000), "frequency": .string("monthly"), "startDate": .string("2026-06-01"),
            "accountIds": .array([.string("a1")])]))
        // budget across all accounts (empty accountIds)
        try Apply.apply(dbQueue: q, action: "createBudget", args: Args([
            "id": .string("b2"), "ledgerId": .string("l1"), "name": .string("All"), "type": .string("expense"),
            "amount": .double(1000), "frequency": .string("monthly"), "startDate": .string("2026-06-01")]))

        let budgets = try Projection.budgets(dbQueue: q, ledgerId: "l1")
        let txns = try Projection.run(dbQueue: q, ledgerId: "l1")
        let today = "2026-06-15"
        let b1 = try XCTUnwrap(budgets.first { $0.id == "b1" })
        let b2 = try XCTUnwrap(budgets.first { $0.id == "b2" })

        XCTAssertEqual(b1.accountIds, ["a1"])
        XCTAssertEqual(Selectors.budgetProgress(b1, txns, today).used, 100, accuracy: 0.001)  // a1 only
        XCTAssertEqual(Selectors.budgetProgress(b2, txns, today).used, 140, accuracy: 0.001)  // both
    }
}
