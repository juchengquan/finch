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

    /// `route` alone doesn't prove the WIRING: `ScheduledTab.postNow` must feed
    /// it the real split count from `store.scheduledSplitCount(templateId:)`,
    /// not a stray literal — a regression hardcoding `splitCount: 0` at that
    /// call site would silently collapse split-income postings back to one,
    /// with every test above still green (they only exercise the pure
    /// decision). `routeForPost` is the actual call `ScheduledTab` makes, so
    /// exercising IT against a real store + real splits closes that gap.
    @MainActor
    func test_routeForPost_readsRealSplitCountFromStore() async throws {
        let packURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: packURL))
        let accountId = try XCTUnwrap(store.accounts.first?.id)

        let templateId = "sch-\(UUID().uuidString.prefix(8))"
        try store.apply(.createScheduled, Args([
            "id": .string(templateId), "ledgerId": .string(store.activeLedgerId), "name": .string("Paycheck"),
            "type": .string("income"), "amount": .double(4200), "frequency": .string("monthly"),
            "dayOfMonth": .int(1), "accountId": .string(accountId),
        ]))
        let bare = try XCTUnwrap(store.scheduled.first { $0.id == templateId })
        XCTAssertEqual(ScheduledPostRouting.routeForPost(bare, store: store), .sheet,
                        "no splits yet — must not silently swallow the posting")

        try store.apply(.addScheduledSplit, Args(["templateId": .string(templateId), "accountId": .string(accountId), "pct": .double(50)]))
        try store.apply(.addScheduledSplit, Args(["templateId": .string(templateId), "accountId": .string(accountId), "pct": .double(50)]))
        let withSplits = try XCTUnwrap(store.scheduled.first { $0.id == templateId })

        XCTAssertEqual(store.scheduledSplitCount(templateId: templateId), 2, "the store must report the real split count")
        XCTAssertEqual(ScheduledPostRouting.routeForPost(withSplits, store: store), .silent,
                        "a regression hardcoding splitCount: 0 at the call site would make this .sheet instead")
    }
}
