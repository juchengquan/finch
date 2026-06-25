import Foundation
import GRDB

/// The rest of the projection surface (beyond the `Tx[]` in Projection.swift)
/// that `FinchStore` needs for the 4 tabs: ledgers, accounts (with balances),
/// budgets, categories, counterparties, exchange rates. Each mirrors the web
/// `lib/db/queries/*` SELECTs (see the field maps in the Phase 1.0 plan / the
/// web state projection). Accounts/budgets/categories are ledger-scoped; the
/// web `projectState` returns all ledgers and the client filters — here the
/// active-ledger filter is pushed into SQL since the tabs only show one ledger.
extension Projection {

    /// `ledgers` — `base` ← `base_currency`. ORDER BY is_default DESC, name.
    public static func ledgers(dbQueue: DatabaseQueue) throws -> [Ledger] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, name, base_currency AS base, color, tagline
                  FROM ledgers ORDER BY is_default DESC, name
                """).map { r in
                Ledger(id: r["id"], name: r["name"], base: r["base"],
                       color: r["color"], tagline: r["tagline"])
            }
        }
    }

    /// `accounts` — `balance` is the stored `current_balance` (kept in sync by
    /// the posting triggers); `groupName` from the LEFT JOIN. Active only.
    public static func accounts(dbQueue: DatabaseQueue, ledgerId: String) throws -> [AccountRow] {
        try accountRows(dbQueue: dbQueue, ledgerId: ledgerId, active: true)
    }

    /// Archived (is_active = 0) accounts — for the unarchive view.
    public static func archivedAccounts(dbQueue: DatabaseQueue, ledgerId: String) throws -> [AccountRow] {
        try accountRows(dbQueue: dbQueue, ledgerId: ledgerId, active: false)
    }

    private static func accountRows(dbQueue: DatabaseQueue, ledgerId: String, active: Bool) throws -> [AccountRow] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT a.id, a.ledger_id AS ledgerId, a.name, a.type, a.currency,
                       a.current_balance AS balance, a.group_id AS groupId,
                       g.name AS groupName, a.sort_order AS sortOrder,
                       a.include_in_net_worth AS inw, a.is_active AS isActive,
                       a.last_reconciled_at AS lastReconciledAt, a.last_reconciled_balance AS lastReconciledBalance
                  FROM accounts a
                  LEFT JOIN account_groups g ON a.group_id = g.id
                 WHERE a.ledger_id = ? AND a.is_active = ?
                 ORDER BY g.sort_order, a.sort_order, a.name
                """, arguments: [ledgerId, active ? 1 : 0]).map { r in
                AccountRow(
                    id: r["id"], balance: r["balance"], ledgerId: r["ledgerId"],
                    currency: r["currency"], includeInNetWorth: r["inw"],
                    isActive: (r["isActive"] as Int? ?? 0) != 0, name: r["name"],
                    type: r["type"], groupId: r["groupId"], groupName: r["groupName"],
                    sortOrder: r["sortOrder"],
                    lastReconciledAt: r["lastReconciledAt"], lastReconciledBalance: r["lastReconciledBalance"])
            }
        }
    }

    /// Account groups (id + name), ordered — for the group picker + group admin.
    public static func accountGroups(dbQueue: DatabaseQueue, ledgerId: String) throws -> [GroupRow] {
        try groupRows(dbQueue: dbQueue, ledgerId: ledgerId, table: "account_groups")
    }

    /// Budget groups (id + name), ordered — for the group picker + group admin.
    public static func budgetGroups(dbQueue: DatabaseQueue, ledgerId: String) throws -> [GroupRow] {
        try groupRows(dbQueue: dbQueue, ledgerId: ledgerId, table: "budget_groups")
    }

    /// The per-ledger display-currency map (`app_state.displayCurrencyByLedger`).
    public static func displayCurrencyByLedger(dbQueue: DatabaseQueue) throws -> [String: String] {
        try dbQueue.read { db in
            guard let raw = try String.fetchOne(db, sql: "SELECT value FROM app_state WHERE key = 'displayCurrencyByLedger'"),
                  let data = raw.data(using: .utf8),
                  let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
            return map
        }
    }

    private static func groupRows(dbQueue: DatabaseQueue, ledgerId: String, table: String) throws -> [GroupRow] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, name FROM \(table) WHERE ledger_id = ? ORDER BY sort_order, name",
                             arguments: [ledgerId]).map { GroupRow(id: $0["id"], name: $0["name"]) }
        }
    }

    /// `budgets` — `type` ← (`kind` == 'income' ? 'income' : 'expense');
    /// `accountIds`/`categoryIds` ← JSON-parse of the `account_ids`/`category_ids`
    /// text columns (`parseIds`). ORDER BY created_at.
    public static func budgets(dbQueue: DatabaseQueue, ledgerId: String) throws -> [BudgetRow] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, ledger_id, group_id, name, kind, amount, saved, carry_forward,
                       frequency, start_date, end_date, is_recurring, rollover, rollover_limit,
                       pending_amount, last_rolled_period, account_ids, category_ids, warning_pct
                  FROM budgets WHERE ledger_id = ? ORDER BY created_at
                """, arguments: [ledgerId]).map { r in
                let kind: String = r["kind"]
                return BudgetRow(
                    id: r["id"], ledgerId: r["ledger_id"], groupId: r["group_id"],
                    name: r["name"] ?? "", type: kind == "income" ? "income" : "expense",
                    amount: r["amount"], saved: r["saved"] ?? 0, carryForward: r["carry_forward"] ?? 0,
                    frequency: r["frequency"], startDate: r["start_date"], endDate: r["end_date"],
                    isRecurring: r["is_recurring"] ?? 1, rollover: r["rollover"] ?? 0,
                    rolloverLimit: r["rollover_limit"], pendingAmount: r["pending_amount"],
                    lastRolledPeriod: r["last_rolled_period"],
                    accountIds: parseIds(r["account_ids"]), categoryIds: parseIds(r["category_ids"]),
                    warningPct: r["warning_pct"] ?? 80)
            }
        }
    }

    /// `categories` — equity rows excluded (they're opening/adjustment markers).
    public static func categories(dbQueue: DatabaseQueue, ledgerId: String) throws -> [CategoryRow] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, ledger_id AS ledgerId, name, parent_id AS parentId, kind, icon, color,
                       sort_order AS sortOrder
                  FROM categories WHERE ledger_id = ? AND kind != 'equity' ORDER BY sort_order
                """, arguments: [ledgerId]).map { r in
                CategoryRow(id: r["id"], ledgerId: r["ledgerId"], name: r["name"],
                            parentId: r["parentId"], kind: r["kind"],
                            icon: r["icon"], color: r["color"], sortOrder: r["sortOrder"])
            }
        }
    }

    /// `counterparties` — canonical merchant names for the active ledger.
    public static func counterparties(dbQueue: DatabaseQueue, ledgerId: String) throws -> [Counterparty] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, ledger_id AS ledgerId, name, is_verified AS isVerified
                  FROM counterparties WHERE ledger_id = ? ORDER BY name
                """, arguments: [ledgerId]).map { r in
                Counterparty(id: r["id"], ledgerId: r["ledgerId"], name: r["name"],
                             isVerified: (r["isVerified"] as Int? ?? 0) != 0)
            }
        }
    }

    /// `budget_groups` id → name, for the Budgets tab grouping ("Ungrouped" for
    /// budgets with a null `group_id`). ORDER BY sort_order, name.
    public static func budgetGroupNames(dbQueue: DatabaseQueue, ledgerId: String) throws -> [String: String] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, name FROM budget_groups WHERE ledger_id = ? ORDER BY sort_order, name
                """, arguments: [ledgerId]).reduce(into: [String: String]()) { $0[$1["id"]] = $1["name"] }
        }
    }

    /// `exchange_rates` — every rate row (latest-per-currency is resolved client
    /// side by `Money.latestRateMap`).
    public static func exchangeRates(dbQueue: DatabaseQueue) throws -> [ExchangeRate] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT date, currency, rate, source FROM exchange_rates").map { r in
                ExchangeRate(date: r["date"], currency: r["currency"], rate: r["rate"], source: r["source"])
            }
        }
    }

    /// `holdings` for a ledger (Phase 1.5) — the investment positions the
    /// Insights/holdings selectors consume.
    public static func holdings(dbQueue: DatabaseQueue, ledgerId: String) throws -> [Holding] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, ledger_id AS ledgerId, account_id AS accountId, symbol, name,
                       shares, cost_basis AS costBasis, currency, last_price AS lastPrice,
                       last_price_date AS lastPriceDate, notes
                  FROM holdings WHERE ledger_id = ? ORDER BY symbol
                """, arguments: [ledgerId]).map { r in
                Holding(id: r["id"], ledgerId: r["ledgerId"], accountId: r["accountId"], symbol: r["symbol"],
                        name: r["name"], shares: r["shares"], costBasis: r["costBasis"], currency: r["currency"],
                        lastPrice: r["lastPrice"], lastPriceDate: r["lastPriceDate"], notes: r["notes"])
            }
        }
    }

    /// Attachments for a transaction. `txId` may be a client Tx id (account
    /// posting id) or an entry id — resolved to the entry like the chokepoint does.
    public static func attachments(dbQueue: DatabaseQueue, txId: String) throws -> [AttachmentRow] {
        try dbQueue.read { db in
            let entryId = (try String.fetchOne(db, sql: "SELECT entry_id FROM postings WHERE id = ?", arguments: [txId])) ?? txId
            return try Row.fetchAll(db, sql: """
                SELECT id, kind, rel_path, original_filename FROM entry_attachments
                 WHERE entry_id = ? ORDER BY created_at
                """, arguments: [entryId]).map {
                AttachmentRow(id: $0["id"], kind: $0["kind"], relPath: $0["rel_path"], originalFilename: $0["original_filename"])
            }
        }
    }

    /// Tags for a ledger (Phase 4 tag admin), name-ordered.
    public static func tags(dbQueue: DatabaseQueue, ledgerId: String) throws -> [TagRow] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, name, color FROM tags WHERE ledger_id = ? ORDER BY name",
                             arguments: [ledgerId]).map { TagRow(id: $0["id"], name: $0["name"], color: $0["color"]) }
        }
    }

    /// Rule rows for the Phase 4 rules manager — name/priority/active plus the raw
    /// condition/actions JSON + runOnEdit (so the manager can edit, not just toggle).
    public static func rules(dbQueue: DatabaseQueue, ledgerId: String) throws -> [RuleSummary] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, name, priority, is_active, condition, actions, run_on_edit FROM rules
                 WHERE ledger_id = ? ORDER BY priority, created_at
                """, arguments: [ledgerId]).map { r in
                RuleSummary(id: r["id"], name: (r["name"] as String?) ?? "Rule",
                            priority: (r["priority"] as Int?) ?? 100,
                            isActive: ((r["is_active"] as Int?) ?? 0) != 0,
                            conditionJSON: (r["condition"] as String?) ?? "",
                            actionsJSON: (r["actions"] as String?) ?? "[]",
                            runOnEdit: ((r["run_on_edit"] as Int?) ?? 0) != 0)
            }
        }
    }

    /// `scheduled_templates` for a ledger, with the confirmed-installment count
    /// joined in (mirrors the web listScheduled + INSTALLMENT_PAID_JOIN). Ordered
    /// by rowid (insertion order), like the web.
    public static func scheduledTemplates(dbQueue: DatabaseQueue, ledgerId: String) throws -> [ScheduledTemplate] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT t.id, t.name, t.description, t.kind, t.amount, t.frequency,
                       t.day_of_month, t.day_of_week, t.account_id, t.from_account_id, t.category_id,
                       t.start_date, t.end_date, t.next_run, t.max_executions,
                       t.installment_total, t.color, COALESCE(p.n, 0) AS installment_paid
                  FROM scheduled_templates t
                  LEFT JOIN (
                    SELECT source_template_id, COUNT(*) AS n FROM entries
                     WHERE source_template_id IS NOT NULL AND status = 'confirmed'
                     GROUP BY source_template_id
                  ) p ON p.source_template_id = t.id
                 WHERE t.ledger_id = ? ORDER BY t.rowid
                """, arguments: [ledgerId]).map { r in
                ScheduledTemplate(
                    id: r["id"], name: (r["name"] as String?) ?? "", description: r["description"],
                    type: r["kind"], amount: r["amount"], frequency: r["frequency"],
                    dayOfMonth: (r["day_of_month"] as Int?) ?? 1, weekDay: r["day_of_week"],
                    accountId: r["account_id"], fromAccountId: r["from_account_id"],
                    categoryId: r["category_id"],
                    startDate: r["start_date"], endDate: r["end_date"],
                    nextRun: (r["next_run"] as String?) ?? "", maxExecutions: r["max_executions"],
                    installmentTotal: r["installment_total"], installmentPaid: r["installment_paid"], color: r["color"])
            }
        }
    }

    /// JSON-array text column → `[String]` (empty on null/malformed) — mirrors
    /// the web `parseIds` helper (budgets.ts:16).
    private static func parseIds(_ raw: String?) -> [String] {
        guard let raw, let data = raw.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }
}
