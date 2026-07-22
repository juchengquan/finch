import XCTest
@testable import FinchApp
import FinchCore
import SwiftUI

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

    /// `route` alone doesn't prove the WIRING: `ScheduledPoster.postNow` must feed
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

    // MARK: - ScheduledPoster.postNow: silent path refuses a future occurrence

    /// A store + a 2×50% split-income template anchored at `startDate` — a
    /// "once" template has exactly one occurrence, at `startDate`, so pinning
    /// it pins exactly which date `resumeOccurrence` resolves to, with no
    /// dependence on how the real wall clock happens to line up with a
    /// recurrence rule.
    @MainActor
    private func makeSplitIncomeTemplate(startDate: String) async throws -> (FinchStore, ScheduledTemplate) {
        let packURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: packURL))
        let accountId = try XCTUnwrap(store.accounts.first?.id)

        let templateId = "sch-\(UUID().uuidString.prefix(8))"
        try store.apply(.createScheduled, Args([
            "id": .string(templateId), "ledgerId": .string(store.activeLedgerId), "name": .string("Paycheck"),
            "type": .string("income"), "amount": .double(4200), "frequency": .string("once"),
            "startDate": .string(startDate), "accountId": .string(accountId),
        ]))
        try store.apply(.addScheduledSplit, Args(["templateId": .string(templateId), "accountId": .string(accountId), "pct": .double(50)]))
        try store.apply(.addScheduledSplit, Args(["templateId": .string(templateId), "accountId": .string(accountId), "pct": .double(50)]))
        let t = try XCTUnwrap(store.scheduled.first { $0.id == templateId })
        XCTAssertEqual(store.scheduledSplitCount(templateId: templateId), 2, "setup: template must actually be split-income")
        return (store, t)
    }

    /// A fully-caught-up split-income template with nothing missed and nothing
    /// due today falls forward to a FUTURE occurrence (`resumeOccurrence`'s
    /// documented behaviour). The silent path has no sheet to confirm that date
    /// in, so it must refuse to post — same outcome as "nothing to post" — not
    /// silently book unconfirmed future income.
    @MainActor
    func test_postNow_splitIncome_futureOccurrence_isSuppressedNotPosted() async throws {
        let today = FinchStore.isoDay(Date())
        let future = Selectors.horizonDay(from: today, addingDays: 5)
        let (store, template) = try await makeSplitIncomeTemplate(startDate: future)
        let txCountBefore = store.txns.count

        var prefill: PostPrefill?
        var errorMessage: String?
        let prefillBinding = Binding<PostPrefill?>(get: { prefill }, set: { prefill = $0 })
        let errorBinding = Binding<String?>(get: { errorMessage }, set: { errorMessage = $0 })

        ScheduledPoster.postNow(template, store: store, prefill: prefillBinding, errorMessage: errorBinding)

        XCTAssertNil(prefill, "split-income never opens the sheet, future occurrence or not")
        XCTAssertEqual(errorMessage, "Nothing left to post for \"Paycheck\".",
                        "a future-only occurrence must be refused on the silent path")
        XCTAssertEqual(store.txns.count, txCountBefore, "nothing should have posted")
    }

    /// The same template, but its only occurrence is due TODAY (not missed, not
    /// future). Catch-up on a due occurrence must be completely unaffected by
    /// the future-date guard — the boundary is strict `>`, so `== wallToday`
    /// still posts silently.
    @MainActor
    func test_postNow_splitIncome_dueOccurrence_stillPostsSilently() async throws {
        let today = FinchStore.isoDay(Date())
        let (store, template) = try await makeSplitIncomeTemplate(startDate: today)
        let txCountBefore = store.txns.count

        var prefill: PostPrefill?
        var errorMessage: String?
        let prefillBinding = Binding<PostPrefill?>(get: { prefill }, set: { prefill = $0 })
        let errorBinding = Binding<String?>(get: { errorMessage }, set: { errorMessage = $0 })

        ScheduledPoster.postNow(template, store: store, prefill: prefillBinding, errorMessage: errorBinding)

        XCTAssertNil(errorMessage, "a due (today) occurrence must still post silently")
        XCTAssertNil(prefill)
        XCTAssertEqual(store.txns.count, txCountBefore + 2, "both 50/50 splits should have posted")
    }

    /// The future-date guard applies only to the AUTO-RESOLVE path (bare "Post now",
    /// no cell in hand). The calendar calls the occurrence-taking overload directly
    /// with a cell the user TAPPED — that explicit choice IS the date confirmation,
    /// so a future occurrence must still post silently there, not be refused.
    @MainActor
    func test_postNow_splitIncome_explicitFutureOccurrence_stillPostsSilently() async throws {
        let today = FinchStore.isoDay(Date())
        let future = Selectors.horizonDay(from: today, addingDays: 5)
        let (store, template) = try await makeSplitIncomeTemplate(startDate: future)
        let txCountBefore = store.txns.count

        var prefill: PostPrefill?
        var errorMessage: String?
        let prefillBinding = Binding<PostPrefill?>(get: { prefill }, set: { prefill = $0 })
        let errorBinding = Binding<String?>(get: { errorMessage }, set: { errorMessage = $0 })

        // Occurrence passed explicitly = the calendar tap. Must post, not suppress.
        ScheduledPoster.postNow(template, occurrence: future, store: store,
                                prefill: prefillBinding, errorMessage: errorBinding)

        XCTAssertNil(errorMessage, "an explicitly-tapped future occurrence must still post")
        XCTAssertNil(prefill, "split-income posts silently, no sheet")
        XCTAssertEqual(store.txns.count, txCountBefore + 2, "both 50/50 splits should have posted")
    }
}
