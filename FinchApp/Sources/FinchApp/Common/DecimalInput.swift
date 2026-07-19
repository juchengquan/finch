import SwiftUI

/// Locale-aware parse + live input filtering for numeric text fields.
enum DecimalInput {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .current
        return f
    }()

    /// Parse decimal text to a Double. The input carries at most one separator (the
    /// filter guarantees it), so a lone comma is normalized to a dot first — this
    /// makes comma-decimal users parse correctly regardless of device locale. Falls
    /// back to the locale formatter last (for any grouping-formatted seed strings).
    static func parse(_ s: String) -> Double? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        if !t.contains("."), t.contains(",") {
            t = t.replacingOccurrences(of: ",", with: ".")
        }
        if let d = Double(t) { return d }
        return formatter.number(from: t)?.doubleValue
    }

    /// Strip a live text-field string to a valid numeric string. Keeps an optional
    /// leading "-" and ASCII digits; for decimals, keeps the LAST separator ("." or
    /// ",") as the decimal point and drops earlier separators (so pasted grouping
    /// like "1,234.50" collapses to "1234.50", while a typed "1,5" stays "1,5").
    /// Everything else is removed. Does NOT reformat; intermediate "-"/"." survive.
    static func filter(_ s: String, allowsDecimal: Bool) -> String {
        let negative = s.first == "-"
        var kept = s.filter { ($0.isASCII && $0.isNumber) || (allowsDecimal && ($0 == "." || $0 == ",")) }
        if allowsDecimal, let lastSep = kept.lastIndex(where: { $0 == "." || $0 == "," }) {
            let intPart = kept[..<lastSep].filter { $0 != "." && $0 != "," }
            let fracPart = kept[kept.index(after: lastSep)...]
            kept = intPart + String(kept[lastSep]) + fracPart
        }
        return (negative ? "-" : "") + kept
    }
}

extension Binding where Value == String {
    /// A decimal-only mirror of this string binding: the setter runs
    /// `DecimalInput.filter(_, allowsDecimal: true)` so the field can only hold a
    /// valid decimal string. Reads pass through unchanged.
    var decimalInput: Binding<String> {
        Binding(get: { wrappedValue },
                set: { wrappedValue = DecimalInput.filter($0, allowsDecimal: true) })
    }
    /// Integer-only mirror (optional leading "-", digits, no separator).
    var integerInput: Binding<String> {
        Binding(get: { wrappedValue },
                set: { wrappedValue = DecimalInput.filter($0, allowsDecimal: false) })
    }
}
