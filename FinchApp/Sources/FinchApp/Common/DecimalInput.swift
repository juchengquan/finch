import Foundation

/// Locale-aware parse for decimal text fields. `.decimalPad` shows the user's
/// locale separator (e.g. `,` in much of Europe), but `Double("0,89")` is nil —
/// so comma-decimal users couldn't enter amounts/rates/shares. Parse with the
/// current locale first, then fall back to a plain `.` decimal.
enum DecimalInput {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .current
        return f
    }()

    static func parse(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        if let n = formatter.number(from: t) { return n.doubleValue }
        return Double(t)   // fallback: plain "." decimal
    }
}
