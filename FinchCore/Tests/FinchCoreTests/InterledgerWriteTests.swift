import XCTest
import GRDB
@testable import FinchCore

/// The cross-ledger transfer write path (2026-08-12 design, D1/D4/D5).
///
/// One user action, two entries — one per ledger, each balanced in its OWN base
/// currency, tied by a shared link id. The pair is created, edited and deleted as
/// a unit; neither half is a valid thing to leave behind on its own.
final class InterledgerWriteTests: XCTestCase {

    /// Personal (USD) with Checking, Travel (EUR) with a card, plus a rate so the
    /// arriving amount can be derived when the caller omits it.
    private func twoLedgers() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('personal','Personal','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('travel','Travel','EUR',0,datetime('now'),datetime('now'))")
            // Balance 0 + a real opening entry, not a hand-set cached number: the
            // audit's balance-drift rule compares the cached balance against the
            // sum of postings, and a fixture that fakes the balance fails it (as
            // this one did, which is the rule working).
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('checking','personal','Checking','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('card','travel','Travel Card','credit_card','EUR',0,0,1,1,datetime('now'),datetime('now'))")
            // USD-per-unit, the hub convention: EUR is worth more than USD.
            try db.execute(sql: "INSERT INTO exchange_rates (date,currency,rate) VALUES ('2026-08-12','EUR',1.10)")
            try db.execute(sql: "INSERT INTO exchange_rates (date,currency,rate) VALUES ('2026-08-12','USD',1.0)")
            try Entries.postOpening(db, ledgerId: "personal", accountId: "checking",
                                    amount: 12000, date: "2026-01-01")
        }
        return q
    }

    private func create(_ q: DatabaseQueue, received: Double? = 4600) throws {
        var args: [String: JSONValue] = [
            "fromAccountId": .string("checking"),
            "toAccountId": .string("card"),
            "fromAmount": .double(5000),
            "date": .string("2026-08-12"),
        ]
        if let received { args["toAmount"] = .double(received) }
        try Apply.apply(dbQueue: q, action: "createInterledgerTransfer", args: Args(args))
    }

    // MARK: creating the pair

