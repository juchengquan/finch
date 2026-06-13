import Foundation
import GRDB

// Account-group + budget-group domains — symmetric CRUD over `account_groups` /
// `budget_groups` (ports of accountGroups/mutations.ts + budgets/mutations.ts's
// group handlers). createX appends at MAX(sort_order)+1; updateX is name-only.

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
        struct A: Decodable { let id: String?; let ledgerId: String?; let name: String }
        let a = try args.to(A.self)
        let name = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw I18nError("error.required.groupName", [:], "Group name is required") }
        let ledgerId = a.ledgerId ?? "personal"
        let sortOrder = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM \(table) WHERE ledger_id = ?", arguments: [ledgerId]) ?? 0
        try db.execute(sql: "INSERT INTO \(table) (id,ledger_id,name,sort_order,created_at,updated_at) VALUES (?,?,?,?,datetime('now'),datetime('now'))",
                       arguments: [a.id ?? Entries.newId(prefix), ledgerId, name, sortOrder])
    }

    static func update(_ db: Database, _ args: Args, table: String) throws {
        guard case .string(let id)? = args.values["id"] else { throw I18nError("error.invalidArgs", [:], "update requires an id") }
        guard case .object(let patch)? = args.values["patch"], let nameV = patch["name"] else { return }   // name-only
        guard nameV.isNonEmptyTrimmedString, let name = nameV.asString else {
            throw I18nError("error.required.groupName", [:], "Group name is required")
        }
        try db.execute(sql: "UPDATE \(table) SET name = ?, updated_at = datetime('now') WHERE id = ?", arguments: [name, id])
    }

    static func delete(_ db: Database, _ args: Args, table: String) throws {
        struct A: Decodable { let id: String }
        try db.execute(sql: "DELETE FROM \(table) WHERE id = ?", arguments: [try args.to(A.self).id])
    }
}
