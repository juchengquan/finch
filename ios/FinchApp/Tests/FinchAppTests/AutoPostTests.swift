import XCTest
@testable import FinchApp
import FinchCore
import SwiftUI

/// The app half of auto-post: the store's generator call (what launch, foreground
/// and unlock run), and the two other ways an occurrence gets posted — the
/// notification's "Confirm now" and the manual Post — which must not add a second
/// row for an occurrence auto-post already added.
@MainActor
final class AutoPostTests: XCTestCase {
    /// A real store on the round-trip sample pack, with no auto-post mark yet —
    /// exactly what an existing install looks like on its first launch with this.
    private func makeStore() async throws -> FinchStore {
        let packURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: packURL))
        return store
    }

    /// A DAILY template that started a year ago, so a back-fill would be ~365 rows
    /// and "only today" is unambiguous whatever day the suite runs.
    @discardableResult
    private func createDaily(_ store: FinchStore, autoPost: Bool, type: String = "expense") throws -> String {
        let accounts = store.accounts.map(\.id)
        let id = "sch-\(UUID().uuidString.prefix(8))"
        var args: [String: JSONValue] = [
            "id": .string(id), "ledgerId": .string(store.activeLedgerId), "name": .string("Coffee \(id)"),
            "type": .string(type), "amount": .double(4), "frequency": .string("daily"),
            "accountId": .string(try XCTUnwrap(accounts.first)),
            "startDate": .string(Selectors.horizonDay(from: store.wallToday, addingDays: -365)),
            "autoPost": .bool(autoPost),
        ]
        if type == "transfer" { args["fromAccountId"] = .string(try XCTUnwrap(accounts.dropFirst().first)) }
        try store.apply(.createScheduled, Args(args))
        return id
    }

    private func rows(_ store: FinchStore, _ templateId: String) -> [Tx] {
        store.txns.filter { $0.sourceTemplateId == templateId }
    }

    // MARK: - The generator call

    /// What a launch runs: today's occurrence, PENDING, dated the real calendar day
    /// — and none of the 365 earlier ones.
    func test_launchRun_addsTodayOnly_asPending_onTheWallClockDay() async throws {
        let store = try await makeStore()
        let id = try createDaily(store, autoPost: true)
        let posted = await store.autoPostDueScheduled()
        XCTAssertEqual(posted, 1, "a year-old daily template must not back-fill on first run")
        let added = rows(store, id)
        XCTAssertEqual(added.count, 1, "the store reprojected — the row is in txns")
        XCTAssertEqual(added.first?.date, store.wallToday)
        XCTAssertEqual(added.first?.occurrenceDate, store.wallToday)
        XCTAssertEqual(added.first?.pending, true, "income/expense wait in To confirm")
    }

    /// Foreground runs after that find nothing, and write nothing.
    func test_repeatRun_isANoOp() async throws {
        let store = try await makeStore()
        let id = try createDaily(store, autoPost: true)
        await store.autoPostDueScheduled()
        // Let the writes so far (the pack load, the create, that run) settle their
        // debounced ambient rounds before counting.
        try await Task.sleep(for: FinchStore.ambientDebounce * 3)
        let runsBefore = store.ambientRunCount
        let again = await store.autoPostDueScheduled()
        XCTAssertEqual(again, 0)
        XCTAssertEqual(rows(store, id).count, 1)
        // Give a debounced ambient round time to fire if one had been queued.
        try await Task.sleep(for: FinchStore.ambientDebounce * 3)
        XCTAssertEqual(store.ambientRunCount, runsBefore, "a run that posts nothing fires no write side-effects")
    }

    func test_manualTemplate_isLeftAlone() async throws {
        let store = try await makeStore()
        let id = try createDaily(store, autoPost: false)
        let posted = await store.autoPostDueScheduled()
        XCTAssertEqual(posted, 0)
        XCTAssertTrue(rows(store, id).isEmpty)
    }

    func test_transfer_isRecordedConfirmed() async throws {
        let store = try await makeStore()
        let id = try createDaily(store, autoPost: true, type: "transfer")
        await store.autoPostDueScheduled()
        let added = rows(store, id)
        XCTAssertFalse(added.isEmpty)
        XCTAssertTrue(added.allSatisfy { $0.pending != true }, "a transfer between your own accounts posts confirmed")
    }

    /// The projection hands the flag to the sheet and the planner.
    func test_projectionCarriesTheFlag() async throws {
        let store = try await makeStore()
        let on = try createDaily(store, autoPost: true)
        let off = try createDaily(store, autoPost: false)
        XCTAssertEqual(store.scheduled.first { $0.id == on }?.postsAutomatically, true)
        XCTAssertEqual(store.scheduled.first { $0.id == off }?.postsAutomatically, false)
    }

    // MARK: - "Confirm now" from the notification

    /// Auto-post already added today's row: Confirm now confirms THAT row. It used to
    /// post, and `resumeOccurrence` — counting the pending row as resolved — would
    /// have booked tomorrow's occurrence instead.
    func test_confirmNow_confirmsTheAutoPostedRow_insteadOfPostingAnother() async throws {
        let store = try await makeStore()
        let id = try createDaily(store, autoPost: true)
        await store.autoPostDueScheduled()
        NotificationService.confirmNow(templateId: id, store: store)
        let after = rows(store, id)
        XCTAssertEqual(after.count, 1, "no second row")
        XCTAssertEqual(after.first?.pending, false, "the waiting row was confirmed")
        XCTAssertEqual(after.first?.occurrenceDate, store.wallToday)
    }

    /// Confirm now got there first (the app was cold-launched by the button): the
    /// generator then sees today as done.
    func test_confirmNowFirst_thenTheGenerator_addsNothing() async throws {
        let store = try await makeStore()
        let id = try createDaily(store, autoPost: true)
        // Starting today, so the occurrence Confirm now resolves is today's (it takes
        // the oldest unposted one).
        try store.apply(.updateScheduled, Args(["id": .string(id), "patch": .object([
            "startDate": .string(store.wallToday)])]))
        NotificationService.confirmNow(templateId: id, store: store)
        XCTAssertEqual(rows(store, id).map(\.occurrenceDate), [store.wallToday])
        let posted = await store.autoPostDueScheduled()
        XCTAssertEqual(posted, 0)
        XCTAssertEqual(rows(store, id).count, 1)
    }

    /// With nothing waiting, Confirm now keeps its old behaviour and posts.
    func test_confirmNow_withNothingWaiting_posts() async throws {
        let store = try await makeStore()
        let id = try createDaily(store, autoPost: false)
        try store.apply(.updateScheduled, Args(["id": .string(id), "patch": .object([
            "startDate": .string(store.wallToday)])]))
        NotificationService.confirmNow(templateId: id, store: store)
        XCTAssertEqual(rows(store, id).count, 1)
        XCTAssertEqual(rows(store, id).first?.pending, false)
    }

    // MARK: - The manual Post

    /// Post on an occurrence auto-post already added — the UIKit list offers Post on
    /// every occurrence row — is refused instead of opening a sheet for a duplicate.
    func test_manualPost_onAnAutoPostedOccurrence_isRefused() async throws {
        let store = try await makeStore()
        let id = try createDaily(store, autoPost: true)
        await store.autoPostDueScheduled()
        let t = try XCTUnwrap(store.scheduled.first { $0.id == id })
        var prefill: PostPrefill?
        var error: String?
        ScheduledPoster.postNow(t, occurrence: store.wallToday, store: store,
                                prefill: Binding(get: { prefill }, set: { prefill = $0 }),
                                errorMessage: Binding(get: { error }, set: { error = $0 }))
        XCTAssertNil(prefill, "no sheet for a duplicate")
        XCTAssertNotNil(error)
        XCTAssertEqual(rows(store, id).count, 1)
    }

    /// A bare Post (no occurrence in hand) resolves PAST the waiting one, as it always
    /// has for a pending row — it never re-posts it.
    func test_bareManualPost_doesNotResolveTheWaitingOccurrence() async throws {
        let store = try await makeStore()
        let id = try createDaily(store, autoPost: true)
        try store.apply(.updateScheduled, Args(["id": .string(id), "patch": .object([
            "startDate": .string(store.wallToday)])]))
        await store.autoPostDueScheduled()
        let t = try XCTUnwrap(store.scheduled.first { $0.id == id })
        var prefill: PostPrefill?
        var error: String?
        ScheduledPoster.postNow(t, store: store,
                                prefill: Binding(get: { prefill }, set: { prefill = $0 }),
                                errorMessage: Binding(get: { error }, set: { error = $0 }))
        XCTAssertNil(error)
        XCTAssertEqual(prefill?.occurrence, Selectors.horizonDay(from: store.wallToday, addingDays: 1),
                       "today's is waiting, so the next one is offered")
    }

    // MARK: - Reminders

    /// The planner does not remind about auto-post templates: their occurrences
    /// arrive in To confirm on their own.
    func test_planner_skipsAutoPostTemplates() {
        func template(_ id: String, autoPost: Int?) -> ScheduledTemplate {
            ScheduledTemplate(id: id, name: id, type: "expense", amount: 10, frequency: "monthly",
                              dayOfMonth: 1, accountId: "a1", nextRun: "2026-05-01", autoPost: autoPost)
        }
        let planned = NotificationPlanner.plan(
            budgets: [], txns: [], scheduled: [template("manual", autoPost: 0), template("auto", autoPost: 1),
                                              template("legacy", autoPost: nil)],
            categories: [], today: "2026-05-15", wallToday: "2026-05-15", ledgerId: "l1",
            enabled: Set(NotificationKind.allCases), money: { "\($0)" })
        XCTAssertEqual(planned.filter { $0.kind == .scheduledDue }.compactMap(\.focusId), ["manual", "legacy"])
    }
}
