import XCTest
import GRDB
@testable import FinchCore

/// `autoPostDueScheduled` — the app's generator. The parity action
/// `generateDueScheduled` (GenerateDueTests) ignores `auto_post` and catches up from
/// the start date; this one honours the flag and never reaches below its
/// high-water mark, which is what makes it safe to switch on for existing data.
final class AutoPostDueTests: XCTestCase {
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

    /// A monthly template on the 15th, from 2026-01-15.
    private func create(_ q: DatabaseQueue, id: String = "s1", type: String = "expense",
                        autoPost: Bool? = true, extra: [String: JSONValue] = [:]) throws {
        var args: [String: JSONValue] = [
            "id": .string(id), "ledgerId": .string("l1"), "name": .string("Rent \(id)"), "type": .string(type),
            "amount": .double(100), "frequency": .string("monthly"), "dayOfMonth": .int(15),
            "accountId": .string("a1"), "startDate": .string("2026-01-15"),
        ]
        if let autoPost { args["autoPost"] = .bool(autoPost) }
        if type == "transfer" { args["fromAccountId"] = .string("a2") }
        for (k, v) in extra { args[k] = v }
        try Apply.apply(dbQueue: q, action: "createScheduled", args: Args(args))
    }

    @discardableResult
    private func run(_ q: DatabaseQueue, _ today: String) throws -> Int {
        try Apply.applyReturningCount(dbQueue: q, action: "autoPostDueScheduled",
                                      args: Args(["today": .string(today), "time": .string("09:00")]))
    }

    private func occurrences(_ q: DatabaseQueue, _ id: String = "s1") throws -> [String] {
        try q.read { db in
            try String.fetchAll(db, sql: "SELECT COALESCE(occurrence_date, date) FROM entries WHERE source_template_id = ? ORDER BY 1",
                                arguments: [id])
        }
    }

    private func mark(_ q: DatabaseQueue) throws -> String? { try q.read { try AutoPostMark.load($0) } }

    // MARK: - What the existing data holds

    /// The rollout question: what do templates created before this shipped hold?
    /// Not the column default (1). Native `createScheduled` has always bound
    /// `autoPost ?? false` explicitly, and neither the sheet nor the demo seed ever
    /// passed it — so every natively created template holds 0. Pinned, because the
    /// rollout reasoning depends on it.
    func test_createWithoutAutoPost_stores0_notTheColumnDefault() throws {
        let q = try seeded()
        try create(q, autoPost: nil)
        XCTAssertEqual(try q.read { try Int.fetchOne($0, sql: "SELECT auto_post FROM scheduled_templates WHERE id = 's1'") }, 0)
    }

    func test_autoPost_isSetOnCreate_andChangedByUpdate() throws {
        let q = try seeded()
        try create(q, autoPost: true)
        func stored() throws -> Int? { try q.read { try Int.fetchOne($0, sql: "SELECT auto_post FROM scheduled_templates WHERE id = 's1'") } }
        XCTAssertEqual(try stored(), 1)
        try Apply.apply(dbQueue: q, action: "updateScheduled",
                        args: Args(["id": .string("s1"), "patch": .object(["autoPost": .bool(false)])]))
        XCTAssertEqual(try stored(), 0)
        try Apply.apply(dbQueue: q, action: "updateScheduled",
                        args: Args(["id": .string("s1"), "patch": .object(["autoPost": .bool(true)])]))
        XCTAssertEqual(try stored(), 1)
        // …and the projection carries it to the app.
        let t = try XCTUnwrap(try Projection.scheduledTemplates(dbQueue: q, ledgerId: "l1").first)
        XCTAssertTrue(t.postsAutomatically)
    }

    // MARK: - Rollout safety: the floor

    /// The first run generates TODAY's occurrence and nothing before it, even though
    /// January through September are all due and unposted. The parity action would
    /// have made nine rows here.
    func test_firstRun_doesNotBackfill() throws {
        let q = try seeded()
        try create(q)
        XCTAssertEqual(try run(q, "2026-10-15"), 1)
        XCTAssertEqual(try occurrences(q), ["2026-10-15"])
        XCTAssertEqual(try mark(q), "2026-10-15")
    }

    func test_firstRun_onANonDueDay_generatesNothing_butSetsTheMark() throws {
        let q = try seeded()
        try create(q)
        XCTAssertEqual(try run(q, "2026-10-17"), 0)
        XCTAssertEqual(try occurrences(q), [])
        XCTAssertEqual(try mark(q), "2026-10-17")
    }

