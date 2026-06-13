import Foundation
import GRDB

/// Rules domain — port of lib/db/domain/rules/mutations.ts (CRUD).
/// DEFERRED: backfillRule (applies a rule to existing transactions via the
/// rules engine `applyRules`, which is itself deferred).
public enum Rules {
    public static let handlers: [ActionName: Apply.Handler] = [
        .createRule: create,
        .updateRule: update,
        .deleteRule: delete,
    ]

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
