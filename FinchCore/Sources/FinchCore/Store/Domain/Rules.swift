import Foundation
import GRDB

/// Rules domain — port of lib/db/domain/rules/mutations.ts (CRUD) plus
/// backfillRule, which replays the rules engine over existing entries.
public enum Rules {
    public static let handlers: [ActionName: Apply.Handler] = [
        .createRule: create,
        .updateRule: update,
        .deleteRule: delete,
        .backfillRule: backfill,
    ]

    /// Active rules for a ledger, priority then created_at — the web's
    /// `listActiveRules`; used by both backfill and postEntry's on-insert hook.
    static func activeRules(_ db: Database, _ ledgerId: String) throws -> [Rule] {
        try Row.fetchAll(db, sql: "SELECT * FROM rules WHERE ledger_id = ? AND is_active = 1 ORDER BY priority, created_at",
                         arguments: [ledgerId]).compactMap(ruleFromRow)
    }

    /// Build a `Rule` from a `rules` row (parse the condition/actions JSON blobs).
    static func ruleFromRow(_ r: Row) -> Rule? {
        guard let condStr = r["condition"] as String?,
              let condJSON = condStr.data(using: .utf8).flatMap({ try? JSONDecoder().decode(JSONValue.self, from: $0) }),
              let condition = RuleCondition.parse(condJSON) else { return nil }
        let actions: [RuleAction] = {
            guard let s = r["actions"] as String?, let data = s.data(using: .utf8),
                  let v = try? JSONDecoder().decode(JSONValue.self, from: data), case .array(let arr) = v else { return [] }
            return arr.compactMap(RuleAction.parse)
        }()
        return Rule(id: r["id"], ledgerId: r["ledger_id"], priority: (r["priority"] as Int?) ?? 100,
                    condition: condition, actions: actions,
                    isActive: ((r["is_active"] as Int?) ?? 0) != 0, runOnEdit: ((r["run_on_edit"] as Int?) ?? 0) != 0)
    }

    private static func synthTx(_ r: Row) -> Tx? {
        var o: [String: JSONValue] = [
            "id": .string(r["id"]), "merchant": .string((r["description"] as String?) ?? ""),
            "amount": .double(r["amount_base"]), "nativeAmount": .double(r["amount"]),
            "account": .string(r["account_id"]), "date": .string(r["date"]),
            "ledgerId": .string(r["ledger_id"]), "pending": .bool(false),
        ]
        if let tm = r["time"] as String? { o["time"] = .string(tm) }   // web parity (mutations.ts:72)
        if let c = r["category_id"] as String? { o["category"] = .string(c) }
        if let cur = r["currency"] as String? { o["currency"] = .string(cur) }
        if let k = r["kind"] as String? { o["kind"] = .string(k) }
        if let cp = r["counterparty_id"] as String? { o["counterpartyId"] = .string(cp) }
        if let n = r["notes"] as String? { o["note"] = .string(n) }
        guard let data = try? JSONEncoder().encode(JSONValue.object(o)) else { return nil }
        return try? JSONDecoder().decode(Tx.self, from: data)
    }

    /// Apply a rule to existing confirmed income/expense/refund entries.
    static func backfill(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String }
        let ruleId = try args.to(A.self).id
        guard let rr = try Row.fetchOne(db, sql: "SELECT * FROM rules WHERE id = ?", arguments: [ruleId]) else {
            throw I18nError("error.notFound.rule", [:], "Rule not found")
        }
        guard let rule = ruleFromRow(rr) else { return }
        let entryRows = try Row.fetchAll(db, sql: """
            SELECT e.id, e.ledger_id, e.date, e.time, e.description, e.kind, e.notes, e.counterparty_id, e.applied_rule_ids,
                   p.account_id, p.amount, p.amount_base, p.currency, p.category_id
              FROM entries e JOIN postings p ON p.entry_id = e.id AND p.account_id IS NOT NULL
             WHERE e.ledger_id = ? AND e.status = 'confirmed' AND e.kind IN ('income','expense','refund')
            """, arguments: [rule.ledgerId])