    /// Days the app was not opened are caught up: the mark stays where the last run
    /// left it, so everything from there to today is generated.
    func test_laterRun_catchesUpFromTheMark() throws {
        let q = try seeded()
        try create(q)
        try run(q, "2026-08-01")
        XCTAssertEqual(try run(q, "2026-10-20"), 3)
        XCTAssertEqual(try occurrences(q), ["2026-08-15", "2026-09-15", "2026-10-15"])
        XCTAssertEqual(try mark(q), "2026-10-20")
    }

    /// A template created today with a start date a year back starts from today.
    func test_newTemplateWithPastStart_doesNotBackfill() throws {
        let q = try seeded()
        try run(q, "2026-10-01")             // the app has been running
        try create(q)                        // starts 2026-01-15
        XCTAssertEqual(try run(q, "2026-10-01"), 0)
        XCTAssertEqual(try run(q, "2026-10-15"), 1)
        XCTAssertEqual(try occurrences(q), ["2026-10-15"])
    }

    /// The mark's own day is re-covered: a template created or switched on later the
    /// same day still gets that day's occurrence.
    func test_sameDay_templateCreatedAfterTheRun_stillGetsToday() throws {
        let q = try seeded()
        try run(q, "2026-10-15")             // morning: nothing to do yet
        try create(q)
        XCTAssertEqual(try run(q, "2026-10-15"), 1)
        XCTAssertEqual(try occurrences(q), ["2026-10-15"])
    }

    /// Switched on long after creation: starts from that day, no back-fill.
    func test_switchedOnLater_startsFromThatDay() throws {
        let q = try seeded()
        try create(q, autoPost: false)
        try run(q, "2026-06-01")
        try run(q, "2026-09-30")
        XCTAssertEqual(try occurrences(q), [], "auto_post = 0 is never generated")
        try Apply.apply(dbQueue: q, action: "updateScheduled",
                        args: Args(["id": .string("s1"), "patch": .object(["autoPost": .bool(true)])]))
        XCTAssertEqual(try run(q, "2026-10-16"), 1)
        XCTAssertEqual(try occurrences(q), ["2026-10-15"])
    }

    /// A clock set back must not re-open old days.
    func test_markNeverMovesBackwards() throws {
        let q = try seeded()
        try create(q)
        try run(q, "2026-10-20")
        try run(q, "2026-09-01")
        XCTAssertEqual(try mark(q), "2026-10-20")
        XCTAssertEqual(try occurrences(q), [], "Sep 15 was before the first run")
    }

    /// A generated row the user deleted stays deleted once its day has passed —
    /// rather than coming back on every launch, as it would under the parity action.
    func test_deletedRow_isNotRecreatedAfterItsDay() throws {
        let q = try seeded()
        try create(q)
        try run(q, "2026-10-15")
        let id = try XCTUnwrap(try q.read { try String.fetchOne($0, sql: "SELECT id FROM entries WHERE source_template_id = 's1'") })
        try Apply.apply(dbQueue: q, action: "deleteTransaction", args: Args(["id": .string(id)]))
        XCTAssertEqual(try run(q, "2026-10-16"), 0)
        XCTAssertEqual(try occurrences(q), [])
    }

