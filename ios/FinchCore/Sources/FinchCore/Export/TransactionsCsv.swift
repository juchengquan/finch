import Foundation
import GRDB

/// Human-readable transactions export as CSV — a port of the web's
/// lib/db/queries/export.ts (`transactionExportRows` / `transactionsCsv`) and
/// lib/csv.ts (RFC 4180 builder). One row per account leg; opening entries
/// excluded; newest first. Optionally scoped to one ledger and/or one
/// `YYYY-MM` month (the Insights → Breakdown export).
public enum TxExport {
    /// Column headers, in order (matches the web COLUMNS labels).
    public static let columnLabels = [
        "Date", "Time", "Ledger", "Account", "Merchant", "Category",
        "Amount", "Currency", "Amount (base)", "Status", "Type", "Note", "Tags",
    ]

    /// RFC 4180: quote a field iff it contains a comma, quote, CR or LF; double
    /// internal quotes.
    static func escape(_ s: String) -> String {
        guard s.contains(where: { $0 == "\"" || $0 == "," || $0 == "\r" || $0 == "\n" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Stringify a number the way JS `String(n)` does — integral values lose the
    /// trailing ".0" (so "12", not "12.0"), matching the web CSV bytes.
    static func num(_ d: Double) -> String {
        if d.isFinite, d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
        return String(d)
    }

    /// The ordered string cells for each leg, ready to escape + join.
    public static func rows(_ db: Database, ledgerId: String?, month: String?) throws -> [[String]] {
        var conds = ["p.account_id IS NOT NULL", "e.kind != 'opening'"]
        var bind: [DatabaseValueConvertible?] = []
        if let ledgerId { conds.append("e.ledger_id = ?"); bind.append(ledgerId) }
        if let month { conds.append("e.date LIKE ?"); bind.append("\(month)%") }
        let sql = """
        SELECT e.date, e.time, e.ledger_id AS ledger,
               a.name AS account,
               COALESCE(p.memo, e.description) AS merchant,
               (SELECT cc.name
                  FROM postings cp
                  JOIN categories cc ON cc.id = cp.category_id
                 WHERE cp.entry_id = e.id AND cp.account_id IS NULL AND cc.kind != 'equity'
                 ORDER BY ABS(cp.amount_base) DESC LIMIT 1) AS category,
               p.amount, p.currency, p.amount_base AS amountBase, e.status, e.kind, e.notes AS note,
               (SELECT GROUP_CONCAT(tg.name, '; ')
                  FROM entry_tags et JOIN tags tg ON et.tag_id = tg.id
                 WHERE et.entry_id = e.id) AS tags
          FROM postings p
          JOIN entries e ON e.id = p.entry_id
          LEFT JOIN accounts a ON p.account_id = a.id
         WHERE \(conds.joined(separator: " AND "))
         ORDER BY e.date DESC, e.time DESC, e.created_at DESC
        """
        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(bind)).map { r in
            [
                r["date"] ?? "",
                r["time"] ?? "",
                r["ledger"] ?? "",
                r["account"] ?? "",
                r["merchant"] ?? "",
                r["category"] ?? "",
                num(r["amount"] ?? 0.0),
                r["currency"] ?? "",
                num(r["amountBase"] ?? 0.0),
                r["status"] ?? "",
                r["kind"] ?? "",
                r["note"] ?? "",
                r["tags"] ?? "",
            ]
        }
    }

    /// The full CSV document (CRLF-joined, trailing CRLF), Excel/Sheets friendly.
    public static func csv(_ db: Database, ledgerId: String?, month: String?) throws -> String {
        let header = columnLabels.map(escape).joined(separator: ",")
        let body = try rows(db, ledgerId: ledgerId, month: month).map { $0.map(escape).joined(separator: ",") }
        return ([header] + body).joined(separator: "\r\n") + "\r\n"
    }
}
