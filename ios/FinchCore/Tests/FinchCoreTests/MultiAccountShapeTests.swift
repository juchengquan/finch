import XCTest
import GRDB
@testable import FinchCore

final class MultiAccountShapeTests: XCTestCase {

    /// Seed a second USD account so an entry can span two of them.
    private func seedTwoAccounts() throws -> DatabaseQueue {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Card','credit_card','USD',0,1,1,1,datetime('now'),datetime('now'))
                """)
        }
        return q
    }

    /// $100 of groceries, $60 on the card and $40 in cash. One purchase.
    func test_expenseAcrossTwoAccounts_passesAudit() throws {
        let q = try seedTwoAccounts()
        try q.write { db in
            _ = try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: "l1", date: "2026-06-01", time: "12:00",
                description: "Market", kind: .expense,
                legs: [
                    .account(Entries.AccountLeg(accountId: "a2", amount: -60)),
                    .account(Entries.AccountLeg(accountId: "a1", amount: -40)),
                    .category(Entries.CategoryLeg(categoryId: "c1", amountBase: 100)),
                ]))
        }
        let problems = try Audit.run(on: q)
        XCTAssertTrue(problems.filter { $0.code == .kindShape }.isEmpty,
                      "a two-account expense is a legal shape: \(problems.map(\.detail))")
    }

    /// The relaxation must NOT loosen transfers — I7 still pins them at exactly 2
    /// account legs and no category leg.
    ///
    /// Built via raw SQL rather than `Entries.postEntry`: `validateShape`'s `.transfer`
    /// branch is untouched by this task and still throws `error.transfer.twoLegs` for a
    /// 3-leg transfer, so postEntry can never write this shape — there would be nothing
    /// for `Audit.run` to see. Constructing the row directly (mirroring the
    /// `Fixtures/audit/kind-shape*` corruption fixtures, which exist for exactly this
    /// reason) tests the AUDIT's kind-shape rule in isolation from the write-path guard,
    /// which is what this test is actually about. `tr_entry_seal` only requires the
    /// entry to balance with >=2 postings and >=1 account leg — it has no per-kind
    /// shape opinion — so sealing a 3-account-leg "transfer" is legal at the DB layer.
    func test_transferWithThreeAccountLegs_stillFailsAudit() throws {
        let q = try seedTwoAccounts()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a3','l1','Savings','savings','USD',0,2,1,1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO entries (id,ledger_id,date,time,description,kind,status,sealed,created_at,updated_at)
                VALUES ('e1','l1','2026-06-01','12:05','Sweep','transfer','confirmed',0,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO postings (id,entry_id,account_id,category_id,amount,currency,amount_base,exchange_rate,sort_order)
                VALUES ('p1','e1','a1',NULL,-100,'USD',-100,1,0),
                       ('p2','e1','a2',NULL,40,'USD',40,1,1),
                       ('p3','e1','a3',NULL,60,'USD',60,1,2)
                """)
            try db.execute(sql: "UPDATE entries SET sealed = 1 WHERE id = 'e1'")
        }
        let problems = try Audit.run(on: q)
        XCTAssertFalse(problems.filter { $0.code == .kindShape }.isEmpty,
                       "a 3-leg transfer must still be a kind-shape defect")
    }

    /// Complements the audit test above: this proves the WRITE PATH itself still
    /// refuses a 3-leg transfer via `Entries.postEntry` — `validateShape`'s `.transfer`
    /// branch (untouched by this task) must still throw `error.transfer.twoLegs`. The
    /// raw-SQL test above only proves the audit still flags a bad shape that somehow
    /// made it into the database; it says nothing about whether `postEntry` itself still
    /// guards the front door. Neither test replaces the other.
    func test_transferWithThreeAccountLegs_stillThrowsAtWrite() throws {
        let q = try seedTwoAccounts()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a3','l1','Savings','savings','USD',0,2,1,1,datetime('now'),datetime('now'))
                """)
        }
        try q.write { db in
            XCTAssertThrowsError(try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: "l1", date: "2026-06-01", time: "12:05",
                description: "Sweep", kind: .transfer,
                legs: [
                    .account(Entries.AccountLeg(accountId: "a1", amount: -100)),
                    .account(Entries.AccountLeg(accountId: "a2", amount: 40)),
                    .account(Entries.AccountLeg(accountId: "a3", amount: 60)),
                ]))) {
                XCTAssertEqual(($0 as? I18nError)?.code, "error.transfer.twoLegs")
            }
        }
    }

    /// A split-tender purchase must not be presented as a transfer.
    func test_twoAccountExpense_isNotATransferGroup() throws {
        let q = try seedTwoAccounts()
        try q.write { db in
            _ = try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: "l1", date: "2026-06-01", time: "12:00",
                description: "Market", kind: .expense,
                legs: [
                    .account(Entries.AccountLeg(accountId: "a2", amount: -60)),
                    .account(Entries.AccountLeg(accountId: "a1", amount: -40)),
                    .category(Entries.CategoryLeg(categoryId: "c1", amountBase: 100)),
                ]))
        }
        let txns = try Projection.run(dbQueue: q, ledgerId: "l1")
        XCTAssertEqual(txns.count, 2, "one row per account leg")
        XCTAssertTrue(txns.allSatisfy { $0.transferGroupId == nil },
                      "a split-tender expense is not a transfer")
    }

    /// A genuine transfer keeps its grouping.
    func test_transfer_stillCarriesTransferGroupId() throws {
        let q = try seedTwoAccounts()
        try q.write { db in
            _ = try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: "l1", date: "2026-06-02", time: "09:00",
                description: "Move", kind: .transfer,
                legs: [
                    .account(Entries.AccountLeg(accountId: "a1", amount: -50)),
                    .account(Entries.AccountLeg(accountId: "a2", amount: 50)),
                ]))
        }
        let txns = try Projection.run(dbQueue: q, ledgerId: "l1")
        XCTAssertEqual(txns.count, 2)
        XCTAssertTrue(txns.allSatisfy { $0.transferGroupId != nil },
                      "a transfer's two legs must stay grouped")
    }
}