    func test_anUnreadableMark_isTreatedAsAFirstRun() throws {
        let q = try seeded()
        try create(q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO app_state (key,value,created_at,updated_at) VALUES (?, 'garbage', datetime('now'), datetime('now'))",
                           arguments: [AutoPostMark.stateKey])
        }
        XCTAssertEqual(try run(q, "2026-10-15"), 1)
        XCTAssertEqual(try occurrences(q), ["2026-10-15"])
    }

    // MARK: - auto_post respected

    func test_manualTemplates_areNeverGenerated() throws {
        let q = try seeded()
        try create(q, id: "manual", autoPost: false)
        try create(q, id: "auto", autoPost: true)
        try run(q, "2026-09-01")
        XCTAssertEqual(try run(q, "2026-10-20"), 2)
        XCTAssertEqual(try occurrences(q, "manual"), [])
        XCTAssertEqual(try occurrences(q, "auto"), ["2026-09-15", "2026-10-15"])
    }

    // MARK: - What gets posted (design decision 25)

    /// Income/expense land PENDING — in To confirm — and leave the balance alone;
    /// stamped with the template and the occurrence they fulfil.
    func test_expense_isPending_andStamped() throws {
        let q = try seeded()
        try create(q)
        try run(q, "2026-10-15")
        try q.read { db in
            let r = try XCTUnwrap(try Row.fetchOne(db, sql: "SELECT status, kind, date, occurrence_date, source_template_id, time FROM entries"))
            XCTAssertEqual(r["status"] as String, "pending")
            XCTAssertEqual(r["kind"] as String, "expense")
            XCTAssertEqual(r["date"] as String, "2026-10-15")
            XCTAssertEqual(r["occurrence_date"] as String?, "2026-10-15")
            XCTAssertEqual(r["source_template_id"] as String?, "s1")
            XCTAssertEqual(r["time"] as String?, "09:00")
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id = 'a1'") ?? -1, 0, accuracy: 0.001)
        }
    }

    func test_income_isPending() throws {
        let q = try seeded()
        try create(q, type: "income")
        try run(q, "2026-10-15")
        XCTAssertEqual(try q.read { try String.fetchAll($0, sql: "SELECT status FROM entries") }, ["pending"])
    }

    /// Transfers post CONFIRMED and move both balances — a pending transfer would
    /// leave two half-confirmed legs on two account ledgers.
    func test_transfer_isConfirmed_andMovesBalances() throws {
        let q = try seeded()
        try create(q, type: "transfer")
        try run(q, "2026-10-15")
        try q.read { db in
            XCTAssertEqual(try String.fetchAll(db, sql: "SELECT status FROM entries"), ["confirmed"])
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT occurrence_date FROM entries"), "2026-10-15")
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id = 'a1'") ?? 0, 100, accuracy: 0.001)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id = 'a2'") ?? 0, -100, accuracy: 0.001)
        }
    }

    // MARK: - No double posting

    func test_runningTwice_isIdempotent() throws {
        let q = try seeded()
        try create(q)
        try run(q, "2026-10-15")
        XCTAssertEqual(try run(q, "2026-10-15"), 0)
        XCTAssertEqual(try occurrences(q), ["2026-10-15"])
    }

    /// The notification's "Confirm now" posts through `postScheduled`; when it got
    /// there first, the generator sees that occurrence as done — even posted late
    /// under a different date — and does not add a second.
    func test_occurrencePostedByPostScheduled_isNotGeneratedAgain() throws {
        let q = try seeded()
        try create(q)
        try run(q, "2026-10-01")
        try Apply.apply(dbQueue: q, action: "postScheduled", args: Args([
            "templateId": .string("s1"), "date": .string("2026-10-16"), "occurrenceDate": .string("2026-10-15"),
        ]))
        XCTAssertEqual(try run(q, "2026-10-16"), 0)
        XCTAssertEqual(try occurrences(q), ["2026-10-15"])
    }

    /// The manual "Post" flow saves the prefilled Add sheet: an `addTransaction`
    /// carrying the template and occurrence. Same dedupe.
    func test_occurrencePostedFromTheSheet_isNotGeneratedAgain() throws {
        let q = try seeded()
        try create(q)
        try run(q, "2026-10-01")
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-100), "merchant": .string("Rent"),
            "date": .string("2026-10-14"), "sourceTemplateId": .string("s1"), "occurrenceDate": .string("2026-10-15"),
            "skipRules": .bool(true),
        ]))
        XCTAssertEqual(try run(q, "2026-10-20"), 0)
        XCTAssertEqual(try occurrences(q), ["2026-10-15"])
    }

    // MARK: - Caps

    func test_installmentTotal_capsGeneration() throws {
        let q = try seeded()
        try create(q, extra: ["installmentTotal": .int(2)])
        try run(q, "2026-08-01")
        XCTAssertEqual(try run(q, "2026-12-31"), 2)
        XCTAssertEqual(try occurrences(q), ["2026-08-15", "2026-09-15"])
    }

    func test_variableAmountTemplate_isSkipped() throws {
        let q = try seeded()
        try create(q, extra: ["amount": .null])
        try run(q, "2026-10-01")
        XCTAssertEqual(try run(q, "2026-10-20"), 0)
    }

    func test_inactiveTemplate_isSkipped() throws {
        let q = try seeded()
        try create(q)
        try q.write { try $0.execute(sql: "UPDATE scheduled_templates SET is_active = 0") }
        try run(q, "2026-10-01")
        XCTAssertEqual(try run(q, "2026-10-20"), 0)
    }

    func test_rejectsAMalformedToday() throws {
        let q = try seeded()
        XCTAssertThrowsError(try run(q, "10/17/2026"))
        XCTAssertNil(try mark(q))
    }

    // MARK: - The parity action is unchanged

    /// `generateDueScheduled` keeps the web's behaviour exactly — every active
    /// template, from its start date, no mark read or written — so the write-parity
    /// fixture still holds.
    func test_parityAction_stillIgnoresAutoPostAndTheMark() throws {
        let q = try seeded()
        try create(q, autoPost: false)
        try Apply.apply(dbQueue: q, action: "generateDueScheduled", args: Args(["today": .string("2026-03-20")]))
        XCTAssertEqual(try occurrences(q), ["2026-01-15", "2026-02-15", "2026-03-15"])
        XCTAssertNil(try mark(q))
    }
}
