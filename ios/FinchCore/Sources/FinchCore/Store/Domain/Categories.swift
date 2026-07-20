import Foundation
import GRDB

/// Categories domain — port of lib/db/domain/categories/mutations.ts, including
/// the reparenting guards from _depth.ts: self-parent, move-under-own-descendant
/// (cycle prevention), and the ≤3-level depth cap.
public enum Categories {
    public static let handlers: [ActionName: Apply.Handler] = [
        .createCategory: create,
        .updateCategory: update,
        .deleteCategory: delete,
        .mergeCategory: merge,
        .mergeCategories: mergeMany,
        .copyCategories: copyCategories,
    ]

    static func create(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String?; let ledgerId: String?; let name: String; let type: String?; let icon: String?; let color: String?; let parentId: String? }
        let a = try args.to(A.self)
        let name = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw I18nError("error.required.categoryName", [:], "Category name is required") }
        let ledgerId = a.ledgerId ?? "personal"
        let type = a.type ?? "expense"
        if let pid = a.parentId { try assertCanBeParent(db, pid) }
        let sortOrder = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM categories WHERE ledger_id = ?", arguments: [ledgerId]) ?? 0
        try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,icon,color,sort_order,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,datetime('now'),datetime('now'))",
                       arguments: [a.id ?? Entries.newId("cat"), ledgerId, a.parentId, name, type, a.icon, a.color, sortOrder])
    }

    // NOTE: `sortOrder` is an iOS-only addition — the web's updateCategory patch
    // does NOT accept it (no category reorder on web). Deliberate divergence
    // (cf. the D7 "Force import" iOS-only override). Web still respects sort_order.
    private static let cols: [String: String] = ["name": "name", "type": "kind", "icon": "icon", "color": "color", "parentId": "parent_id", "sortOrder": "sort_order"]

    static func update(_ db: Database, _ args: Args) throws {
        guard case .string(let id)? = args.values["id"] else { throw I18nError("error.invalidArgs", [:], "updateCategory requires an id") }
        let patch: [String: JSONValue] = { if case .object(let p)? = args.values["patch"] { return p }; return [:] }()
        if let nameV = patch["name"], !nameV.isNonEmptyTrimmedString {
            throw I18nError("error.required.categoryName", [:], "Category name is required")
        }
        if case .string(let pid)? = patch["parentId"] {
            if pid == id { throw I18nError("error.category.selfParent", [:], "A category cannot be its own parent") }
            if try isInSubtreeOf(db, pid, id) {
                throw I18nError("error.category.underDescendant", [:], "A category cannot be moved under its own descendant")
            }
            try assertSubtreeFitsUnder(db, id, pid)
        }
        var sets: [String] = []
        var bind: [DatabaseValueConvertible?] = []
        for key in ["name", "type", "icon", "color", "parentId", "sortOrder"] where patch.keys.contains(key) {
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

    /// Combine `sourceId` into `targetId`: repoint every reference source holds
    /// (transaction legs incl. splits, scheduled templates + splits, budget id
    /// lists), re-parent source's children under target (top-level fallback past
    /// the 3-level cap), then delete source. One atomic transaction (Apply wraps).
    static func merge(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let sourceId: String; let targetId: String }
        let a = try args.to(A.self)
        try validateMerge(db, source: a.sourceId, target: a.targetId)
        try mergeOne(db, source: a.sourceId, target: a.targetId)
        try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [a.sourceId])
    }

    /// Combine many `sourceIds` into `targetId` in one transaction (Apply wraps).
    /// All sources are validated up-front, so a bad one aborts the whole set with
    /// nothing merged. Sources' children re-parent under target; sources deleted.
    static func mergeMany(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let sourceIds: [String]; let targetId: String }
        let a = try args.to(A.self)
        if a.sourceIds.isEmpty {
            throw I18nError("error.invalidArgs", [:], "mergeCategories requires at least one source")
        }
        for source in a.sourceIds { try validateMerge(db, source: source, target: a.targetId) }
        for source in a.sourceIds { try mergeOne(db, source: source, target: a.targetId) }
        for source in a.sourceIds {
            try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [source])
        }
    }

    /// Shared guards for a single source→target merge (self, existence, same-kind,
    /// not-into-own-descendant). Read-only — no writes.
    private static func validateMerge(_ db: Database, source: String, target: String) throws {
        if source == target {
            throw I18nError("error.category.mergeSelf", [:], "Cannot merge a category into itself")
        }
        guard let sKind = try String.fetchOne(db, sql: "SELECT kind FROM categories WHERE id = ?", arguments: [source]),
              let tKind = try String.fetchOne(db, sql: "SELECT kind FROM categories WHERE id = ?", arguments: [target]) else {
            throw I18nError("error.notFound.category", [:], "Category does not exist")
        }
        if sKind != tKind {
            throw I18nError("error.category.mergeKind", [:], "Categories must be the same type to merge")
        }
        if try isInSubtreeOf(db, target, source) {
            throw I18nError("error.category.mergeDescendant", [:], "Cannot merge a category into its own subcategory")
        }
    }

    /// Repoint every reference `source` holds onto `target` and re-parent source's
    /// children under target (top-level fallback past the 3-level cap). Does NOT
    /// validate or delete `source`. Runs inside the caller's transaction.
    private static func mergeOne(_ db: Database, source: String, target: String) throws {
        try db.execute(sql: "UPDATE postings SET category_id = ? WHERE category_id = ?", arguments: [target, source])
        try db.execute(sql: "UPDATE scheduled_templates SET category_id = ? WHERE category_id = ?", arguments: [target, source])
        // scheduled_splits.category_id is ON DELETE RESTRICT — repointing it here is
        // what lets the caller's later DELETE of `source` succeed.
        try db.execute(sql: "UPDATE scheduled_splits SET category_id = ? WHERE category_id = ?", arguments: [target, source])
        for row in try Row.fetchAll(db, sql: "SELECT id, category_ids FROM budgets WHERE category_ids LIKE ?", arguments: ["%\(source)%"]) {
            guard let raw = row["category_ids"] as String?, let data = raw.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode([String].self, from: data), parsed.contains(source) else { continue }
            var seen = Set<String>()
            let rewritten = parsed.map { $0 == source ? target : $0 }.filter { seen.insert($0).inserted }
            let json = String(data: try JSONEncoder().encode(rewritten), encoding: .utf8)
            try db.execute(sql: "UPDATE budgets SET category_ids = ?, updated_at = datetime('now') WHERE id = ?",
                           arguments: [json, row["id"] as String])
        }
        let children = try String.fetchAll(db, sql: "SELECT id FROM categories WHERE parent_id = ?", arguments: [source])
        for child in children {
            let fits = try categoryDepth(db, target) + subtreeDepth(db, child) <= 3
            try db.execute(sql: "UPDATE categories SET parent_id = ?, updated_at = datetime('now') WHERE id = ?",
                           arguments: [fits ? target : nil, child])
        }
    }

    /// Additively copy user categories from one ledger to another, preserving the
    /// tree and dedup by (kind, target-parent, name). System rows are skipped.
    /// `ids` (optional) restricts to those categories plus their ancestors.
    static func copyCategories(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let fromLedgerId: String; let toLedgerId: String; let ids: [String]? }
        let a = try args.to(A.self)
        // Source user categories (skip system equity rows).
        var byId: [String: Row] = [:]
        for r in try Row.fetchAll(db, sql: "SELECT id, parent_id, name, kind, icon, color FROM categories WHERE ledger_id = ? AND system IS NULL", arguments: [a.fromLedgerId]) {
            byId[r["id"] as String] = r
        }
        // Wanted set: all, or the ids + their ancestors.
        var wanted = Set(byId.keys)
        if let ids = a.ids {
            wanted = []
            for start in ids {
                var cur: String? = start
                while let c = cur, byId[c] != nil, wanted.insert(c).inserted { cur = byId[c]?["parent_id"] as String? }
            }
        }
        // Target dedup map: (kind|parentTargetId|lowerName) -> target id, over ALL target rows.
        var dedup: [String: String] = [:]
        for r in try Row.fetchAll(db, sql: "SELECT id, parent_id, name, kind FROM categories WHERE ledger_id = ?", arguments: [a.toLedgerId]) {
            let key = "\(r["kind"] as String)|\(r["parent_id"] as String? ?? "")|\((r["name"] as String).lowercased())"
            dedup[key] = r["id"] as String
        }
        var nextOrder = (try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM categories WHERE ledger_id = ?", arguments: [a.toLedgerId])) ?? 0
        var idMap: [String: String] = [:]   // source id -> target id (existing or new)
        // Process parents before children.
        var pending = wanted
        while !pending.isEmpty {
            let ready = pending.filter { id in
                let p = byId[id]?["parent_id"] as String?
                return p == nil || !wanted.contains(p!) || idMap[p!] != nil
            }
            if ready.isEmpty { break }   // safety against cycles (schema prevents them)
            for src in ready.sorted() {
                let r = byId[src]!
                let srcParent = r["parent_id"] as String?
                let targetParent: String? = (srcParent != nil && wanted.contains(srcParent!)) ? idMap[srcParent!] : nil
                let name = (r["name"] as String)
                let kind = r["kind"] as String
                let key = "\(kind)|\(targetParent ?? "")|\(name.lowercased())"
                if let existing = dedup[key] { idMap[src] = existing }
                else {
                    let newId = Entries.newId("cat")
                    try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,icon,color,sort_order,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,datetime('now'),datetime('now'))",
                                   arguments: [newId, a.toLedgerId, targetParent, name, kind, r["icon"] as String?, r["color"] as String?, nextOrder])
                    nextOrder += 1
                    idMap[src] = newId; dedup[key] = newId
                }
                pending.remove(src)
            }
        }
    }

    // MARK: depth / cycle guards (port of lib/db/domain/categories/_depth.ts)

    /// Hops from `id` up to the root; the 10-hop bound is the web's cycle backstop.
    private static func categoryDepth(_ db: Database, _ id: String) throws -> Int {
        var cur: String? = id, depth = 0
        for _ in 0..<10 {
            guard let c = cur else { break }
            guard let row = try Row.fetchOne(db, sql: "SELECT parent_id FROM categories WHERE id = ?", arguments: [c]) else {
                throw I18nError("error.notFound.category", [:], "Category does not exist")
            }
            depth += 1
            cur = row["parent_id"] as String?
        }
        return depth
    }

    /// Levels in the subtree rooted at `id` (1 = leaf).
    private static func subtreeDepth(_ db: Database, _ id: String) throws -> Int {
        var frontier = [id], depth = 1
        for _ in 0..<10 {
            if frontier.isEmpty { break }
            let placeholders = frontier.map { _ in "?" }.joined(separator: ",")
            let rows = try String.fetchAll(db, sql: "SELECT id FROM categories WHERE parent_id IN (\(placeholders))",
                                           arguments: StatementArguments(frontier))
            if rows.isEmpty { break }
            depth += 1
            frontier = rows
        }
        return depth
    }

    /// True if `candidateId` is `ancestorId` or any of its descendants — the
    /// move-under-own-descendant cycle guard.
    private static func isInSubtreeOf(_ db: Database, _ candidateId: String, _ ancestorId: String) throws -> Bool {
        var cur: String? = candidateId
        for _ in 0..<10 {
            guard let c = cur else { break }
            if c == ancestorId { return true }
            guard let row = try Row.fetchOne(db, sql: "SELECT parent_id FROM categories WHERE id = ?", arguments: [c]) else { return false }
            cur = row["parent_id"] as String?
        }
        return false
    }

    private static func assertCanBeParent(_ db: Database, _ parentId: String) throws {
        if try categoryDepth(db, parentId) >= 3 {
            throw I18nError("error.category.depthCap", [:], "Categories nest at most three levels deep")
        }
    }

    private static func assertSubtreeFitsUnder(_ db: Database, _ movingId: String, _ newParentId: String) throws {
        if try categoryDepth(db, newParentId) + subtreeDepth(db, movingId) > 3 {
            throw I18nError("error.category.depthCap", [:], "Categories nest at most three levels deep")
        }
    }
}
