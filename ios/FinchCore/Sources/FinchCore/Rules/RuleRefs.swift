import Foundation
import GRDB

/// What a rule may still write once the things it names have moved on.
///
/// A rule stores ids — the category it sets, the merchant, the tags it adds, the
/// categories of a split — and nothing stops those rows from being deleted or merged
/// away afterwards. The engine used to write such an id straight into a posting or
/// entry, so the FOREIGN KEY check refused the whole write: after merging Groceries
/// into Food, adding "Whole Foods" by any route (sheet, Siri, Watch, CSV) failed.
/// Mirrors the web's `pruneRulePatch` (`frontend/lib/db/core/rule-refs.ts`).
public enum RuleRefs {
    /// The kinds a rule may give an entry, and the shape each one needs. The same set
    /// `postEntry` lets a rule choose between; a rule saying "transfer" or
    /// "adjustment" describes an entry with a different number of legs, which no
    /// rule can conjure, and writing it anyway failed the ledger audit on every
    /// backup taken afterwards.
    public static let ruledKinds: Set<String> = ["income", "expense", "refund"]

    /// Drop from `patch` every id that no longer names a row this ledger can use:
    /// a category or tag of this ledger, a merchant (merchants are global). A split
    /// with any dangling category is dropped whole — re-dividing it would invent a
    /// proportion the rule never asked for. The rule's other actions still apply.
    static func prune(_ db: Database, _ patch: inout RulePatch, ledgerId: String) throws {
        func categoryExists(_ id: String) throws -> Bool {
            try Bool.fetchOne(db, sql: "SELECT 1 FROM categories WHERE id = ? AND ledger_id = ?",
                              arguments: [id, ledgerId]) ?? false
        }
        if case .set(let id?) = patch.categoryId, try !categoryExists(id) { patch.categoryId = .keep }
        if case .set(let id?) = patch.counterpartyId,
           try !(Bool.fetchOne(db, sql: "SELECT 1 FROM counterparties WHERE id = ?", arguments: [id]) ?? false) {
            patch.counterpartyId = .keep
        }
        if let splits = patch.splits,
           try splits.contains(where: { s in try s.categoryId.map { try !categoryExists($0) } ?? false }) {
            patch.splits = nil
        }
        if let add = patch.tagIdsAdd {
            patch.tagIdsAdd = try add.filter {
                try Bool.fetchOne(db, sql: "SELECT 1 FROM tags WHERE id = ? AND ledger_id = ?",
                                  arguments: [$0, ledgerId]) ?? false
            }
        }
    }

    /// Whether a rule may re-kind an existing income/expense/refund entry to `kind`.
    /// A refund puts money back, so every account leg must be positive — the same
    /// rule the audit's kind-shape check holds it to.
    static func canRekind(_ db: Database, entryId: String, to kind: String) throws -> Bool {
        guard ruledKinds.contains(kind) else { return false }
        guard kind == "refund" else { return true }
        let outflows = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM postings WHERE entry_id = ? AND account_id IS NOT NULL AND amount <= 0
            """, arguments: [entryId]) ?? 0
        return outflows == 0
    }

    /// Repoint every reference a rule holds to `source` onto `target`: the actions
    /// (`set_category` / `set_counterparty` / a split's categories) and the
    /// conditions (`category_id` / `counterparty_id` leaves, `is` and `in`). Used
    /// by the category and merchant merges, so a rule keeps doing what it did.
    /// `actionKey` is the action field ("categoryId"), `field` the condition field
    /// ("category_id"). Runs inside the caller's transaction.
    static func repoint(_ db: Database, actionKey: String, field: String, source: String, target: String) throws {
        let rows = try Row.fetchAll(db, sql: "SELECT id, condition, actions FROM rules WHERE condition LIKE ? OR actions LIKE ?",
                                    arguments: ["%\(source)%", "%\(source)%"])
        for row in rows {
            let id: String = row["id"]
            var changed = false
            func swap(_ v: Any) -> Any {
                if let s = v as? String, s == source { changed = true; return target }
                if let arr = v as? [Any] {
                    var seen = Set<String>()
                    return arr.map(swap).filter { ($0 as? String).map { seen.insert($0).inserted } ?? true }
                }
                return v
            }
            func walkCondition(_ v: Any) -> Any {
                guard var o = v as? [String: Any] else { return v }
                for key in ["all", "any"] { if let arr = o[key] as? [Any] { o[key] = arr.map(walkCondition) } }
                if let n = o["not"] { o["not"] = walkCondition(n) }
                if o["field"] as? String == field, let value = o["value"] { o["value"] = swap(value) }
                return o
            }
            func walkAction(_ v: Any) -> Any {
                guard var o = v as? [String: Any] else { return v }
                if let value = o[actionKey] { o[actionKey] = swap(value) }
                if let splits = o["splits"] as? [Any] { o["splits"] = splits.map(walkAction) }
                return o
            }
            let condition = (row["condition"] as String?).flatMap(json).map(walkCondition)
            let actions = (row["actions"] as String?).flatMap(json).map { ($0 as? [Any])?.map(walkAction) ?? $0 }
            guard changed else { continue }
            try db.execute(sql: "UPDATE rules SET condition = ?, actions = ?, updated_at = datetime('now') WHERE id = ?",
                           arguments: [condition.flatMap(text) ?? row["condition"], actions.flatMap(text) ?? row["actions"], id])
        }
    }

    private static func json(_ s: String) -> Any? {
        s.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0, options: [.fragmentsAllowed]) }
    }
    private static func text(_ v: Any) -> String? {
        (try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed, .sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) }
    }
}
