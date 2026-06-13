import Foundation
import GRDB

/// Tags domain — port of lib/db/domain/tags/mutations.ts (createTag/updateTag/deleteTag).
public enum Tags {
    public static let handlers: [ActionName: Apply.Handler] = [
        .createTag: createTag,
        .updateTag: updateTag,
        .deleteTag: deleteTag,
    ]

    static func createTag(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String?; let ledgerId: String?; let name: String; let color: String? }
        let a = try args.to(A.self)
        let name = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw I18nError("error.required.tagName", [:], "Tag name is required") }
        try db.execute(sql: "INSERT INTO tags (id,ledger_id,name,color,created_at,updated_at) VALUES (?,?,?,?,datetime('now'),datetime('now'))",
                       arguments: [a.id ?? Entries.newId("tag"), a.ledgerId ?? "personal", name, a.color])
    }

    static func updateTag(_ db: Database, _ args: Args) throws {
        guard case .string(let id)? = args.values["id"] else { throw I18nError("error.invalidArgs", [:], "updateTag requires an id") }
        let patch: [String: JSONValue] = { if case .object(let p)? = args.values["patch"] { return p }; return [:] }()
        var sets: [String] = []
        var bind: [DatabaseValueConvertible?] = []
        if let v = patch["name"] {
            guard case .string(let s) = v, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw I18nError("error.required.tagName", [:], "Tag name is required")
            }
            sets.append("name = ?"); bind.append(s)
        }
        if patch.keys.contains("color") {
            if case .string(let s)? = patch["color"] { sets.append("color = ?"); bind.append(s) }
            else { sets.append("color = ?"); bind.append(nil as String?) }
        }
        if sets.isEmpty { return }
        sets.append("updated_at = datetime('now')")
        bind.append(id)
        try db.execute(sql: "UPDATE tags SET \(sets.joined(separator: ", ")) WHERE id = ?", arguments: StatementArguments(bind))
    }

    static func deleteTag(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String }
        try db.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: [try args.to(A.self).id])
    }
}
