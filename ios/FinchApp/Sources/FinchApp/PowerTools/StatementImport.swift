import Foundation
import FinchCore

/// A parsed bank-statement line.
public struct StatementRow: Equatable, Identifiable, Sendable {
    public let id = UUID()
    public let date: String          // normalized YYYY-MM-DD
    public let description: String
    public let amount: Double         // signed (negative = spend)
}

/// Phase 4 — pure CSV statement parsing + matching (the tested core; the
/// .fileImporter UI is a thin shell). Handles a header row naming
/// date/description/amount (any order, case-insensitive); falls back to
/// positional [date, description, amount]. Amounts tolerate $ and thousands
/// commas; dates accept YYYY-MM-DD or MM/DD/YYYY.
public enum StatementCSV {
    public static func parse(_ text: String) -> [StatementRow] {
        var lines = text.split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return [] }

        // Column indices (default positional).
        var di = 0, ci = 1, ai = 2
        let firstCols = splitCSVLine(lines[0]).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        let looksLikeHeader = firstCols.contains { ["date", "description", "amount", "memo", "payee"].contains($0) }
        if looksLikeHeader {
            if let i = firstCols.firstIndex(where: { $0 == "date" }) { di = i }
            if let i = firstCols.firstIndex(where: { $0 == "description" || $0 == "memo" || $0 == "payee" }) { ci = i }
            if let i = firstCols.firstIndex(where: { $0 == "amount" }) { ai = i }
            lines.removeFirst()
        }

        return lines.compactMap { line in
            let cols = splitCSVLine(line)
            guard cols.count > max(di, ci, ai),
                  let date = normalizeDate(cols[di]),
                  let amount = parseAmount(cols[ai]) else { return nil }
            return StatementRow(date: date, description: cols[ci].trimmingCharacters(in: .whitespaces), amount: amount)
        }
    }

    /// Minimal CSV field split honoring double-quoted fields.
    static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []; var cur = ""; var inQuotes = false
        for ch in line {
            if ch == "\"" { inQuotes.toggle() }
            else if ch == "," && !inQuotes { fields.append(cur); cur = "" }
            else { cur.append(ch) }
        }
        fields.append(cur)
        return fields.map { $0.replacingOccurrences(of: "\"", with: "") }
    }

    static func parseAmount(_ s: String) -> Double? {
        let cleaned = s.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        return Double(cleaned)
    }

    static func normalizeDate(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.count == 10, t[t.index(t.startIndex, offsetBy: 4)] == "-" { return t }   // YYYY-MM-DD
        let parts = t.split(separator: "/")                                            // MM/DD/YYYY
        if parts.count == 3, let m = Int(parts[0]), let d = Int(parts[1]), let y = Int(parts[2]) {
            return String(format: "%04d-%02d-%02d", y, m, d)
        }
        return nil
    }
}

/// Matches statement rows against existing transactions for an account: same
/// amount (±1¢) within ±`dayWindow` days, not already cleared. Pure.
public enum StatementMatcher {
    public struct Result: Equatable { public let row: StatementRow; public let matchedTxId: String? }

    public static func match(_ rows: [StatementRow], txns: [Tx], accountId: String, dayWindow: Int = 3) -> [Result] {
        let candidates = txns.filter { $0.account == accountId }
        return rows.map { row in
            let m = candidates.first { tx in
                abs((tx.nativeAmount ?? tx.amount) - row.amount) < 0.01 && dayDiff(tx.date, row.date) <= dayWindow
            }
            return Result(row: row, matchedTxId: m?.id)
        }
    }

    private static let fmt = AppDate.isoDay
    static func dayDiff(_ a: String, _ b: String) -> Int {
        guard let da = fmt.date(from: String(a.prefix(10))), let db = fmt.date(from: b) else { return .max }
        return Int(abs(da.timeIntervalSince(db)) / 86_400)
    }
}
