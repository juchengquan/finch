import XCTest
import GRDB
@testable import FinchCore

/// "Missed" means missed. It was read off the template alone, so occurrences came
/// back that nobody owed:
///
/// - **A1** — a row auto-post added and the user deleted left no trace: deleted on
///   its own day, the next foreground re-posted it (a transfer moved the money
///   twice); deleted on a later day, it read "overdue". The app's delete now counts
///   the occurrence as skipped, and Undo un-skips it.
/// - **S3** — changing a paid item's day of month, start date or frequency gave it a
///   recurrence its postings do not land on, so its whole history read "overdue".
/// - **S4** — an "Add automatically" item created with a past start date (auto-post
///   never back-fills) read "overdue <start>" for good.
///
/// The fix is `Selectors.missedFloor`: nothing below the latest posted or skipped
/// occurrence, nor below the day auto-post started covering the template, is missed.
final class MissedOccurrenceTests: XCTestCase {

    // MARK: fixtures

    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            for id in ["a1", "a2"] {
                try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES (?,'l1',?,'cash','USD',0,0,1,1,datetime('now'),datetime('now'))",
                               arguments: [id, id])
            }
        }
        return q
    }

    /// A monthly item on the 15th, from 2026-01-15.
    private func create(_ q: DatabaseQueue, type: String = "expense", autoPost: Bool = true,
                        extra: [String: JSONValue] = [:]) throws {
        var args: [String: JSONValue] = [
            "id": .string("s1"), "ledgerId": .string("l1"), "name": .string("Rent"), "type": .string(type),
            "amount": .double(100), "frequency": .string("monthly"), "dayOfMonth": .int(15),
            "accountId": .string("a1"), "startDate": .string("2026-01-15"), "autoPost": .bool(autoPost),
        ]
        if type == "transfer" { args["fromAccountId"] = .string("a2") }
        for (k, v) in extra { args[k] = v }
        try Apply.apply(dbQueue: q, action: "createScheduled", args: Args(args))
    }

    @discardableResult
    private func autoPost(_ q: DatabaseQueue, _ today: String) throws -> Int {
        try Apply.applyReturningCount(dbQueue: q, action: "autoPostDueScheduled",
                                      args: Args(["today": .string(today), "time": .string("09:00")]))
    }

    private func post(_ q: DatabaseQueue, _ occurrence: String) throws {
        try Apply.apply(dbQueue: q, action: "postScheduled", args: Args([
            "templateId": .string("s1"), "date": .string(occurrence), "occurrenceDate": .string(occurrence)]))
    }

    private func update(_ q: DatabaseQueue, _ patch: [String: JSONValue]) throws {
        try Apply.apply(dbQueue: q, action: "updateScheduled", args: Args(["id": .string("s1"), "patch": .object(patch)]))
    }

    /// The app's delete (`FinchStore.deleteTransaction(s)`).
    private func appDelete(_ q: DatabaseQueue, _ id: String, today: String) throws {
        try Apply.apply(dbQueue: q, action: "deleteTransactionSkippingOccurrence",
                        args: Args(["id": .string(id), "today": .string(today)]))
    }

    private func linkedEntryIds(_ q: DatabaseQueue) throws -> [String] {
        try q.read { try String.fetchAll($0, sql: "SELECT id FROM entries WHERE source_template_id = 's1' ORDER BY COALESCE(occurrence_date, date)") }
    }

    private func occurrences(_ q: DatabaseQueue) throws -> [String] {
        try q.read { try String.fetchAll($0, sql: "SELECT COALESCE(occurrence_date, date) FROM entries WHERE source_template_id = 's1' ORDER BY 1") }
    }

    private func balance(_ q: DatabaseQueue, _ account: String) throws -> Double {
        try q.read { try Double.fetchOne($0, sql: "SELECT current_balance FROM accounts WHERE id = ?", arguments: [account]) ?? .nan }
    }

    private func template(_ q: DatabaseQueue) throws -> ScheduledTemplate {
        try XCTUnwrap(try Projection.scheduledTemplates(dbQueue: q, ledgerId: "l1").first { $0.id == "s1" })
    }

    /// What the row's caption and Post read: `ScheduledCaption.due`'s date.
    private func resume(_ q: DatabaseQueue, today: String) throws -> String? {
        Selectors.resumeOccurrence(template: try template(q), posted: Selectors.scheduledPostedMap(try Projection.run(dbQueue: q)),
                                   today: today)
    }

    // MARK: - A1: deleting a linked row skips its occurrence

    /// The headline: deleted on the day auto-post added it, it stays deleted. The
    /// next foreground the same day re-covers the mark's own day, and used to post it
    /// again.
    func test_A1_rowDeletedOnItsOwnDay_isNotRepostedThatDay() throws {
        let q = try seeded()
        try create(q)
        XCTAssertEqual(try autoPost(q, "2026-10-15"), 1)
        try appDelete(q, try XCTUnwrap(try linkedEntryIds(q).first), today: "2026-10-15")
        XCTAssertEqual(try autoPost(q, "2026-10-15"), 0, "the next foreground, the same day")
        XCTAssertEqual(try occurrences(q), [])
        XCTAssertEqual(try template(q).skippedDates, ["2026-10-15"])
        XCTAssertEqual(try resume(q, today: "2026-10-15"), "2026-11-15", "not due any more either")
    }

    /// For a transfer the re-post moved the money twice.
    func test_A1_transferDeletedOnItsOwnDay_movesNoMoney() throws {
        let q = try seeded()
        try create(q, type: "transfer")
        try autoPost(q, "2026-10-15")
        XCTAssertEqual(try balance(q, "a2"), -100, accuracy: 0.001)
        try appDelete(q, try XCTUnwrap(try linkedEntryIds(q).first), today: "2026-10-15")
        try autoPost(q, "2026-10-15")
        XCTAssertEqual(try balance(q, "a1"), 0, accuracy: 0.001)
        XCTAssertEqual(try balance(q, "a2"), 0, accuracy: 0.001)
    }

    /// Deleted on a later day it already stayed gone, but read "overdue 2026-10-15".
    func test_A1_rowDeletedOnALaterDay_isNotOverdue() throws {
        let q = try seeded()
        try create(q)
        try autoPost(q, "2026-10-15")
        try appDelete(q, try XCTUnwrap(try linkedEntryIds(q).first), today: "2026-10-17")
        XCTAssertEqual(try autoPost(q, "2026-10-17"), 0)
        XCTAssertEqual(try resume(q, today: "2026-10-17"), "2026-11-15")
    }

    /// Undo brings back the row AND the occurrence's eligibility: the skip goes, so
    /// were the row removed some other way, the occurrence would be due again.
    func test_A1_undo_restoresTheRow_andUnskipsTheOccurrence() throws {
        let q = try seeded()
        try create(q)
        try autoPost(q, "2026-10-15")
        let id = try XCTUnwrap(try linkedEntryIds(q).first)
        let captured = try q.read { try TransactionUndo.capture($0, txIds: [id]) }
        try appDelete(q, id, today: "2026-10-15")
        XCTAssertEqual(try template(q).skippedDates, ["2026-10-15"])
        let settled = try q.read { try TransactionUndo.settle(captured, $0) }
        try Apply.apply(dbQueue: q, action: "restoreTransactions", args: try settled.args)

        XCTAssertEqual(try linkedEntryIds(q), [id], "the row is back, under its id")
        XCTAssertNil(try template(q).skippedDates, "and the occurrence is not skipped any more")
        // Eligibility: with the skip gone, removing the row by a path that records
        // nothing (the parity delete) leaves the occurrence due, so auto-post adds it.
        try Apply.apply(dbQueue: q, action: "deleteTransaction", args: Args(["id": .string(id)]))
        XCTAssertEqual(try autoPost(q, "2026-10-15"), 1)
        XCTAssertEqual(try occurrences(q), ["2026-10-15"])
    }

    /// Skips are recorded per deleted row, so a bulk delete — several app deletes —
    /// skips each, and one Undo un-skips them all.
    func test_A1_bulkDelete_andItsUndo() throws {
        let q = try seeded()
        try create(q)
        try autoPost(q, "2026-08-01")
        try autoPost(q, "2026-10-20")
        let ids = try linkedEntryIds(q)
        XCTAssertEqual(ids.count, 3)
        let captured = try q.read { try TransactionUndo.capture($0, txIds: ids) }
        for id in ids { try appDelete(q, id, today: "2026-10-20") }
        XCTAssertEqual(try template(q).skippedDates, ["2026-08-15", "2026-09-15", "2026-10-15"])
        XCTAssertEqual(try resume(q, today: "2026-10-20"), "2026-11-15")
        let settled = try q.read { try TransactionUndo.settle(captured, $0) }
        try Apply.apply(dbQueue: q, action: "restoreTransactions", args: try settled.args)
        XCTAssertEqual(try linkedEntryIds(q).sorted(), ids.sorted())
        XCTAssertNil(try template(q).skippedDates)
    }

    /// A row posted EARLY and deleted is not missed — its occurrence goes back to
    /// upcoming rather than being skipped.
    func test_A1_aFutureOccurrence_isNotSkipped() throws {
        let q = try seeded()
        try create(q, autoPost: false)
        try post(q, "2026-11-15")
        try appDelete(q, try XCTUnwrap(try linkedEntryIds(q).first), today: "2026-10-20")
        XCTAssertNil(try template(q).skippedDates)
        XCTAssertEqual(try occurrences(q), [])
    }

    /// Another row still fulfils the occurrence (a duplicate): it is posted, not
    /// skipped. And a row no schedule posted is just deleted.
    func test_A1_aStillFulfilledOccurrence_andAnUnlinkedRow_recordNothing() throws {
        let q = try seeded()
        try create(q, autoPost: false)
        try post(q, "2026-09-15")
        try post(q, "2026-09-15")
        try appDelete(q, try XCTUnwrap(try linkedEntryIds(q).first), today: "2026-10-20")
        XCTAssertNil(try template(q).skippedDates)
        XCTAssertEqual(try occurrences(q), ["2026-09-15"])

        let plain = try XCTUnwrap(try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-5), "merchant": .string("Coffee"),
            "date": .string("2026-10-01"), "skipRules": .bool(true)])))
        try appDelete(q, plain, today: "2026-10-20")
        XCTAssertEqual(try q.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM entries WHERE id = ?", arguments: [plain]) }, 0)
        XCTAssertNil(try template(q).skippedDates)
    }

    /// The occurrence a row was posted for may no longer be an occurrence (the
    /// schedule changed since): there is nothing to skip, and the delete still goes.
    func test_A1_aDateThatIsNoLongerAnOccurrence_isJustDeleted() throws {
        let q = try seeded()
        try create(q, autoPost: false)
        try post(q, "2026-09-15")
        try update(q, ["dayOfMonth": .int(20)])
        try appDelete(q, try XCTUnwrap(try linkedEntryIds(q).first), today: "2026-10-20")
        XCTAssertEqual(try occurrences(q), [])
        XCTAssertNil(try template(q).skippedDates)
    }

    /// The web's `deleteTransaction` is untouched — it records no skip — so the
    /// parity fixture still holds.
    func test_A1_theParityDelete_recordsNoSkip() throws {
        let q = try seeded()
        try create(q)
        try autoPost(q, "2026-10-15")
        try Apply.apply(dbQueue: q, action: "deleteTransaction", args: Args(["id": .string(try XCTUnwrap(try linkedEntryIds(q).first))]))
        XCTAssertNil(try template(q).skippedDates)
        XCTAssertNil(try q.read { try AppDomain.getAppState($0, ScheduledSkips.stateKey) })
    }

    func test_A1_rejectsAMalformedToday() throws {
        let q = try seeded()
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "deleteTransactionSkippingOccurrence",
                                             args: Args(["id": .string("x"), "today": .string("10/20/2026")])))
    }

    // MARK: - S3: a changed schedule does not resurrect its history

    /// Paid January through October, then moved from the 15th to the 20th. The new
    /// recurrence's January 20 was never owed.
    func test_S3_changedDayOfMonth_isNotOverdueFromJanuary() throws {
        let q = try seeded()
        try create(q, autoPost: false)
        for m in 1...10 { try post(q, String(format: "2026-%02d-15", m)) }
        XCTAssertEqual(try resume(q, today: "2026-10-19"), "2026-11-15", "precondition: caught up")
        try update(q, ["dayOfMonth": .int(20)])
        XCTAssertEqual(try resume(q, today: "2026-10-19"), "2026-10-20")
        XCTAssertEqual(try resume(q, today: "2026-10-25"), "2026-10-20", "a NEW miss after the history still counts")
    }

    func test_S3_movedStartDate_isNotOverdueFromTheNewStart() throws {
        let q = try seeded()
        try create(q, autoPost: false)
        for m in 1...10 { try post(q, String(format: "2026-%02d-15", m)) }
        try update(q, ["startDate": .string("2025-06-15")])
        XCTAssertEqual(try resume(q, today: "2026-10-19"), "2026-11-15")
    }

    func test_S3_changedFrequency_isNotOverdueFromTheStart() throws {
        let q = try seeded()
        try create(q, autoPost: false)
        for m in 1...10 { try post(q, String(format: "2026-%02d-15", m)) }
        // Weekly from Thursday 2026-01-15: Oct 15 is one of its days, and posted.
        try update(q, ["frequency": .string("weekly")])
        XCTAssertEqual(try resume(q, today: "2026-10-19"), "2026-10-22")
    }

    /// Only the past is history: posting next month's early does not forgive this
    /// month's, nor does skipping it in advance.
    func test_aFutureResolution_doesNotRaiseTheFloor() {
        let t = ScheduledTemplate(id: "s1", name: "Rent", type: "expense", amount: 100, frequency: "monthly",
                                  dayOfMonth: 15, accountId: "a1", startDate: "2026-09-15", nextRun: "",
                                  skippedDates: ["2026-12-15"])
        let posted = ["s1|2026-09-15": false, "s1|2026-11-15": false]
        XCTAssertEqual(Selectors.resumeOccurrence(template: t, posted: posted, today: "2026-10-19"), "2026-10-15")
        XCTAssertTrue(Selectors.isMissed(template: t, date: "2026-10-15", posted: posted, today: "2026-10-19"))
    }

    /// The calendar's badge reads `isMissed`; it must agree with the caption.
    func test_isMissed_agreesWithResumeOccurrence() throws {
        let q = try seeded()
        try create(q, autoPost: false)
        for m in 1...10 { try post(q, String(format: "2026-%02d-15", m)) }
        try update(q, ["dayOfMonth": .int(20)])
        let t = try template(q)
        let posted = Selectors.scheduledPostedMap(try Projection.run(dbQueue: q))
        XCTAssertFalse(Selectors.isMissed(template: t, date: "2026-01-20", posted: posted, today: "2026-10-25"))
        XCTAssertTrue(Selectors.isMissed(template: t, date: "2026-10-20", posted: posted, today: "2026-10-25"))
        XCTAssertFalse(Selectors.isMissed(template: t, date: "2026-11-20", posted: posted, today: "2026-10-25"), "upcoming")
    }

    /// A plain backlog with no history at all is still a backlog, oldest first.
    func test_noHistory_keepsTheWholeBacklog() {
        let t = ScheduledTemplate(id: "s1", name: "Rent", type: "expense", amount: 100, frequency: "monthly",
                                  dayOfMonth: 15, accountId: "a1", startDate: "2026-07-15", nextRun: "")
        XCTAssertEqual(Selectors.resumeOccurrence(template: t, posted: [:], today: "2026-10-19"), "2026-07-15")
        XCTAssertNil(Selectors.missedFloor(template: t, posted: [:], today: "2026-10-19"))
    }

    // MARK: - S4: auto-post's own floor

    /// Created on 2026-10-17 starting in January: auto-post adds nothing before that
    /// day, so nothing before it is overdue.
    func test_S4_newAutoTemplateWithAPastStart_isNotOverdue() throws {
        let q = try seeded()
        try autoPost(q, "2026-10-17")          // the foreground run, that morning
        try create(q)
        XCTAssertEqual(try autoPost(q, "2026-10-17"), 0, "the run the sheet's save triggers")
        XCTAssertEqual(try template(q).autoPostSince, "2026-10-17")
        XCTAssertEqual(try resume(q, today: "2026-10-17"), "2026-11-15")
    }

    /// The floor is the template's own: an occurrence auto-post could NOT add after
    /// it — here for want of an exchange rate — is still really missed.
    func test_S4_anOccurrenceAutoPostCouldNotAdd_isStillOverdue() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('krw','l1','Seoul','cash','KRW',0,0,1,1,datetime('now'),datetime('now'))")
        }
        try create(q, extra: ["accountId": .string("krw")])
        try autoPost(q, "2026-10-01")
        XCTAssertEqual(try autoPost(q, "2026-10-20"), 0)
        XCTAssertEqual(try template(q).autoPostSince, "2026-10-01")
        XCTAssertEqual(try resume(q, today: "2026-10-20"), "2026-10-15")
    }

    /// Switched on later: the floor is the first run with it on — the run's own
    /// floor, the day after the mark — and switching it off drops it, so it starts
    /// afresh when switched on again.
    func test_S4_switchedOnLater_andOffAgain() throws {
        let q = try seeded()
        try create(q, autoPost: false)
        try autoPost(q, "2026-06-01")
        XCTAssertNil(try template(q).autoPostSince, "manual templates have none")
        XCTAssertEqual(try resume(q, today: "2026-06-01"), "2026-01-15", "a manual backlog is a backlog")
        try update(q, ["autoPost": .bool(true)])
        try autoPost(q, "2026-06-05")
        XCTAssertEqual(try template(q).autoPostSince, "2026-06-02")
        XCTAssertEqual(try resume(q, today: "2026-06-05"), "2026-06-15")
        try update(q, ["autoPost": .bool(false)])
        try autoPost(q, "2026-06-06")
        XCTAssertNil(try template(q).autoPostSince)
        try update(q, ["autoPost": .bool(true)])
        try autoPost(q, "2026-09-01")
        XCTAssertEqual(try template(q).autoPostSince, "2026-06-07")
    }

    /// The floor only applies while auto-post is on: the template's flag, not the
    /// stored day, decides.
    func test_S4_sinceIsIgnoredForAManualTemplate() {
        let t = ScheduledTemplate(id: "s1", name: "Rent", type: "expense", amount: 100, frequency: "monthly",
                                  dayOfMonth: 15, accountId: "a1", startDate: "2026-07-15", nextRun: "",
                                  autoPost: 0, autoPostSince: "2026-10-01")
        XCTAssertEqual(Selectors.resumeOccurrence(template: t, posted: [:], today: "2026-10-19"), "2026-07-15")
    }

    func test_S4_deletingATemplate_dropsItsSinceOnTheNextRun() throws {
        let q = try seeded()
        try create(q)
        try autoPost(q, "2026-10-01")
        try Apply.apply(dbQueue: q, action: "deleteScheduled", args: Args(["id": .string("s1")]))
        try autoPost(q, "2026-10-02")
        XCTAssertEqual(try q.read { try AutoPostSince.load($0) }, [:])
    }

    /// The parity action writes none of it.
    func test_theParityGenerator_recordsNoSince() throws {
        let q = try seeded()
        try create(q)
        try Apply.apply(dbQueue: q, action: "generateDueScheduled", args: Args(["today": .string("2026-03-20")]))
        XCTAssertNil(try q.read { try AppDomain.getAppState($0, AutoPostSince.stateKey) })
    }
}
