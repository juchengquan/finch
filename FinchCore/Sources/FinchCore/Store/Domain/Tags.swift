import Foundation
import GRDB

/// Tags domain — port of lib/db/domain/tags/mutations.ts (createTag/updateTag/deleteTag).
public enum Tags {
    public static let handlers: [ActionName: Apply.Handler] = [
        .createTag: createTag,
        .updateTag: updateTag,
        .deleteTag: deleteTag,
        .mergeTag: mergeTag,
        .mergeTags: mergeTags,
        .copyTags: copyTags,
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

    /// Additively copy tags from one ledger to another, dedup by name
    /// (case-insensitive). `ids` (optional) restricts to those source tags.
    static func copyTags(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let fromLedgerId: String; let toLedgerId: String; let ids: [String]? }
        let a = try args.to(A.self)
        let want = a.ids.map(Set.init)
        let existing = Set(try String.fetchAll(db, sql: "SELECT lower(name) FROM tags WHERE ledger_id = ?", arguments: [a.toLedgerId]))
        for row in try Row.fetchAll(db, sql: "SELECT id, name, color FROM tags WHERE ledger_id = ?", arguments: [a.fromLedgerId]) {
            let id = row["id"] as String
            guard want?.contains(id) ?? true else { continue }
            let name = (row["name"] as String).trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty || existing.contains(name.lowercased()) { continue }
            try db.execute(sql: "INSERT INTO tags (id,ledger_id,name,color,created_at,updated_at) VALUES (?,?,?,?,datetime('now'),datetime('now'))",
                           arguments: [Entries.newId("tag"), a.toLedgerId, name, row["color"] as String?])
        }
    }

    // MARK: merge

    /// Combine `sourceId` into `targetId`: repoint the entry_tags join (dedup on
    /// the composite PK) and any rule actions, then delete the source tag (its
    /// leftover join rows cascade away). One atomic transaction (Apply wraps).
    static func mergeTag(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let sourceId: String; let targetId: String }
        let a = try args.to(A.self)
        try validateMerge(db, source: a.sourceId, target: a.targetId)
        try mergeOne(db, source: a.sourceId, target: a.targetId)
        try db.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: [a.sourceId])
    }

    /// Combine many `sourceIds` into `targetId` in one transaction. All sources
    /// are validated up-front, so a bad one aborts the whole set with nothing merged.
    static func mergeTags(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let sourceIds: [String]; let targetId: String }
        let a = try args.to(A.self)
        if a.sourceIds.isEmpty {
            throw I18nError("error.invalidArgs", [:], "mergeTags requires at least one source")
        }
        for source in a.sourceIds { try validateMerge(db, source: source, target: a.targetId) }
        for source in a.sourceIds { try mergeOne(db, source: source, target: a.targetId) }
        for source in a.sourceIds {
            try db.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: [source])
        }
    }

    /// Guards for a single source→target merge (self, existence). Read-only.
    private static func validateMerge(_ db: Database, source: String, target: String) throws {
        if source == target {
            throw I18nError("error.tag.mergeSelf", [:], "Cannot merge a tag into itself")
        }
        for id in [source, target] where try Int.fetchOne(db, sql: "SELECT 1 FROM tags WHERE id = ?", arguments: [id]) == nil {
            throw I18nError("error.notFound.tag", [:], "Tag does not exist")
        }
    }

    /// Repoint the join + rule actions from `source` to `target`. No validation,
    /// no delete. Runs inside the caller's transaction.
    private static func mergeOne(_ db: Database, source: String, target: String) throws {
        // 1) Repoint the join, dedup via the composite PK (entry with both → target once).
        try db.execute(sql: """
            INSERT OR IGNORE INTO entry_tags (entry_id, tag_id)
            SELECT entry_id, ? FROM entry_tags WHERE tag_id = ?
            """, arguments: [target, source])
        // (Source join rows remain; the caller's DELETE of the tag cascades them away.)

        // 2) Repoint rule actions that add/remove the source tag.
        for row in try Row.fetchAll(db, sql: "SELECT id, actions FROM rules WHERE actions LIKE ?", arguments: ["%\(source)%"]) {
            guard let raw = row["actions"] as String?, let data = raw.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
            var changed = false
            var seenTagActions = Set<String>()   // "type|tagId" — drop duplicate add/remove of the same tag
            var rewritten: [[String: Any]] = []
            for var act in parsed {
                let type = act["type"] as? String
                if type == "add_tag" || type == "remove_tag", let tid = act["tagId"] as? String {
                    if tid == source { act["tagId"] = target; changed = true }
                    let key = "\(type ?? "")|\(act["tagId"] as? String ?? "")"
                    if !seenTagActions.insert(key).inserted { changed = true; continue }   // duplicate — drop
                }
                rewritten.append(act)
            }
            if changed,
               let out = try? JSONSerialization.data(withJSONObject: rewritten),
               let json = String(data: out, encoding: .utf8),
               let id = row["id"] as String? {
                try db.execute(sql: "UPDATE rules SET actions = ?, updated_at = datetime('now') WHERE id = ?", arguments: [json, id])
            }
        }
    }
}
