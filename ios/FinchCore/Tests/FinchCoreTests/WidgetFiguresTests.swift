import XCTest
@testable import FinchCore

/// The figures the widget and the Watch show at a glance.
final class WidgetFiguresTests: XCTestCase {
    private func tx(_ amount: Double, _ date: String, kind: String = "expense", pending: Bool = false,
                    category: String? = "food", ledger: String = "l1") -> Tx {
        Tx(id: UUID().uuidString, merchant: "M", category: category, amount: amount, account: "a1",
           date: date, pending: pending, ledgerId: ledger, currency: "USD", nativeAmount: amount, kind: kind)
    }

    /// "This week" is Monday through today. It used to be the last COMPLETED week,
    /// so on a Wednesday after a $300 Monday the widget showed last week's total.
    func test_spentThisWeek_is_monday_through_today() {
        let txns = [
            tx(-300, "2026-11-23"),                  // Monday this week
            tx(-20, "2026-11-25"),                   // today (Wednesday)
            tx(15, "2026-11-24", kind: "refund"),    // money back nets off
            tx(-999, "2026-11-22"),                  // last Sunday — last week
            tx(-50, "2026-11-26"),                   // tomorrow (scheduled ahead)
            tx(-70, "2026-11-24", pending: true),    // not confirmed
            tx(5000, "2026-11-24", kind: "income", category: "pay"),
            tx(-40, "2026-11-24", ledger: "l2"),     // another ledger
        ]
        XCTAssertEqual(Selectors.spentThisWeek(txns, "l1", "2026-11-25"), 305, accuracy: 0.001)
        XCTAssertEqual(Selectors.spentThisWeek(txns, "l1", "2026-11-23"), 300, accuracy: 0.001)
        XCTAssertEqual(Selectors.spentThisWeek(txns, "l1", ""), 0)
    }

    /// Income goals aren't spending: $0 of a $10,000 salary goal counted as unused
    /// budget, so $900 of $1,000 spent read 8% instead of 90%.
    func test_budgetUsedPct_leaves_income_goals_out() {
        func budget(_ id: String, _ type: String, _ amount: Double, categories: [String]) -> BudgetRow {
            BudgetRow(id: id, ledgerId: "l1", groupId: nil, name: id, type: type,
                      amount: amount, saved: 0, carryForward: 0, frequency: "monthly",
                      startDate: "2026-11-01", endDate: nil, isRecurring: 1, rollover: 0,
                      rolloverLimit: nil, pendingAmount: nil, lastRolledPeriod: nil,
                      accountIds: [], categoryIds: categories, tagIds: [], counterpartyIds: [], warningPct: 80)
        }
        let budgets = [budget("spend", "expense", 1000, categories: ["food"]),
                       budget("salary", "income", 10000, categories: ["pay"])]
        let pct = WidgetSnapshot.budgetUsedPct(budgets, [tx(-900, "2026-11-10")], "2026-11-25", [])
        XCTAssertEqual(pct, 90)
    }

    func test_a_snapshot_without_the_mask_flag_still_decodes() throws {
        let old = #"{"netWorth":100,"currency":"USD","budgetUsedPct":50,"weeklySpent":20,"generatedAt":"t"}"#
        let snap = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(old.utf8))
        XCTAssertNil(snap.masked)
    }
}
