import Foundation
import GRDB

/// The id lists a budget filters on — `category_ids`, `tag_ids`, `counterparty_ids`,
/// `account_ids`, each a JSON array of ids.
enum BudgetFilters {
    /// Rewrite `source` to `target` in every budget's `column` list, keeping each id
    /// once. A merge calls it before deleting `source`: a budget still filtering on
    /// the deleted id matched nothing, so "Groceries at Whole Foods" read 0 spent
    /// after Whole Foods was merged into "Whole Foods Market".
    static func repoint(_ db: Database, column: String, source: String, target: String) throws {
        precondition(["category_ids", "tag_ids", "counterparty_ids", "account_ids"].contains(column))
        for row in try Row.fetchAll(db, sql: "SELECT id, \(column) AS ids FROM budgets WHERE \(column) LIKE ?",
                                    arguments: ["%\(source)%"]) {
            guard let raw = row["ids"] as String?, let data = raw.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode([String].self, from: data), parsed.contains(source) else { continue }
            var seen = Set<String>()
            let rewritten = parsed.map { $0 == source ? target : $0 }.filter { seen.insert($0).inserted }
            let json = String(data: try JSONEncoder().encode(rewritten), encoding: .utf8)
            try db.execute(sql: "UPDATE budgets SET \(column) = ?, updated_at = datetime('now') WHERE id = ?",
                           arguments: [json, row["id"] as String])
        }
    }
}
