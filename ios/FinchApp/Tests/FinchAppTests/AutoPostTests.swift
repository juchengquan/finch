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

    // MARK: - "Missed" means missed

    /// A row auto-post added and the user deleted stays deleted: the next foreground
    /// the same day re-covers the mark's own day and used to add it straight back.
    /// The delete counts as skipping the occurrence, so the row does not read
    /// overdue either — and Undo brings back the row and un-skips it.
    func test_deletedAutoPostedRow_staysDeleted_andUndoBringsItBack() async throws {
        let store = try await makeStore()
        let id = try createDaily(store, autoPost: true)
        await store.autoPostDueScheduled()
        let row = try XCTUnwrap(rows(store, id).first)
        try store.deleteTransaction(row.id)
        let posted = await store.autoPostDueScheduled()
        XCTAssertEqual(posted, 0, "the same day's next foreground adds nothing")
        XCTAssertTrue(rows(store, id).isEmpty)
        var t = try XCTUnwrap(store.scheduled.first { $0.id == id })
        XCTAssertEqual(t.skippedDates, [store.wallToday])
        let due = ScheduledCaption.due(t, posted: Selectors.scheduledPostedMap(store.txns), today: store.wallToday)
        XCTAssertEqual(due?.date, Selectors.horizonDay(from: store.wallToday, addingDays: 1))
        XCTAssertEqual(due?.overdue, false)

        try store.undoDelete()
        XCTAssertEqual(rows(store, id).map(\.id), [row.id], "the row is back")
        t = try XCTUnwrap(store.scheduled.first { $0.id == id })
        XCTAssertNil(t.skippedDates, "and its occurrence is not skipped any more")
    }

    /// The bulk delete goes the same way.
    func test_bulkDeletedAutoPostedRow_isSkippedToo() async throws {
        let store = try await makeStore()
        let id = try createDaily(store, autoPost: true, type: "transfer")
        await store.autoPostDueScheduled()
        // One transfer, two legs in the feed; the user ticks the one row it shows.
        XCTAssertEqual(store.deleteTransactions([try XCTUnwrap(rows(store, id).first).id]), 1)
        await store.autoPostDueScheduled()
        XCTAssertTrue(rows(store, id).isEmpty, "a transfer must not move the money twice")
        XCTAssertEqual(store.scheduled.first { $0.id == id }?.skippedDates, [store.wallToday])
    }

    /// A new "Add automatically" item with a past start date: auto-post never
    /// back-fills, so a year of earlier days is not overdue.
    func test_newAutoTemplateWithAPastStart_isNotOverdue() async throws {
        let store = try await makeStore()
        let id = try createDaily(store, autoPost: true)
        await store.autoPostDueScheduled()
        let t = try XCTUnwrap(store.scheduled.first { $0.id == id })
        let caption = ScheduledCaption.cadence(t, posted: Selectors.scheduledPostedMap(store.txns), today: store.wallToday)
        XCTAssertFalse(caption.overdue, caption.text)
    }

    /// …even on a day it posts nothing. That run fires no write side-effects, but it
    /// still records when auto-post began, and the store republishes the templates
    /// for it — otherwise the row read "overdue" until the next unrelated write.
    func test_aRunThatPostsNothing_stillPublishesWhenAutoPostBegan() async throws {
        let store = try await makeStore()
        let id = try createDaily(store, autoPost: true)
        // Weekly on tomorrow's weekday: a year of past occurrences, none today.
        let tomorrow = try XCTUnwrap(AppDate.isoDay.date(from: Selectors.horizonDay(from: store.wallToday, addingDays: 1)))
        let weekDay = Calendar(identifier: .gregorian).component(.weekday, from: tomorrow) - 1
        try store.apply(.updateScheduled, Args(["id": .string(id), "patch": .object([
            "frequency": .string("weekly"), "weekDay": .int(weekDay)])]))
        let before = try XCTUnwrap(store.scheduled.first { $0.id == id })
        XCTAssertTrue(ScheduledCaption.due(before, posted: [:], today: store.wallToday)?.overdue ?? false,
                      "precondition: before auto-post ran, the past start reads overdue")
        let posted = await store.autoPostDueScheduled()
        XCTAssertEqual(posted, 0)
        let t = try XCTUnwrap(store.scheduled.first { $0.id == id })
        XCTAssertNotNil(t.autoPostSince)
        XCTAssertEqual(ScheduledCaption.due(t, posted: Selectors.scheduledPostedMap(store.txns), today: store.wallToday)?.overdue,
                       false)
    }

    /// The past-due reminder reads the same `resumeOccurrence`: a paid monthly item
    /// moved to another day of the month is not "due" from its history.
    func test_planner_aRescheduledPaidItem_isNotPastDue() {
        let t = ScheduledTemplate(id: "rent", name: "Rent", type: "expense", amount: 100, frequency: "monthly",
                                  dayOfMonth: 20, accountId: "a1", startDate: "2026-01-15", nextRun: "", autoPost: 0)
        let paid = (1...10).map { m in
            Tx(id: "p\(m)", merchant: "Rent", amount: -100, account: "a1", date: String(format: "2026-%02d-15", m),
               ledgerId: "l1", sourceTemplateId: "rent")
        }
        let planned = NotificationPlanner.plan(
            budgets: [], txns: paid, scheduled: [t], categories: [], today: "2026-10-19", wallToday: "2026-10-19",
            ledgerId: "l1", enabled: Set(NotificationKind.allCases), money: { "\($0)" })
        let due = planned.first { $0.kind == .scheduledDue && $0.focusId == "rent" }
        XCTAssertNotNil(due?.deliverOn, "a future reminder for Oct 20, not a past-due one for Jan 20")
    }
}
