import Foundation
import GRDB

/// Scheduled-templates domain — port of lib/db/domain/scheduled/mutations.ts
/// (the CRUD + split actions). DEFERRED: postScheduled + generateDueScheduled
/// (the template→transaction posting actions) and postSingle/split posting.
public enum Scheduled {
    public static let handlers: [ActionName: Apply.Handler] = [
        .createScheduled: create,
        .updateScheduled: update,
        .deleteScheduled: delete,
        .addScheduledSplit: addSplit,
        .updateScheduledSplit: updateSplit,
        .removeScheduledSplit: removeSplit,
    ]

    /// null/empty → nil; otherwise a positive whole number (else throws).
    private static func parseInstallmentTotal(_ v: JSONValue?) throws -> Int? {
        guard let v, !(v == .null) else { return nil }
        if case .string(let s) = v, s.isEmpty { return nil }
        guard let d = v.asDouble, d > 0, d.truncatingRemainder(dividingBy: 1) == 0 else {
            throw I18nError("error.scheduled.installmentTotal", [:], "Installment total must be a positive whole number")
        }
        return Int(d)
    }

    static func create(_ db: Database, _ args: Args) throws {
        struct A: Decodable {
            let id: String?; let ledgerId: String?; let name: String; let description: String?; let type: String?
            let amount: Double?; let frequency: String?; let dayOfMonth: Double?; let weekDay: Double?
            let accountId: String?; let fromAccountId: String?; let color: String?; let category: String?
            let startDate: String?; let endDate: String?; let maxExecutions: Double?
        }
        let a = try args.to(A.self)
        let name = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw I18nError("error.required.templateName", [:], "Template name is required") }
        let type = a.type ?? "expense"
        if !["income", "expense", "transfer"].contains(type) { throw I18nError("error.account.splitTypeUnknown", ["type": type], "Unknown type \"\(type)\"") }
        let frequency = a.frequency ?? "monthly"
        if !["once", "daily", "weekly", "biweekly", "monthly", "quarterly", "yearly"].contains(frequency) {
            throw I18nError("error.account.splitFreqUnknown", ["freq": frequency], "Unknown frequency \"\(frequency)\"")
        }
        let accountId = (a.accountId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if accountId.isEmpty { throw I18nError("error.required.account", [:], "An account is required") }
        let installmentTotal = try parseInstallmentTotal(args.values["installmentTotal"])
        let fromAccountId = (type == "transfer") ? a.fromAccountId?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let startDate = a.startDate ?? String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        try db.execute(sql: """
            INSERT INTO scheduled_templates
              (id,ledger_id,name,description,kind,amount,amount_varies,splits_enabled,account_id,
               from_account_id,category_id,frequency,day_of_month,day_of_week,start_date,
               end_date,max_executions,installment_total,next_run,last_run,auto_post,color,is_active,created_at,updated_at)
            VALUES (?,?,?,?,?,?,0,0,?,?,?,?,?,?,?,?,?,?,NULL,NULL,?,?,1,datetime('now'),datetime('now'))
            """, arguments: [a.id ?? Entries.newId("sch"), a.ledgerId ?? "personal", name,
                             a.description?.trimmingCharacters(in: .whitespacesAndNewlines), type, a.amount,
                             accountId, fromAccountId, a.category, frequency, Int(a.dayOfMonth ?? 1) == 0 ? 1 : Int(a.dayOfMonth ?? 1),
                             a.weekDay.map { Int($0) }, startDate, a.endDate, a.maxExecutions.map { Int($0) }, installmentTotal,
                             (args.values["autoPost"]?.isTruthy ?? false) ? 1 : 0, a.color])
    }

    private static let cols: [String: String] = [
        "name": "name", "description": "description", "amount": "amount", "frequency": "frequency",
        "dayOfMonth": "day_of_month", "weekDay": "day_of_week", "autoPost": "auto_post", "color": "color",
        "type": "kind", "category": "category_id", "endDate": "end_date", "maxExecutions": "max_executions",
        "installmentTotal": "installment_total",
    ]

    static func update(_ db: Database, _ args: Args) throws {
        guard let id = args.idString else { throw I18nError("error.invalidArgs", [:], "updateScheduled requires an id") }
        var patch = args.patchObject
        if let n = patch["name"], !n.isNonEmptyTrimmedString { throw I18nError("error.required.templateName", [:], "Template name is required") }
        if patch.keys.contains("installmentTotal") {
            patch["installmentTotal"] = try parseInstallmentTotal(patch["installmentTotal"]).map { JSONValue.int($0) } ?? .null
        }
        var sets: [String] = []
        var bind: [DatabaseValueConvertible?] = []
        for (key, col) in cols where patch.keys.contains(key) {
            sets.append("\(col) = ?"); bind.append(patch[key]!.sqlBind)
        }
        if sets.isEmpty { return }
        sets.append("updated_at = datetime('now')")
        bind.append(id)
        try db.execute(sql: "UPDATE scheduled_templates SET \(sets.joined(separator: ", ")) WHERE id = ?", arguments: StatementArguments(bind))
    }

    static func delete(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String }
        try db.execute(sql: "DELETE FROM scheduled_templates WHERE id = ?", arguments: [try args.to(A.self).id])
    }

    static func addSplit(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let templateId: String; let accountId: String; let pct: Double? }
        let a = try args.to(A.self)
        let accountId = a.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        if accountId.isEmpty { throw I18nError("error.required.splitAccount", [:], "A split needs an account") }
        let sort = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM scheduled_splits WHERE template_id = ?", arguments: [a.templateId]) ?? 0
        let id = "\(a.templateId)-s\(sort)-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6).lowercased())"
        try db.execute(sql: "INSERT INTO scheduled_splits (id,template_id,account_id,amount_pct,amount_abs,category_id,description,sort_order) VALUES (?,?,?,?,NULL,NULL,NULL,?)",
                       arguments: [id, a.templateId, accountId, a.pct ?? 0, sort])
        try db.execute(sql: "UPDATE scheduled_templates SET splits_enabled = 1, updated_at = datetime('now') WHERE id = ?", arguments: [a.templateId])
    }

    static func updateSplit(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let templateId: String; let index: Int; let pct: Double }
        let a = try args.to(A.self)
        try db.execute(sql: """
            UPDATE scheduled_splits SET amount_pct = ?
             WHERE id = (SELECT id FROM scheduled_splits WHERE template_id = ? ORDER BY sort_order LIMIT 1 OFFSET ?)
            """, arguments: [a.pct, a.templateId, a.index])
    }

    static func removeSplit(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let templateId: String; let index: Int }
        let a = try args.to(A.self)
        try db.execute(sql: """
            DELETE FROM scheduled_splits
             WHERE id = (SELECT id FROM scheduled_splits WHERE template_id = ? ORDER BY sort_order LIMIT 1 OFFSET ?)
            """, arguments: [a.templateId, a.index])
        let n = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scheduled_splits WHERE template_id = ?", arguments: [a.templateId]) ?? 0
        if n == 0 {
            try db.execute(sql: "UPDATE scheduled_templates SET splits_enabled = 0, updated_at = datetime('now') WHERE id = ?", arguments: [a.templateId])
        }
    }
}
