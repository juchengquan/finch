import SwiftUI

/// Parse + live input filtering for numeric text fields. Decimal input uses "." as
/// the only decimal separator ("," is rejected on input); `parse` reads plain "."
/// decimals.
enum DecimalInput {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .current
        return f
    }()

    /// Parse decimal text (a plain "." decimal, as produced by `filter`) to a Double.
    /// Falls back to the locale formatter for any grouping-formatted seed strings.
    static func parse(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        if let d = Double(t) { return d }
        return formatter.number(from: t)?.doubleValue
    }

    /// Strip a live text-field string to a valid numeric string. Keeps an optional
    /// leading "-" and ASCII digits; for decimals, keeps the FIRST "." and drops every
    /// later separator (so once a number has a decimal point, another is ignored —
    /// "5.4." → "5.4", "5.4.4.4" → "5.444"). "," is NOT a decimal separator here — it is
    /// removed like any other stray character, along with letters, spaces, currency
    /// symbols, and grouping. Does NOT reformat; intermediate "-"/"." survive so typing
    /// isn't blocked.
    static func filter(_ s: String, allowsDecimal: Bool) -> String {
        var out = ""
        var sawSeparator = false
        for (i, ch) in s.enumerated() {
            if ch == "-" {
                if i == 0 { out.append(ch) }                 // only a leading minus
            } else if ch.isASCII && ch.isNumber {            // 0–9
                out.append(ch)
            } else if allowsDecimal && ch == "." {           // "." only — comma rejected
                if !sawSeparator { out.append(ch); sawSeparator = true }
            }
            // else: strip
        }
        return out
    }
}

extension View {
    /// Live-filter a numeric text field. After each edit, rewrite `text` to a valid
    /// numeric string (`DecimalInput.filter`). Writing back through the field's own
    /// state forces SwiftUI to correct the *displayed* text — so a rejected character
    /// (a letter, a comma, a 2nd separator) can't linger on screen while the field is
    /// being edited. Works identically on iOS/iPad and macOS, and against paste.
    /// `allowsDecimal: false` restricts to integers (no separator).
    func numericInput(_ text: Binding<String>, allowsDecimal: Bool = true) -> some View {
        onChange(of: text.wrappedValue) { _, newValue in
            let filtered = DecimalInput.filter(newValue, allowsDecimal: allowsDecimal)
            if filtered != newValue { text.wrappedValue = filtered }
        }
    }
}