    func test_createWritesOneBalancedHalfPerLedger() throws {
        let q = try twoLedgers()
        try create(q)
        try q.read { db in
            let kinds = try String.fetchAll(db, sql: "SELECT kind FROM entries WHERE kind = 'interledger' ORDER BY ledger_id")
            XCTAssertEqual(kinds, ["interledger", "interledger"], "exactly two halves, both labelled")
            let ledgers = try String.fetchAll(db, sql: "SELECT ledger_id FROM entries WHERE kind = 'interledger' ORDER BY ledger_id")
            XCTAssertEqual(ledgers, ["personal", "travel"], "one half in each book")

            // Each half balances in its OWN base — the reason a single entry can't
            // span two ledgers in the first place.
            for eid in try String.fetchAll(db, sql: "SELECT id FROM entries WHERE kind = 'interledger'") {
                let sum = try Double.fetchOne(db, sql: "SELECT ROUND(SUM(amount_base), 2) FROM postings WHERE entry_id = ?", arguments: [eid])
                XCTAssertEqual(sum, 0, "half \(eid) must balance on its own")
                XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [eid]), 1,
                               "one account leg per half — two would be an ordinary transfer")
            }
        }
    }

    func test_bothHalvesShareOneLinkId() throws {
        let q = try twoLedgers()
        try create(q)
        try q.read { db in
            let links = try String.fetchAll(db, sql: "SELECT interledger_link_id FROM entries WHERE interledger_link_id IS NOT NULL")
            XCTAssertEqual(links.count, 2)
            XCTAssertFalse(links[0].isEmpty)
            XCTAssertEqual(links[0], links[1], "the pair is one thing — that is what the link is for")
        }
    }

    func test_moneyLeavesOneBookAndArrivesInTheOther() throws {
        let q = try twoLedgers()
        try create(q)
        try q.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id = 'checking'"), 7000,
                           "Personal is poorer by the amount that left")
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id = 'card'"), 4600,
                           "Travel is richer by the amount that arrived, in its own currency")
        }
    }

    /// D7: the partner's name is stamped at write time, so a row can say where the
    /// money went without the projection ever reaching into another ledger.
    func test_eachHalfNamesThePartner() throws {
        let q = try twoLedgers()
        try create(q)
        try q.read { db in
            let personal = try String.fetchOne(db, sql: "SELECT description FROM entries WHERE ledger_id = 'personal' AND kind = 'interledger'")
            let travel = try String.fetchOne(db, sql: "SELECT description FROM entries WHERE ledger_id = 'travel' AND kind = 'interledger'")
            XCTAssertEqual(personal, "Travel · Travel Card")
            XCTAssertEqual(travel, "Personal · Checking")
        }
    }

    /// The write path and the audit must agree — a shape the writer produces can
    /// never be one the audit calls corrupt, or import would reject our own data.
    func test_theResultPassesTheAudit() throws {
        let q = try twoLedgers()
        try create(q)
        let problems = try Audit.run(on: q)
        XCTAssertTrue(problems.isEmpty, "the writer must not produce shapes the audit rejects: \(problems)")
    }

    /// D5: omitting the received amount derives it from the stored rate.
    func test_receivedAmountDerivesFromTheRateWhenOmitted() throws {
        let q = try twoLedgers()
        try create(q, received: nil)
        // 5000 USD at 1.10 USD-per-EUR ≈ 4545.45 EUR.
        let arrived = try q.read { try Double.fetchOne($0, sql: "SELECT current_balance FROM accounts WHERE id = 'card'") } ?? 0
        XCTAssertEqual(arrived, 4545.45, accuracy: 0.01)
    }

    // MARK: what it refuses

    func test_refusesTwoAccountsInTheSameLedger() throws {
        let q = try twoLedgers()
        try q.write { db in
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('savings','personal','Savings','savings','USD',0,1,1,1,datetime('now'),datetime('now'))")
        }
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "createInterledgerTransfer", args: Args([
            "fromAccountId": .string("checking"), "toAccountId": .string("savings"),
            "fromAmount": .double(100), "date": .string("2026-08-12"),
        ])), "same-ledger is an ordinary transfer — taking it here would write two entries where one belongs")
    }

    func test_refusesTheSameAccount() throws {
        let q = try twoLedgers()
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "createInterledgerTransfer", args: Args([
            "fromAccountId": .string("checking"), "toAccountId": .string("checking"),
            "fromAmount": .double(100), "date": .string("2026-08-12"),
        ])))
    }

    // MARK: editing and deleting the pair

    func test_deletingEitherHalfRemovesBoth() throws {
        let q = try twoLedgers()
        try create(q)
        let personalId = try q.read { try String.fetchOne($0, sql: "SELECT id FROM entries WHERE ledger_id = 'personal' AND kind = 'interledger'") }!
        try Apply.apply(dbQueue: q, action: "deleteInterledgerTransfer", args: Args(["id": .string(personalId)]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE kind = 'interledger'"), 0,
                           "deleting one side must not leave an orphan claiming money arrived from nowhere")
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id = 'checking'"), 12000,
                           "both books return to where they started")
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id = 'card'"), 0)
        }
    }

    func test_updatingAmountsRewritesBothHalves() throws {
        let q = try twoLedgers()
        try create(q)
        let personalId = try q.read { try String.fetchOne($0, sql: "SELECT id FROM entries WHERE ledger_id = 'personal' AND kind = 'interledger'") }!
        try Apply.apply(dbQueue: q, action: "updateInterledgerTransfer", args: Args([
            "id": .string(personalId), "fromAmount": .double(6000), "toAmount": .double(5500),
        ]))
        try q.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id = 'checking'"), 6000)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id = 'card'"), 5500)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE kind = 'interledger'"), 2,
                           "still exactly one pair")
            let links = try String.fetchAll(db, sql: "SELECT DISTINCT interledger_link_id FROM entries WHERE interledger_link_id IS NOT NULL")
            XCTAssertEqual(links.count, 1, "the pair keeps its identity across an edit")
        }
        XCTAssertTrue(try Audit.run(on: q).isEmpty, "an edited pair must still be well-formed")
    }
}
