import Foundation
import GRDB

/// Budgets domain — port of lib/db/domain/budgets/mutations.ts (the budget
/// actions; the budget-group actions live in Groups.swift). DEFERRED: the
/// withDedupMessage wrapping on create + rollover invalidation.
public enum Budgets {
    public static let handlers: [ActionName: Apply.Handler] = [
        .createBudget: create,
        .updateBudget: update,
        .updateBudgetCycle: updateCycle,
        .clearPendingAmount: clearPending,
        .removeBudget: remove,
        .contributeBudget: contribute,
    ]

    /// JSON array text, or nil for an empty list — matches the web `idsToJson`
    /// (`ids.length ? JSON.stringify(ids) : null`), so the column stores NULL.
    private static func idsToJson(_ ids: [String]) -> String? {
        if ids.isEmpty { return nil }
        return (try? JSONEncoder().encode(ids)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func create(_ db: Database, _ args: Args) throws {
        struct A: Decodable {
            let id: String?; let ledgerId: String?; let groupId: String?; let name: String; let type: String?
            let amount: Double; let saved: Double?; let frequency: String?; let startDate: String?; let endDate: String?
            let isRecurring: Double?; let rolloverLimit: Double?
            let accountIds: [String]?; let categoryIds: [String]?; let warningPct: Double?
        }
        let a = try args.to(A.self)
        let name = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw I18nError("error.required.budgetName", [:], "Budget name is required") }
        let type = a.type == "income" ? "income" : "expense"
        if !(a.amount > 0) { throw I18nError("error.budget.amountGt0", [:], "Budget amount must be greater than 0") }
        let rollover = (args.values["rollover"]?.isTruthy ?? false) ? 1 : 0
        let isRecurring = a.isRecurring.map { Int($0) } ?? (type == "income" ? 0 : 1)
        let startDate = a.startDate ?? String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        try db.execute(sql: """
            INSERT INTO budgets (id, ledger_id, group_id, name, kind, amount, saved, carry_forward,
                frequency, start_date, end_date, is_recurring, rollover, rollover_limit,
                account_ids, category_ids, warning_pct, created_at, updated_at)
            VALUES (?,?,?,?,?,?,?,0,?,?,?,?,?,?,?,?,?,datetime('now'),datetime('now'))
            """, arguments: [a.id ?? Entries.newId("bgt"), a.ledgerId ?? "personal", a.groupId, name, type,
                             a.amount, a.saved ?? 0, a.frequency ?? "monthly", startDate, a.endDate, isRecurring,
                             rollover, a.rolloverLimit, idsToJson(a.accountIds ?? []), idsToJson(a.categoryIds ?? []),
                             a.warningPct ?? 80])
    }

    private static let cols: [String: String] = [
        "groupId": "group_id", "name": "name", "type": "kind", "amount": "amount", "frequency": "frequency",
        "startDate": "start_date", "endDate": "end_date", "isRecurring": "is_recurring", "rollover": "rollover",
        "rolloverLimit": "rollover_limit", "accountIds": "account_ids", "categoryIds": "category_ids", "warningPct": "warning_pct",
    ]

    static func update(_ db: Database, _ args: Args) throws {
        guard let id = args.idString else { throw I18nError("error.invalidArgs", [:], "updateBudget requires an id") }
        let patch = args.patchObject
        if let n = patch["name"], !n.isNonEmptyTrimmedString { throw I18nError("error.required.budgetName", [:], "Budget name is required") }
        if let amt = patch["amount"], let a = amt.asDouble, !(a > 0) { throw I18nError("error.budget.amountGt0", [:], "Budget amount must be greater than 0") }

        // Amount-only edit on a recurring budget → stage it for the next cycle.
        if patch.count == 1, let amt = patch["amount"]?.asDouble {
            if try Int.fetchOne(db, sql: "SELECT is_recurring FROM budgets WHERE id = ?", arguments: [id]) == 1 {
                try db.execute(sql: "UPDATE budgets SET pending_amount = ?, updated_at = datetime('now') WHERE id = ?", arguments: [amt, id])
                return
            }
        }

        var sets: [String] = []
        var bind: [DatabaseValueConvertible?] = []
        for (key, col) in cols where patch.keys.contains(key) {
            sets.append("\(col) = ?")
            if key == "accountIds" || key == "categoryIds" { bind.append(idsToJson(patch[key]!.asStringArray)) }
            else { bind.append(patch[key]!.sqlBind) }
        }
        if sets.isEmpty { return }
        sets.append("updated_at = datetime('now')")
        bind.append(id)
        try db.execute(sql: "UPDATE budgets SET \(sets.joined(separator: ", ")) WHERE id = ?", arguments: StatementArguments(bind))
    }

    static func updateCycle(_ db: Database, _ args: Args) throws {
        guard let id = args.idString else { throw I18nError("error.invalidArgs", [:], "updateBudgetCycle requires an id") }
        let patch = args.patchObject
        let validFreqs: Set<String> = ["daily", "weekly", "biweekly", "monthly", "quarterly", "yearly"]
        guard let frequency = patch["frequency"]?.asString, validFreqs.contains(frequency) else {
            throw I18nError("error.budget.unknownFreq", ["freq": patch["frequency"]?.asString ?? "nil"], "Unknown frequency")
        }
        guard let startDate = patch["startDate"]?.asString, isYMD(startDate) else {
            throw I18nError("error.budget.dateFormat", [:], "startDate must be YYYY-MM-DD")
        }
        if let amt = patch["amount"]?.asDouble, !(amt > 0) { throw I18nError("error.budget.amountGt0", [:], "Budget amount must be greater than 0") }
        guard let existing = try Row.fetchOne(db, sql: "SELECT amount, end_date FROM budgets WHERE id = ?", arguments: [id]) else {
            throw I18nError("error.notFound.budget", [:], "Budget not found")
        }
        let amount = patch["amount"]?.asDouble ?? (existing["amount"] as Double)
        // undefined keeps existing; explicit (incl. null) sets it.
        let endDate: String? = patch.keys.contains("endDate") ? patch["endDate"]?.asString : (existing["end_date"] as String?)
        try db.execute(sql: """
            UPDATE budgets SET amount = ?, frequency = ?, start_date = ?, end_date = ?,
                pending_amount = NULL, last_rolled_period = NULL, updated_at = datetime('now')
             WHERE id = ?
            """, arguments: [amount, frequency, startDate, endDate, id])
    }

    static func clearPending(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String }
        try db.execute(sql: "UPDATE budgets SET pending_amount = NULL, updated_at = datetime('now') WHERE id = ?", arguments: [try args.to(A.self).id])
    }

    static func remove(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String }
        try db.execute(sql: "DELETE FROM budgets WHERE id = ?", arguments: [try args.to(A.self).id])
    }

    static func contribute(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String; let amount: Double }
        let a = try args.to(A.self)
        if !a.amount.isFinite { throw I18nError("error.budget.invalidContribution", [:], "Invalid contribution amount") }
        try db.execute(sql: "UPDATE budgets SET saved = MAX(0, saved + ?), updated_at = datetime('now') WHERE id = ?", arguments: [a.amount, a.id])
    }
}
