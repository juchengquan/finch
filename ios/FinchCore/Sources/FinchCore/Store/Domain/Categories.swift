import Foundation
import GRDB

/// Categories domain — port of lib/db/domain/categories/mutations.ts.
/// DEFERRED: the ≤3-level depth validation (`assertCanBeParent` /
/// `assertSubtreeFitsUnder` / descendant checks) — only the self-parent guard
/// is enforced here; flat-category fixtures don't exercise the rest.
public enum Categories {
    public static let handlers: [ActionName: Apply.Handler] = [
        .createCategory: create,
        .updateCategory: update,
        .deleteCategory: delete,
    ]

    static func create(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String?; let ledgerId: String?; let name: String; let type: String?; let icon: String?; let color: String?; let parentId: String? }
        let a = try args.to(A.self)
        let name = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw I18nError("error.required.categoryName", [:], "Category name is required") }
        let ledgerId = a.ledgerId ?? "personal"
        let type = a.type ?? "expense"
        let sortOrder = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM categories WHERE ledger_id = ?", arguments: [ledgerId]) ?? 0
        try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,icon,color,sort_order,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,datetime('now'),datetime('now'))",
                       arguments: [a.id ?? Entries.newId("cat"), ledgerId, a.parentId, name, type, a.icon, a.color, sortOrder])
    }

    private static let cols: [String: String] = ["name": "name", "type": "kind", "icon": "icon", "color": "color", "parentId": "parent_id"]

    static func update(_ db: Database, _ args: Args) throws {
        guard case .string(let id)? = args.values["id"] else { throw I18nError("error.invalidArgs", [:], "updateCategory requires an id") }
        let patch: [String: JSONValue] = { if case .object(let p)? = args.values["patch"] { return p }; return [:] }()
        if let nameV = patch["name"], !nameV.isNonEmptyTrimmedString {
            throw I18nError("error.required.categoryName", [:], "Category name is required")
        }
        if case .string(let pid)? = patch["parentId"], pid == id {
            throw I18nError("error.category.selfParent", [:], "A category cannot be its own parent")
        }
        var sets: [String] = []
        var bind: [DatabaseValueConvertible?] = []
        for key in ["name", "type", "icon", "color", "parentId"] where patch.keys.contains(key) {
            sets.append("\(cols[key]!) = ?")
            bind.append(patch[key]!.sqlBind)
        }
        if sets.isEmpty { return }
        sets.append("updated_at = datetime('now')")
        bind.append(id)
        try db.execute(sql: "UPDATE categories SET \(sets.joined(separator: ", ")) WHERE id = ?", arguments: StatementArguments(bind))
    }

    static func delete(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String }
        try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [try args.to(A.self).id])
    }
}
