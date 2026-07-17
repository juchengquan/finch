import Foundation
import GRDB

// Account-group + budget-group domains — symmetric CRUD over `account_groups` /
// `budget_groups` (ports of accountGroups/mutations.ts + budgets/mutations.ts's
// group handlers). createX appends at MAX(sort_order)+1; updateX patches
// name / color / sortOrder.

public enum AccountGroups {
    public static let handlers: [ActionName: Apply.Handler] = [
        .createAccountGroup: { try Groups.create($0, $1, table: "account_groups", prefix: "ag") },
        .updateAccountGroup: { try Groups.update($0, $1, table: "account_groups") },
        .deleteAccountGroup: { try Groups.delete($0, $1, table: "account_groups") },
    ]
}

public enum BudgetGroups {
    public static let handlers: [ActionName: Apply.Handler] = [
        .createBudgetGroup: { try Groups.create($0, $1, table: "budget_groups", prefix: "bgg") },
        .updateBudgetGroup: { try Groups.update($0, $1, table: "budget_groups") },
        .deleteBudgetGroup: { try Groups.delete($0, $1, table: "budget_groups") },
    ]
}

enum Groups {
    static func create(_ db: Database, _ args: Args, table: String, prefix: String) throws {
        struct A: Decodable { let id: String?; let ledgerId: String?; let name: String; let color: String? }
        let a = try args.to(A.self)
        let name = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw I18nError("error.required.groupName", [:], "Group name is required") }
        let ledgerId = a.ledgerId ?? "personal"
        let sortOrder = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM \(table) WHERE ledger_id = ?", arguments: [ledgerId]) ?? 0
        try db.execute(sql: "INSERT INTO \(table) (id,ledger_id,name,color,sort_order,created_at,updated_at) VALUES (?,?,?,?,?,datetime('now'),datetime('now'))",
                       arguments: [a.id ?? Entries.newId(prefix), ledgerId, name, a.color, sortOrder])
    }

    static func update(_ db: Database, _ args: Args, table: String) throws {
        guard case .string(let id)? = args.values["id"] else { throw I18nError("error.invalidArgs", [:], "update requires an id") }
        guard case .object(let patch)? = args.values["patch"] else { return }
        var sets: [String] = []
        var bind: [DatabaseValueConvertible?] = []
        if let nameV = patch["name"] {
            guard nameV.isNonEmptyTrimmedString, let name = nameV.asString else {
                throw I18nError("error.required.groupName", [:], "Group name is required")
            }
            sets.append("name = ?"); bind.append(name)
        }
        if let colorV = patch["color"] { sets.append("color = ?"); bind.append(colorV.sqlBind) }
        if let sortV = patch["sortOrder"] { sets.append("sort_order = ?"); bind.append(sortV.sqlBind) }
        if sets.isEmpty { return }
        sets.append("updated_at = datetime('now')")
        bind.append(id)
        try db.execute(sql: "UPDATE \(table) SET \(sets.joined(separator: ", ")) WHERE id = ?", arguments: StatementArguments(bind))
    }

    static func delete(_ db: Database, _ args: Args, table: String) throws {
        struct A: Decodable { let id: String }
        try db.execute(sql: "DELETE FROM \(table) WHERE id = ?", arguments: [try args.to(A.self).id])
    }
}
