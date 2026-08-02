import XCTest
import GRDB
@testable import FinchCore

final class ScheduledSplitEntryTests: XCTestCase {

    /// A salary split 60/40 across two accounts posts ONE transaction with two account
    /// legs — the same shape the Add sheet produces by hand.
    func test_splitTemplate_postsOneEntryWithTwoAccountLegs() throws {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Savings','savings','USD',0,1,1,1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at)
                VALUES ('cin','l1',NULL,'Salary','income',1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO scheduled_templates
                  (id,ledger_id,name,description,kind,amount,amount_varies,splits_enabled,account_id,category_id,
                   frequency,start_date,auto_post,is_active,created_at,updated_at)
                VALUES ('t1','l1','Salary','Salary','income',3000,0,1,'a1','cin',
                        'monthly','2026-06-01',1,1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO scheduled_splits (id,template_id,account_id,amount_pct,amount_abs,category_id,description,sort_order)
                VALUES ('s1','t1','a1',60,NULL,NULL,'main',0), ('s2','t1','a2',40,NULL,NULL,'savings',1)
                """)
        }
        try Apply.apply(dbQueue: q, action: "postScheduled", args: Args([
            "templateId": .string("t1"), "date": .string("2026-06-01")]))

        let (entries, acctLegs) = try q.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE source_template_id = 't1'") ?? 0,
             try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM postings p JOIN entries e ON e.id = p.entry_id
                 WHERE e.source_template_id = 't1' AND p.account_id IS NOT NULL
                """) ?? 0)
        }
        XCTAssertEqual(entries, 1, "one salary is one transaction")
        XCTAssertEqual(acctLegs, 2, "…carrying both destination accounts")

        // Each split's own `description` has no per-row home on a single entry any
        // more — it is carried onto that leg's `memo` rather than being dropped.
        let legRows = try q.read { db in
            try Row.fetchAll(db, sql: """
                SELECT p.account_id, p.amount, p.memo FROM postings p
                 JOIN entries e ON e.id = p.entry_id
                 WHERE e.source_template_id = 't1' AND p.account_id IS NOT NULL
                 ORDER BY p.account_id
                """)
        }
        XCTAssertEqual(legRows.count, 2)
        let a1Leg = legRows.first { ($0["account_id"] as String?) == "a1" }
        let a2Leg = legRows.first { ($0["account_id"] as String?) == "a2" }
        XCTAssertEqual(a1Leg?["amount"] as Double?, 1800, "60% of 3000")
        XCTAssertEqual(a1Leg?["memo"] as String?, "main")
        XCTAssertEqual(a2Leg?["amount"] as Double?, 1200, "40% of 3000")
        XCTAssertEqual(a2Leg?["memo"] as String?, "savings")

        let problems = try Audit.run(on: q)
        XCTAssertTrue(problems.isEmpty, "the posted entry must be clean: \(problems.map(\.detail))")
    }

    /// `amount_abs` overrides `amount_pct` when both are present on a split — the
    /// same precedence the old per-split loop honoured.
    func test_amountAbsOverridesPct() throws {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Savings','savings','USD',0,1,1,1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at)
                VALUES ('cin','l1',NULL,'Salary','income',1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO scheduled_templates
                  (id,ledger_id,name,description,kind,amount,amount_varies,splits_enabled,account_id,category_id,
                   frequency,start_date,auto_post,is_active,created_at,updated_at)
                VALUES ('t3','l1','Salary','Salary','income',3000,0,1,'a1','cin',
                        'monthly','2026-06-01',1,1,datetime('now'),datetime('now'))
                """)
            // s5 has BOTH amount_pct and amount_abs set — amount_abs must win (500,
            // not 60% of 3000 = 1800).
            try db.execute(sql: """
                INSERT INTO scheduled_splits (id,template_id,account_id,amount_pct,amount_abs,category_id,description,sort_order)
                VALUES ('s5','t3','a1',60,500,NULL,NULL,0), ('s6','t3','a2',40,NULL,NULL,NULL,1)
                """)
        }
        try Apply.apply(dbQueue: q, action: "postScheduled", args: Args([
            "templateId": .string("t3"), "date": .string("2026-06-01")]))

        let a1Amount = try q.read { db in
            try Double.fetchOne(db, sql: """
                SELECT p.amount FROM postings p JOIN entries e ON e.id = p.entry_id
                 WHERE e.source_template_id = 't3' AND p.account_id = 'a1'
                """)
        }
        XCTAssertEqual(a1Amount, 500, "amount_abs (500) must win over amount_pct (60% = 1800)")
    }

    /// Every split resolving to a zero portion (0% and no absolute override) still
    /// throws `error.scheduled.noSplits` — collapsing the loop into one `postEntry`
    /// call must not silently post an empty/unbalanced entry instead.
    func test_allZeroSplits_throwsNoSplits() throws {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Savings','savings','USD',0,1,1,1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at)
                VALUES ('cin','l1',NULL,'Salary','income',1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO scheduled_templates
                  (id,ledger_id,name,description,kind,amount,amount_varies,splits_enabled,account_id,category_id,
                   frequency,start_date,auto_post,is_active,created_at,updated_at)
                VALUES ('t2','l1','Salary','Salary','income',3000,0,1,'a1','cin',
                        'monthly','2026-06-01',1,1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO scheduled_splits (id,template_id,account_id,amount_pct,amount_abs,category_id,description,sort_order)
                VALUES ('s3','t2','a1',0,NULL,NULL,'main',0), ('s4','t2','a2',0,NULL,NULL,'savings',1)
                """)
        }
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "postScheduled", args: Args([
            "templateId": .string("t2"), "date": .string("2026-06-01")]))) { error in
            guard let e = error as? I18nError else { return XCTFail("expected I18nError, got \(error)") }
            XCTAssertEqual(e.code, "error.scheduled.noSplits")
        }

        let entries = try q.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE source_template_id = 't2'") ?? 0
        }
        XCTAssertEqual(entries, 0, "nothing should be posted when every split is zero")
    }
}