        for r in entryRows {
            guard let t = synthTx(r) else { continue }
            let patch = RulesEngine.applyRules(t, [rule])
            if !patch.appliedRuleIds.contains(rule.id) { continue }
            let entryId: String = r["id"]

            var sets: [String] = []
            var bind: [DatabaseValueConvertible?] = []
            if case .set(let cp) = patch.counterpartyId { sets.append("counterparty_id = ?"); bind.append(cp) }
            if let m = patch.merchant {
                sets.append("description = ?"); bind.append(m)
                sets.append("counterparty_id = ?"); bind.append(try Entries.resolveCounterpartyIdByName(db, rule.ledgerId, m))
            }
            if let n = patch.note { sets.append("notes = ?"); bind.append(n) }
            if let k = patch.kind { sets.append("kind = ?"); bind.append(k) }
            if patch.reviewed { sets.append("reviewed_at = datetime('now')") }
            // merge rule id into applied_rule_ids
            var prev: [String] = {
                guard let s = r["applied_rule_ids"] as String?, let data = s.data(using: .utf8),
                      let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
                return arr
            }()
            if !prev.contains(rule.id) { prev.append(rule.id) }
            sets.append("applied_rule_ids = ?")
            bind.append((try? String(data: JSONEncoder().encode(prev), encoding: .utf8)) ?? "[]")
            // The web only writes the header when there's a change beyond applied_rule_ids.
            if sets.count > 1 {
                sets.append("updated_at = datetime('now')"); bind.append(entryId)
                try db.execute(sql: "UPDATE entries SET \(sets.joined(separator: ", ")) WHERE id = ?", arguments: StatementArguments(bind))
            }

            if case .set(let catId) = patch.categoryId {
                let catCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE entry_id = ? AND category_id IS NOT NULL", arguments: [entryId]) ?? 0
                if catCount < 2, let acct = try Row.fetchOne(db, sql: "SELECT id, account_id, amount, amount_base, exchange_rate, memo, orig_amount, orig_currency, cleared_at FROM postings WHERE entry_id = ? AND account_id IS NOT NULL LIMIT 1", arguments: [entryId]) {
                    let acctBase: Double = acct["amount_base"]
                    var ep = Entries.EntryPatch()
                    ep.legs = .set([
                        .account(Entries.AccountLeg(accountId: acct["account_id"], amount: acct["amount"], amountBase: acctBase, exchangeRate: (acct["exchange_rate"] as Double?) ?? 1, memo: acct["memo"], id: acct["id"],
                            origAmount: acct["orig_amount"], origCurrency: acct["orig_currency"], clearedAt: acct["cleared_at"])),
                        .category(Entries.CategoryLeg(categoryId: catId, amountBase: -acctBase)),
                    ])
                    try Entries.rebuildEntry(db, entryId, ep)
                }
            }

            for tagId in patch.tagIdsAdd ?? [] {
                try db.execute(sql: "INSERT OR IGNORE INTO entry_tags (entry_id, tag_id) VALUES (?, ?)", arguments: [entryId, tagId])
            }
        }
        try db.execute(sql: "UPDATE rules SET last_applied_at = datetime('now') WHERE id = ?", arguments: [ruleId])
    }

    static func create(_ db: Database, _ args: Args) throws {
        let v = args.values
        let ledgerId = v["ledgerId"]?.asString ?? "personal"
        guard let condition = v["condition"], condition != .null else {
            throw I18nError("error.required.ruleCondition", [:], "Rule condition is required")
        }
        let actionsJson: String = { if case .array? = v["actions"] { return v["actions"]!.jsonString }; return "[]" }()
        let name = v["name"]?.asString
        let priority = v["priority"]?.asDouble.map { Int($0) } ?? 100
        let isActive = (v["isActive"] == .bool(false)) ? 0 : 1   // default true
        let runOnEdit = (v["runOnEdit"] == .bool(true)) ? 1 : 0
        let id = v["id"]?.asString ?? Entries.newId("rule")
        try db.execute(sql: """
            INSERT INTO rules (id, ledger_id, name, priority, condition, actions, is_active, run_on_edit, created_at, updated_at)
            VALUES (?,?,?,?,?,?,?,?,datetime('now'),datetime('now'))
            """, arguments: [id, ledgerId, name, priority, condition.jsonString, actionsJson, isActive, runOnEdit])
    }

    static func update(_ db: Database, _ args: Args) throws {
        guard let id = args.idString else { throw I18nError("error.invalidArgs", [:], "updateRule requires an id") }
        let patch = args.patchObject
        var sets: [String] = []
        var bind: [DatabaseValueConvertible?] = []
        if patch.keys.contains("name") { sets.append("name = ?"); bind.append(patch["name"]!.sqlBind) }
        if let p = patch["priority"] { sets.append("priority = ?"); bind.append(p.asDouble.map { Int($0) }) }
        if let c = patch["condition"] { sets.append("condition = ?"); bind.append(c.jsonString) }
        if let a = patch["actions"] { sets.append("actions = ?"); bind.append(a.jsonString) }
        if let ia = patch["isActive"] { sets.append("is_active = ?"); bind.append(ia.isTruthy ? 1 : 0) }
        if let re = patch["runOnEdit"] { sets.append("run_on_edit = ?"); bind.append(re.isTruthy ? 1 : 0) }
        if sets.isEmpty { return }
        sets.append("updated_at = datetime('now')")
        bind.append(id)
        try db.execute(sql: "UPDATE rules SET \(sets.joined(separator: ", ")) WHERE id = ?", arguments: StatementArguments(bind))
    }

    static func delete(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String }
        try db.execute(sql: "DELETE FROM rules WHERE id = ?", arguments: [try args.to(A.self).id])
    }
}
