import XCTest
@testable import FinchApp
import FinchCore

/// "Confirm now" books the occurrence its reminder named, and says so when it can't.
///
/// It used to resolve afresh with `resumeOccurrence` and post through `try?`. A
/// reminder for an occurrence since skipped or paid then fell forward and booked a
/// confirmed expense dated weeks ahead, and a refusal (no exchange rate) opened
/// Scheduled with the item still due and no word of why.
@MainActor
final class ConfirmNowOccurrenceTests: XCTestCase {
    /// The store and the test both read the wall clock; see `MidnightGuard`.
    override func setUp() async throws {
        try await MidnightGuard.waitIfClose()
    }

    private func makeStore() async throws -> FinchStore {
        let packURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: packURL))
        return store
    }

    private func day(_ store: FinchStore, _ offset: Int) -> String {
        Selectors.horizonDay(from: store.wallToday, addingDays: offset)
    }

    /// A manual daily template starting three days ago: four occurrences, none posted.
    private func createDaily(_ store: FinchStore, accountId: String? = nil) throws -> String {
        let id = "sch-\(UUID().uuidString.prefix(8))"
        try store.apply(.createScheduled, Args([
            "id": .string(id), "ledgerId": .string(store.activeLedgerId), "name": .string("Coffee"),
            "type": .string("expense"), "amount": .double(4), "frequency": .string("daily"),
            "accountId": .string(try accountId ?? XCTUnwrap(store.accounts.first?.id)),
            "startDate": .string(day(store, -3)), "autoPost": .bool(false),
        ]))
        return id
    }

    private func rows(_ store: FinchStore, _ id: String) -> [Tx] {
        store.txns.filter { $0.sourceTemplateId == id }
    }

    private func assertRefused(_ code: String, _ body: () throws -> Void,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) {
            XCTAssertEqual(($0 as? I18nError)?.code, code, file: file, line: line)
        }
    }

    /// Three days are missed; the reminder named yesterday's. That one is booked, not
    /// the oldest — which is what resolving afresh would pick.
    func test_postsTheNamedOccurrence() async throws {
        let store = try await makeStore()
        let id = try createDaily(store)
        try NotificationService.confirmNow(templateId: id, occurrence: day(store, -1), store: store)
        XCTAssertEqual(rows(store, id).map(\.occurrenceDate), [day(store, -1)])
        XCTAssertEqual(rows(store, id).first?.pending, false)
    }

    func test_refusesAFutureOccurrence() async throws {
        let store = try await makeStore()
        let id = try createDaily(store)
        assertRefused("error.scheduled.notDueYet") {
            try NotificationService.confirmNow(templateId: id, occurrence: day(store, 1), store: store)
        }
        XCTAssertTrue(rows(store, id).isEmpty)
    }

    /// The audit's case: a reminder from before occurrences were named, tapped once
    /// everything up to today is paid. It used to fall forward and book tomorrow's.
    func test_anUndatedReminder_neverFallsForwardIntoTheFuture() async throws {
        let store = try await makeStore()
        let id = try createDaily(store)
        for d in -3...0 {
            try store.apply(.postScheduled, Args(["templateId": .string(id), "date": .string(day(store, d))]))
        }
        assertRefused("error.scheduled.notDueYet") {
            try NotificationService.confirmNow(templateId: id, occurrence: nil, store: store)
        }
        XCTAssertEqual(rows(store, id).count, 4, "nothing dated tomorrow was booked")
    }

    /// Without a date it still catches up as before: the oldest missed.
    func test_anUndatedReminder_postsTheOldestMissed() async throws {
        let store = try await makeStore()
        let id = try createDaily(store)
        try NotificationService.confirmNow(templateId: id, occurrence: nil, store: store)
        XCTAssertEqual(rows(store, id).map(\.occurrenceDate), [day(store, -3)])
    }

    /// Since the reminder: paid from the app, or skipped. Neither is booked again.
    func test_refusesAnOccurrencePaidOrSkippedSince() async throws {
        let store = try await makeStore()
        let id = try createDaily(store)
        try store.apply(.postScheduled, Args(["templateId": .string(id), "date": .string(day(store, -2))]))
        assertRefused("error.scheduled.alreadyPosted") {
            try NotificationService.confirmNow(templateId: id, occurrence: day(store, -2), store: store)
        }
        try store.apply(.skipScheduledOccurrence, Args(["templateId": .string(id), "date": .string(day(store, -1))]))
        assertRefused("error.scheduled.occurrenceSkipped") {
            try NotificationService.confirmNow(templateId: id, occurrence: day(store, -1), store: store)
        }
        XCTAssertEqual(rows(store, id).count, 1)
    }

    /// An edit that moved the schedule: the named day is no longer an occurrence.
    func test_refusesAnOccurrenceAnEditMoved() async throws {
        let store = try await makeStore()
        let id = try createDaily(store)
        try store.apply(.updateScheduled, Args(["id": .string(id), "patch": .object([
            "startDate": .string(store.wallToday)])]))
        assertRefused("error.scheduled.notAnOccurrence") {
            try NotificationService.confirmNow(templateId: id, occurrence: day(store, -1), store: store)
        }
        XCTAssertTrue(rows(store, id).isEmpty)
    }

    /// F6: the engine's refusal reaches the caller instead of vanishing into `try?`.
    func test_aMissingExchangeRateIsThrown_notSwallowed() async throws {
        let store = try await makeStore()
        let won = "acct-krw-\(UUID().uuidString.prefix(6))"
        try store.apply(.createAccount, Args([
            "id": .string(won), "ledgerId": .string(store.activeLedgerId), "name": .string("Won"),
            "type": .string("savings"), "currency": .string("KRW"),
        ]))
        let id = try createDaily(store, accountId: won)
        assertRefused("error.fx.noRate") {
            try NotificationService.confirmNow(templateId: id, occurrence: store.wallToday, store: store)
        }
        XCTAssertTrue(rows(store, id).isEmpty)
    }

    /// …and the button's handler turns it into what the alert it raises says: the
    /// item's name, and why (#832 wired this up; nothing had pinned it).
    func test_aRefusalBecomesTheAlertText() async throws {
        let store = try await makeStore()
        let won = "acct-krw-\(UUID().uuidString.prefix(6))"
        try store.apply(.createAccount, Args([
            "id": .string(won), "ledgerId": .string(store.activeLedgerId), "name": .string("Won"),
            "type": .string("savings"), "currency": .string("KRW"),
        ]))
        let id = try createDaily(store, accountId: won)
        let refusal = try XCTUnwrap(NotificationService.confirmNowRefusal(
            templateId: id, occurrence: store.wallToday, title: "Scheduled: Coffee", store: store))
        XCTAssertEqual(refusal.title, "Coffee")
        var thrown: Error?
        XCTAssertThrowsError(try NotificationService.confirmNow(templateId: id, occurrence: store.wallToday, store: store)) {
            thrown = $0
        }
        XCTAssertEqual(refusal.body, String(localized: "Couldn't add it: \(i18nMessage(try XCTUnwrap(thrown)))"))
        XCTAssertTrue(rows(store, id).isEmpty)

        // A template gone since: the reminder's own title names it.
        XCTAssertEqual(NotificationService.confirmNowRefusal(
            templateId: "gone", occurrence: store.wallToday, title: "Scheduled: Old", store: store)?.title,
                       "Scheduled: Old")
        // Booked: nothing to say.
        let ok = try createDaily(store)
        XCTAssertNil(NotificationService.confirmNowRefusal(
            templateId: ok, occurrence: store.wallToday, title: "Scheduled: Coffee", store: store))
        XCTAssertEqual(rows(store, ok).count, 1)
    }
}
