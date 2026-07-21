import XCTest
@testable import FinchApp
import FinchCore

/// Which templates the edit sheet can faithfully represent. Split-income templates
/// fan out across MULTIPLE ACCOUNTS; the sheet's splits are categories within ONE
/// transaction — a different concept — so those keep the silent engine path.
final class ScheduledPostRoutingTests: XCTestCase {
    private func t(amount: Double?, type: String = "expense") -> ScheduledTemplate {
        ScheduledTemplate(id: "s1", name: "Gym", description: nil, type: type, amount: amount,
                          frequency: "monthly", dayOfMonth: 15, weekDay: nil, accountId: "a1",
                          fromAccountId: nil, startDate: "2026-01-15", endDate: nil,
                          nextRun: "", maxExecutions: nil, installmentTotal: nil, installmentPaid: nil)
    }

    func test_simpleTemplate_opensSheet() {
        XCTAssertEqual(ScheduledPostRouting.route(t(amount: -40), splitCount: 0), .sheet)
    }

    func test_variableAmountTemplate_opensSheet() {   // today this ERRORS in the engine
        XCTAssertEqual(ScheduledPostRouting.route(t(amount: nil), splitCount: 0), .sheet)
    }

    func test_transferTemplate_opensSheet() {
        XCTAssertEqual(ScheduledPostRouting.route(t(amount: -40, type: "transfer"), splitCount: 0), .sheet)
    }

    func test_splitIncomeTemplate_staysSilent() {
        XCTAssertEqual(ScheduledPostRouting.route(t(amount: 4200, type: "income"), splitCount: 2), .silent)
    }

    func test_incomeWithoutSplits_opensSheet() {
        XCTAssertEqual(ScheduledPostRouting.route(t(amount: 4200, type: "income"), splitCount: 0), .sheet)
    }
}
