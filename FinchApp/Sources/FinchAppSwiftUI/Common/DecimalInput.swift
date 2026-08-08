import SwiftUI
import FinchCore

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
    /// The amount-field placeholder for a currency with `fractionDigits` minor
    /// units: "0", "0.00", "0.000".
    static func zeroPlaceholder(fractionDigits: Int) -> String {
        fractionDigits == 0 ? "0" : "0." + String(repeating: "0", count: fractionDigits)
    }

    /// What a field should read once the user leaves it.
    ///
    /// Pure, and separate from the modifier, so the rules are testable without a
    /// view. Returns the input unchanged when there is nothing to settle.
    static func settled(_ s: String, currency: String) -> String {
        // Empty is UNSET, not zero — an optional field (rollover cap, last
        // price, max filter) and an untouched grid cell both rely on that.
        guard !s.trimmingCharacters(in: .whitespaces).isEmpty else { return s }
        // Mid-entry: "5." is on its way to 5.75. Settling it to "5.00" would sit
        // the field at max digits and swallow the next keystroke.
        guard !s.hasSuffix(".") else { return s }
        guard let value = parse(s) else { return s }
        return text(value, currency: currency)
    }

    /// The text to SEED an amount field with — the counterpart to `filter`, which
    /// governs typing.
    ///
    /// Every seed site used `String(format: "%g", …)`, which carries six
    /// significant digits and drops trailing zeros: 500 became "500", and — the
    /// half that mattered — 1234567.89 became "1.23457e+06", which `parse`
    /// accepts as 1234570.0. Opening a large transaction and pressing save
    /// rewrote the amount. Neither input filter catches it: both run `onChange`,
    /// and a seeded value never fires one.
    static func text(_ value: Double, currency: String) -> String {
        text(value, fractionDigits: Currencies.minorUnits(for: currency))
    }

    /// For the rare caller that knows its digits without a currency code.
    static func text(_ value: Double, fractionDigits: Int) -> String {
        String(format: "%.\(fractionDigits)f", value)
    }

    /// `maxFractionDigits` (ISO 4217 minor units) caps the digits AFTER the
    /// separator — TRIM semantics, distinct from `allowsDecimal: false`'s strip:
    /// "12.34" clamped to 0 digits is "12" (cut at the separator), never "1234".
    /// That difference is what makes mid-entry currency switches honest.
    static func filter(_ s: String, allowsDecimal: Bool, maxFractionDigits: Int? = nil) -> String {
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
        guard let maxDigits = maxFractionDigits, let dot = out.firstIndex(of: ".") else { return out }
        if maxDigits == 0 { return String(out[..<dot]) }     // cut AT the separator
        let fracStart = out.index(after: dot)
        guard out.distance(from: fracStart, to: out.endIndex) > maxDigits else { return out }
        return String(out[..<out.index(fracStart, offsetBy: maxDigits)])
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

    /// A currency-denominated amount field: clamps typing to the currency's
    /// ISO 4217 minor units (`Currencies.minorUnits(for:)`), hides the decimal
    /// key for 0-decimal currencies, re-trims when the currency CHANGES
    /// mid-entry, and — on blur — settles what was typed to the currency's
    /// digits so a typed value reads the same as a seeded one.
    /// Not for rates or quantities — those stay on plain `numericInput`.
    func moneyInput(_ text: Binding<String>, currency: String) -> some View {
        modifier(MoneyInputModifier(text: text, currency: currency))
    }
}

/// The body of `moneyInput`.
///
/// A `ViewModifier` rather than a chain of `.onChange` because `@FocusState` has
/// to be owned by a view, and the blur pass needs it. Every existing caller
/// gains that pass with no edit — which is the point of putting it here rather
/// than in the twenty sheets that use it.
private struct MoneyInputModifier: ViewModifier {
    @Binding var text: String
    let currency: String
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        let digits = Currencies.minorUnits(for: currency)
        // allowsDecimal stays true even for 0-digit currencies: the max-0 clamp
        // CUTS at the separator (trim), where allowsDecimal:false would strip it
        // and glue the fraction onto the integer ("12.34" → "1234").
        return content
            .keyboardType(digits == 0 ? .numberPad : .decimalPad)
            .focused($focused)
            .onChange(of: text) { _, newValue in
                let filtered = DecimalInput.filter(newValue, allowsDecimal: true, maxFractionDigits: digits)
                if filtered != newValue { text = filtered }
            }
            .onChange(of: currency) { _, newCurrency in
                let d = Currencies.minorUnits(for: newCurrency)
                let filtered = DecimalInput.filter(text, allowsDecimal: true, maxFractionDigits: d)
                if filtered != text { text = filtered }
            }
            .onChange(of: focused) { _, isFocused in
                guard !isFocused else { return }
                let settled = DecimalInput.settled(text, currency: currency)
                if settled != text { text = settled }
            }
    }
}
