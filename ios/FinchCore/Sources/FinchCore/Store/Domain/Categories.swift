import Foundation
import GRDB

/// Categories domain — port of lib/db/domain/categories/mutations.ts, including
/// the reparenting guards from _depth.ts: self-parent, move-under-own-descendant
/// (cycle prevention), and the depth cap — see `maxDepth`, which is 5 natively
/// while the web still enforces 3.
public enum Categories {
    public static let handlers: [ActionName: Apply.Handler] = [
        .createCategory: create,
        .updateCategory: update,
        .deleteCategory: delete,
        .mergeCategory: merge,
        .mergeCategories: mergeMany,
        .copyCategories: copyCategories,
        .setCategoryOrder: setOrder,
    ]

    /// Apply a whole drag's worth of `parent_id` / `sort_order` changes in ONE action.
    ///
    /// **This exists for cost, not convenience.** `CategoryReorder.reorder` renumbers
    /// the entire destination sibling group, so a single drop yields one move per
    /// member — and routing each through `updateCategory` meant one `store.apply` per
    /// move. Every one of those re-reads the whole active ledger and fires the full
    /// write side-effect set: Spotlight re-index, notification re-plan, widget
    /// snapshot + timeline reload, auto-backup, CloudKit outbox. Dropping inside a
    /// group of eight paid all of that eight times, which is what made the settle
    /// after a drag crawl on device. Budgets already had this shape
    /// (`setBudgetOrder`); Categories was the odd one out.
    ///
    /// Guards are NOT relaxed for being in a batch — each move re-runs the same
    /// self-parent, under-own-descendant and depth-cap checks `update` applies, and
    /// the first failure throws, rolling the whole action back. A drag is one
    /// intention; it should land completely or not at all.
    static func setOrder(_ db: Database, _ args: Args) throws {
        struct Move: Decodable { let id: String; let parentId: String?; let sortOrder: Int }
        struct A: Decodable { let moves: [Move] }
        for move in try args.to(A.self).moves {
            if let pid = move.parentId {
                if pid == move.id {
                    throw I18nError("error.category.selfParent", [:], "A category cannot be its own parent")
                }
                if try isInSubtreeOf(db, pid, move.id) {
                    throw I18nError("error.category.underDescendant", [:],
                                    "A category cannot be moved under its own descendant")
                }
                try assertSubtreeFitsUnder(db, move.id, pid)
            }
            try db.execute(
                sql: "UPDATE categories SET parent_id = ?, sort_order = ?, updated_at = datetime('now') WHERE id = ?",
                arguments: [move.parentId, move.sortOrder, move.id])
        }
    }

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
    /// the depth cap), then delete source. One atomic transaction (Apply wraps).
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
    /// children under target (top-level fallback past the depth cap). Does NOT
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
            let fits = try categoryDepth(db, target) + subtreeDepth(db, child) <= maxDepth
            try db.execute(sql: "UPDATE categories SET parent_id = ?, updated_at = datetime('now') WHERE id = ?",
                           arguments: [fits ? target : nil, child])
        }
    }

    /// Additively copy user categories from one ledger to another, preserving the
    /// tree and dedup by (kind, target-parent, name). System rows are skipped.
    /// `ids` (optional) restricts to those categories plus their ancestors.
    static func copyCategories(_ db: Database, _ args: Args) throws {
        _ = try copyCategoriesReturningCount(db, args)
    }

    /// Like `copyCategories`, returning how many categories were actually
    /// INSERTED. Copies dedup against the target (an existing match is reused,
    /// not duplicated), so the count is what the caller needs to say "N added"
    /// rather than a bare "done" that hides a no-op.
    static func copyCategoriesReturningCount(_ db: Database, _ args: Args) throws -> Int {
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
        var added = 0                       // NEW inserts only — reused matches don't count
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
                    added += 1
                }
                pending.remove(src)
            }
        }
        return added
    }

    // MARK: depth / cycle guards (port of lib/db/domain/categories/_depth.ts)

    /// How deep categories may nest. **The web still enforces 3**, so a tree deeper
    /// than that is native-only and the web cannot represent it — a deliberate
    /// divergence, like `sortOrder` on `updateCategory` just above.
    ///
    /// 5 rather than "unlimited" on purpose. A finite limit is what lets every walk
    /// below stay bounded, keeps "too deep" a thing the engine can actually say (so
    /// a malformed import is rejected instead of producing a 500-deep chain), and
    /// keeps `merge`'s promote-the-children fallback meaningful. It is also already
    /// far past use: Home → Utilities → Energy → Gas → Standing charge is 5.
    public static let maxDepth = 4 + 1

    /// Step limit for the tree walks below. **Derived from `maxDepth`, never written
    /// as a literal.** These bounds exist to stop a walk spinning forever if the data
    /// already contains a cycle — a different job from the depth rule, which is why
    /// they used to be a bare `10` while the cap was `3`. Once the two numbers are
    /// close, a hardcoded bound silently becomes too short: a walk that stops at
    /// exactly `maxDepth` steps never reaches the root of the deepest LEGAL tree and
    /// returns a wrong depth, or misses a cycle. Always stay ahead of the rule.
    private static let walkLimit = maxDepth + 2

    /// Hops from `id` up to the root; `walkLimit` is the cycle backstop.
    private static func categoryDepth(_ db: Database, _ id: String) throws -> Int {
        var cur: String? = id, depth = 0
        for _ in 0..<walkLimit {
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
        for _ in 0..<walkLimit {
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
        for _ in 0..<walkLimit {
            guard let c = cur else { break }
            if c == ancestorId { return true }
            guard let row = try Row.fetchOne(db, sql: "SELECT parent_id FROM categories WHERE id = ?", arguments: [c]) else { return false }
            cur = row["parent_id"] as String?
        }
        return false
    }

    private static func assertCanBeParent(_ db: Database, _ parentId: String) throws {
        if try categoryDepth(db, parentId) >= maxDepth {
            throw I18nError("error.category.depthCap", [:], "Categories can't be nested any deeper")
        }
    }

    private static func assertSubtreeFitsUnder(_ db: Database, _ movingId: String, _ newParentId: String) throws {
        if try categoryDepth(db, newParentId) + subtreeDepth(db, movingId) > maxDepth {
            throw I18nError("error.category.depthCap", [:], "Categories can't be nested any deeper")
        }
    }
}
