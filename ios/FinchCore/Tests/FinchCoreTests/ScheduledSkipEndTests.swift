import XCTest
import GRDB
@testable import FinchCore

/// Skipping one occurrence of a scheduled template, and ending a template on a date.
///
/// The contract, asserted end to end below: a skipped occurrence is not due, not
/// generated, not forecast and not reminded about; it does not count as an execution,
/// so an installment plan still makes all its payments, one period later; and it can
/// be un-skipped. An end date is a hard stop for all of the same readers.
final class ScheduledSkipEndTests: XCTestCase {

    // MARK: fixtures

    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','Cash','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
        }
        return q
    }

    /// A monthly expense on the 15th, from 2026-01-15.
    private func createGym(_ q: DatabaseQueue, extra: [String: JSONValue] = [:]) throws {
        var args: [String: JSONValue] = [
            "id": .string("gym"), "ledgerId": .string("l1"), "name": .string("Gym"), "type": .string("expense"),
            "amount": .double(40), "frequency": .string("monthly"), "dayOfMonth": .int(15),
            "accountId": .string("a1"), "startDate": .string("2026-01-15"),
        ]
        for (k, v) in extra { args[k] = v }
        try Apply.apply(dbQueue: q, action: "createScheduled", args: Args(args))
    }

    private func skip(_ q: DatabaseQueue, _ date: String, template: String = "gym") throws {
        try Apply.apply(dbQueue: q, action: "skipScheduledOccurrence",
                        args: Args(["templateId": .string(template), "date": .string(date)]))
    }
    private func unskip(_ q: DatabaseQueue, _ date: String, template: String = "gym") throws {
        try Apply.apply(dbQueue: q, action: "unskipScheduledOccurrence",
                        args: Args(["templateId": .string(template), "date": .string(date)]))
    }
    private func template(_ q: DatabaseQueue, _ id: String = "gym") throws -> ScheduledTemplate {
        try XCTUnwrap(try Projection.scheduledTemplates(dbQueue: q, ledgerId: "l1").first { $0.id == id })
    }
    private func generatedDates(_ q: DatabaseQueue, _ id: String = "gym") throws -> [String] {
        try q.read { db in
            try String.fetchAll(db, sql: "SELECT COALESCE(occurrence_date, date) FROM entries WHERE source_template_id = ? ORDER BY 1",
                                arguments: [id])
        }
    }

    private func monthly15(skipped: [String]? = nil, endDate: String? = nil,
                           installmentTotal: Int? = nil, installmentPaid: Int? = nil) -> ScheduledTemplate {
        ScheduledTemplate(id: "gym", name: "Gym", type: "expense", amount: 40, frequency: "monthly",
                          dayOfMonth: 15, accountId: "a1", startDate: "2026-01-15", endDate: endDate,
                          nextRun: "", installmentTotal: installmentTotal, installmentPaid: installmentPaid,
                          skippedDates: skipped)
    }

    // MARK: the recurrence

    func test_skippedOccurrenceIsLeftOutUnlessAskedFor() {
        let t = monthly15(skipped: ["2026-02-15"])
        XCTAssertEqual(Selectors.occurrencesUpTo(t, "2026-03-31"), ["2026-01-15", "2026-03-15"])
        XCTAssertEqual(Selectors.occurrencesUpTo(t, "2026-03-31", includeSkipped: true),
                       ["2026-01-15", "2026-02-15", "2026-03-15"])
        XCTAssertEqual(Selectors.occurrencesInRange([t], from: "2026-02-01", through: "2026-02-28").count, 0)
        XCTAssertEqual(Selectors.occurrencesInRange([t], from: "2026-02-01", through: "2026-02-28",
                                                    includeSkipped: true).map(\.date), ["2026-02-15"])
    }

    func test_nextOccurrenceJumpsTheSkipAndEndsAtTheEndDate() {
        XCTAssertEqual(Selectors.nextOccurrence(monthly15(skipped: ["2026-02-15"]), onOrAfter: "2026-02-01"), "2026-03-15")
        XCTAssertEqual(Selectors.nextOccurrence(monthly15(endDate: "2026-02-20"), onOrAfter: "2026-02-01"), "2026-02-15")
        XCTAssertNil(Selectors.nextOccurrence(monthly15(endDate: "2026-02-20"), onOrAfter: "2026-02-16"),
                     "nothing after the end date — the template has ended")
        // The only remaining occurrence skipped ⇒ nothing left either.
        XCTAssertNil(Selectors.nextOccurrence(monthly15(skipped: ["2026-02-15"], endDate: "2026-02-20"),
                                              onOrAfter: "2026-02-01"))
    }

    func test_isOccurrence() {
        let t = monthly15()
        XCTAssertTrue(Selectors.isOccurrence(t, "2026-02-15"))
        XCTAssertFalse(Selectors.isOccurrence(t, "2026-02-16"))
        XCTAssertFalse(Selectors.isOccurrence(t, "2025-12-15"), "before the start")
        XCTAssertFalse(Selectors.isOccurrence(monthly15(endDate: "2026-02-01"), "2026-02-15"), "after the end")
        XCTAssertTrue(Selectors.isOccurrence(monthly15(skipped: ["2026-02-15"]), "2026-02-15"),
                      "a skipped date is still an occurrence — that is what lets it be un-skipped")
    }

    // MARK: picking which occurrence to skip / unskip

    func test_skipTargetIsThisCyclesOccurrence_andWalksForward() {
        // Jan posted; on 2026-02-20 the Feb 15th just passed (5 days) beats Mar 15th (23).
        let posted = ["gym|2026-01-15": false]
        XCTAssertEqual(Selectors.skipTarget(template: monthly15(), posted: posted, today: "2026-02-20"), "2026-02-15")
        XCTAssertEqual(Selectors.skipTarget(template: monthly15(skipped: ["2026-02-15"]), posted: posted, today: "2026-02-20"),
                       "2026-03-15", "once Feb is skipped the next bare Skip takes March")
        XCTAssertEqual(Selectors.resumeOccurrence(template: monthly15(skipped: ["2026-02-15"]), posted: posted, today: "2026-02-20"),
                       "2026-03-15", "Post now passes over a skip too")
    }

    /// The reason Skip does not reuse `resumeOccurrence`: with a backlog of missed
    /// occurrences, "skip" means this cycle's, never the oldest — skipping that changed
    /// nothing the user could see.
    func test_skipTargetIgnoresAnOlderBacklog() {
        // Nothing posted since Jan 15th. Two days after Mar 15th: that one, not Jan's.
        XCTAssertEqual(Selectors.skipTarget(template: monthly15(), posted: [:], today: "2026-03-17"), "2026-03-15")
        XCTAssertEqual(Selectors.resumeOccurrence(template: monthly15(), posted: [:], today: "2026-03-17"), "2026-01-15",
                       "Post now still catches up oldest-first")
        // The day before Apr 15th: the upcoming one is nearer.
        XCTAssertEqual(Selectors.skipTarget(template: monthly15(), posted: [:], today: "2026-04-14"), "2026-04-15")
        // Equidistant (Feb 15th → Mar 1st → Mar 15th, 14 days each): the upcoming one.
        XCTAssertEqual(Selectors.skipTarget(template: monthly15(), posted: [:], today: "2026-03-01"), "2026-03-15")
        // The one just passed is posted: the upcoming one, not an older missed one.
        XCTAssertEqual(Selectors.skipTarget(template: monthly15(), posted: ["gym|2026-03-15": false], today: "2026-03-17"),
                       "2026-04-15")
        XCTAssertEqual(Selectors.previousOccurrence(monthly15(), before: "2026-03-15"), "2026-02-15", "strictly before")
    }

    /// Found on the simulator: with this cycle's occurrence skipped, the nearer open
    /// one was LAST month's missed occurrence, and a second Skip went backwards.
    /// Skips walk forward from the current occurrence, never back.
    func test_repeatedSkipsWalkForward_neverBack() {
        // Nothing posted. 2026-04-14: current is Apr 15th; skip it.
        let t = monthly15(skipped: ["2026-04-15"])
        XCTAssertEqual(Selectors.currentOccurrence(t, today: "2026-04-14"), "2026-04-15", "skipped still counts as current")
        XCTAssertEqual(Selectors.skipTarget(template: t, posted: [:], today: "2026-04-14"), "2026-05-15",
                       "not Mar 15th, though it is nearer than May 15th")
    }

    func test_unskipTargetIsTheLatestSkip_andPostedSkipsDoNotCount() {
        let t = monthly15(skipped: ["2026-02-15", "2026-03-15"])
        XCTAssertEqual(Selectors.unskipTarget(template: t, posted: [:]), "2026-03-15")
        XCTAssertEqual(Selectors.activeSkips(template: t, posted: ["gym|2026-03-15": false]), ["2026-02-15"],
                       "a posted occurrence is not skipped any more, whatever the list says")
        XCTAssertNil(Selectors.unskipTarget(template: monthly15(), posted: [:]))
    }

    // MARK: the actions

    func test_skipAndUnskipRoundTripThroughTheProjection() throws {
        let q = try seeded()
        try createGym(q)
        try skip(q, "2026-03-15")
        try skip(q, "2026-02-15")
        try skip(q, "2026-02-15")   // twice: a no-op, not a duplicate
        XCTAssertEqual(try template(q).skippedDates, ["2026-02-15", "2026-03-15"])
        try unskip(q, "2026-02-15")
        XCTAssertEqual(try template(q).skippedDates, ["2026-03-15"])
        try unskip(q, "2026-02-15")   // not skipped any more: a no-op, not an error
        try unskip(q, "2026-03-15")
        XCTAssertEqual(try template(q).skippedDates, nil, "the template's entry is dropped once empty")
    }

    func test_skipRefusesANonOccurrence_aPostedOne_andAMissingTemplate() throws {
        let q = try seeded()
        try createGym(q)
        XCTAssertThrowsError(try skip(q, "2026-02-16")) {
            XCTAssertEqual(($0 as? I18nError)?.code, "error.scheduled.notAnOccurrence")
        }
        XCTAssertThrowsError(try skip(q, "not-a-date")) {
            XCTAssertEqual(($0 as? I18nError)?.code, "error.scheduled.notAnOccurrence")
        }
        // Posted LATE (dated the 18th) for the 15th: still recognised as posted.
        try Apply.apply(dbQueue: q, action: "postScheduled", args: Args([
            "templateId": .string("gym"), "date": .string("2026-02-18"), "occurrenceDate": .string("2026-02-15")]))
        XCTAssertThrowsError(try skip(q, "2026-02-15")) {
            XCTAssertEqual(($0 as? I18nError)?.code, "error.scheduled.skipAlreadyPosted")
        }
        XCTAssertThrowsError(try skip(q, "2026-02-15", template: "nope")) {
            XCTAssertEqual(($0 as? I18nError)?.code, "error.notFound.template")
        }
        XCTAssertNil(try template(q).skippedDates, "nothing was written by the refusals")
    }

    func test_deletingATemplateDropsItsSkips() throws {
        let q = try seeded()
        try createGym(q)
        try Apply.apply(dbQueue: q, action: "createScheduled", args: Args([
            "id": .string("rent"), "ledgerId": .string("l1"), "name": .string("Rent"), "type": .string("expense"),
            "amount": .double(900), "frequency": .string("monthly"), "dayOfMonth": .int(1),
            "accountId": .string("a1"), "startDate": .string("2026-01-01")]))
        try skip(q, "2026-02-15")
        try skip(q, "2026-02-01", template: "rent")
        try Apply.apply(dbQueue: q, action: "deleteScheduled", args: Args(["id": .string("gym")]))
        let map = try q.read { db in try ScheduledSkips.load(db) }
        XCTAssertEqual(map, ["rent": ["2026-02-01"]], "only the deleted template's skips go")
    }

    // MARK: generateDueScheduled

    func test_generateDueLeavesASkippedOccurrenceOut_untilItIsUnskipped() throws {
        let q = try seeded()
        try createGym(q)
        try skip(q, "2026-02-15")
        try Apply.apply(dbQueue: q, action: "generateDueScheduled", args: Args(["today": .string("2026-03-20")]))
        XCTAssertEqual(try generatedDates(q), ["2026-01-15", "2026-03-15"])
        try unskip(q, "2026-02-15")
        try Apply.apply(dbQueue: q, action: "generateDueScheduled", args: Args(["today": .string("2026-03-20")]))
        XCTAssertEqual(try generatedDates(q), ["2026-01-15", "2026-02-15", "2026-03-15"],
                       "un-skipped, the occurrence is due again and generated on the next run")
    }

    /// The decision this feature turns on: a skip is NOT an execution. A 3-payment
    /// plan with its second month skipped still makes 3 payments — Jan, Mar, Apr.
    func test_aSkipDoesNotSpendAnInstallment() throws {
        let q = try seeded()
        try createGym(q, extra: ["installmentTotal": .int(3)])
        try skip(q, "2026-02-15")
        try Apply.apply(dbQueue: q, action: "generateDueScheduled", args: Args(["today": .string("2026-12-31")]))
        XCTAssertEqual(try generatedDates(q), ["2026-01-15", "2026-03-15", "2026-04-15"])
    }

    func test_aSkipDoesNotSpendAMaxExecution() throws {
        let q = try seeded()
        try createGym(q, extra: ["maxExecutions": .int(2)])
        try skip(q, "2026-01-15")
        try Apply.apply(dbQueue: q, action: "generateDueScheduled", args: Args(["today": .string("2026-12-31")]))
        XCTAssertEqual(try generatedDates(q), ["2026-02-15", "2026-03-15"])
    }

    func test_generateDueStopsAtTheEndDate() throws {
        let q = try seeded()
        try createGym(q, extra: ["endDate": .string("2026-03-01")])
        try Apply.apply(dbQueue: q, action: "generateDueScheduled", args: Args(["today": .string("2026-12-31")]))
        XCTAssertEqual(try generatedDates(q), ["2026-01-15", "2026-02-15"])
    }

    /// The installment cap and the end date together: the end date wins, even though
    /// the skip would otherwise have pushed the third payment past it.
    func test_theEndDateIsAHardStopEvenForAPlanASkipExtended() throws {
        let q = try seeded()
        try createGym(q, extra: ["installmentTotal": .int(3), "endDate": .string("2026-03-31")])
        try skip(q, "2026-02-15")
        try Apply.apply(dbQueue: q, action: "generateDueScheduled", args: Args(["today": .string("2026-12-31")]))
        XCTAssertEqual(try generatedDates(q), ["2026-01-15", "2026-03-15"])
    }

    // MARK: the end date through create / update

    func test_endDateIsSetOnCreate_movedAndClearedOnUpdate() throws {
        let q = try seeded()
        try createGym(q, extra: ["endDate": .string("2026-06-30")])
        XCTAssertEqual(try template(q).endDate, "2026-06-30")
        try Apply.apply(dbQueue: q, action: "updateScheduled", args: Args([
            "id": .string("gym"), "patch": .object(["endDate": .string("2026-04-30")])]))
        XCTAssertEqual(try template(q).endDate, "2026-04-30")
        try Apply.apply(dbQueue: q, action: "updateScheduled", args: Args([
            "id": .string("gym"), "patch": .object(["endDate": .null])]))
        XCTAssertNil(try template(q).endDate, "a null patch clears it — the item runs on again")
    }

    // MARK: forecasts

    private let account = AccountRow(id: "a1", balance: 1000, ledgerId: "l1", currency: "USD")

    func test_accountForecastLeavesOutSkippedAndEndedOccurrences() {
        let skipped = Selectors.accountForecast(account, [monthly15(skipped: ["2026-03-15"])], "2026-02-20", 60)
        XCTAssertEqual(skipped.events.map(\.date), ["2026-04-15"])
        XCTAssertEqual(skipped.endingBalance, 960)
        let ended = Selectors.accountForecast(account, [monthly15(endDate: "2026-03-31")], "2026-02-20", 60)
        XCTAssertEqual(ended.events.map(\.date), ["2026-03-15"])
    }

    /// Forecast installments: 2 of 3 paid, the next one skipped — the last payment
    /// still appears, a month later, rather than the skip using it up.
    func test_accountForecastKeepsTheLastInstallmentAfterASkip() {
        let t = monthly15(skipped: ["2026-03-15"], installmentTotal: 3, installmentPaid: 2)
        let f = Selectors.accountForecast(account, [t], "2026-02-20", 120)
        XCTAssertEqual(f.events.map(\.date), ["2026-04-15"])
    }

    func test_monthForecastLeavesOutASkippedOrEndedOccurrence() throws {
        let plain = try XCTUnwrap(Selectors.monthForecast([], [monthly15()], "l1", "2026-03", "2026-03-10"))
        XCTAssertEqual(plain.scheduledRest, 40)
        let skipped = try XCTUnwrap(Selectors.monthForecast([], [monthly15(skipped: ["2026-03-15"])], "l1", "2026-03", "2026-03-10"))
        XCTAssertEqual(skipped.scheduledRest, 0)
        let ended = try XCTUnwrap(Selectors.monthForecast([], [monthly15(endDate: "2026-03-14")], "l1", "2026-03", "2026-03-10"))
        XCTAssertEqual(ended.scheduledRest, 0)
        let endsLater = try XCTUnwrap(Selectors.monthForecast([], [monthly15(endDate: "2026-03-15")], "l1", "2026-03", "2026-03-10"))
        XCTAssertEqual(endsLater.scheduledRest, 40, "the end date is inclusive")
    }
}
