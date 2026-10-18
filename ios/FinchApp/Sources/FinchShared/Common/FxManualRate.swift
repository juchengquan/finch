import Foundation
import FinchCore

/// The pure half of the hand-entered exchange rate form (`ManualRateSheet`).
///
/// The engine stores every rate as USD per 1 unit, which is the wrong way round for
/// a person: nobody knows that 1 KRW is 0.00073 USD, and "KRW 0.0007" on its own
/// does not say which way it reads. So the form asks in words — "1 KRW = ___ EUR",
/// against the ledger's base — or, flipped, "1 EUR = ___ KRW", which is how a bank
/// or a receipt usually quotes it. This type turns either answer into the stored
/// USD-per-unit figure and back.

/// The source tag a hand-entered rate is saved with. The web's FX dialog writes the
/// same tag, and `SourceBadge` already colours it.
let fxManualSource = "manual"

/// Whether a stored rate is one the user entered (and so may edit). A row with no
/// source predates provenance tagging and already shows the "manual" badge.
func fxIsManual(_ rate: ExchangeRate) -> Bool {
    rate.source == nil || rate.source == fxManualSource
}

/// The currency a `error.fx.noRate` refusal is missing, or nil for any other error —
/// what lets a refused save offer to enter that rate by hand.
func fxNoRateCurrency(_ error: Error) -> String? {
    guard let e = error as? I18nError, e.code == "error.fx.noRate" else { return nil }
    return e.params["currency"]
}

/// A save refused for want of a rate, remembered with the message it put on screen,
/// so the sheet offers "Enter a KRW rate" under that refusal and no later error.
struct FxNoRateRefusal: Equatable {
    let currency: String
    let message: String

    init?(_ error: Error, shown message: String) {
        guard let currency = fxNoRateCurrency(error) else { return nil }
        self.currency = currency
        self.message = message
    }

    /// Whether `shown` — the sheet's current error line — is still this refusal.
    func isShowing(_ shown: String?) -> Bool { shown == message }
}

/// How a hand-entered rate for `currency` is quoted on the form.
struct FxManualQuote: Equatable {
    /// The currency being rated: "KRW".
    let currency: String
    /// What one unit is worth in: the ledger's base, or USD when the base cannot be
    /// used (it is the currency itself, or it has no rate to pivot through).
    let quote: String
    /// USD per 1 `quote`, as of the rate's date.
    let usdPerQuote: Double

    /// Quote against `base` when that is possible, else against USD (the hub).
    ///
    /// The base's own rate is looked up the way the engine looks one up for a
    /// write — nearest on-or-before `date`, else nearest after — so a rate typed
    /// as "1 KRW = 0.00067 EUR" is stored as the figure that converts back to
    /// exactly that on the same day.
    static func make(currency: String, base: String, date: String,
                     rates: [ExchangeRate]) -> FxManualQuote {
        let hub = FxManualQuote(currency: currency, quote: "USD", usdPerQuote: 1)
        guard base != currency, base != "USD" else { return hub }
        let mine = rates.filter { $0.currency == base }
        let rate = mine.filter { $0.date <= date }.max { $0.date < $1.date }
            ?? mine.filter { $0.date > date }.min { $0.date < $1.date }
        guard let rate, rate.rate > 0 else { return hub }
        return FxManualQuote(currency: currency, quote: base, usdPerQuote: rate.rate)
    }

    /// The left and right codes of the sentence the form reads as:
    /// "1 KRW = ___ EUR", or flipped, "1 EUR = ___ KRW".
    func terms(inverted: Bool) -> (one: String, other: String) {
        inverted ? (quote, currency) : (currency, quote)
    }

    /// The stored USD-per-unit figure for what was typed; nil unless it is > 0.
    func usdPerUnit(entered: Double, inverted: Bool) -> Double? {
        guard entered > 0, entered.isFinite else { return nil }
        return inverted ? usdPerQuote / entered : entered * usdPerQuote
    }

    /// What the form shows for a stored USD-per-unit figure — the inverse of
    /// `usdPerUnit`, used to seed the field when a rate is edited.
    func entered(usdPerUnit: Double, inverted: Bool) -> Double {
        inverted ? usdPerQuote / usdPerUnit : usdPerUnit / usdPerQuote
    }
}

/// A rate as text: six significant digits, never an exponent, "." decimal, no
/// grouping — so it reads the same everywhere and seeds a field that `DecimalInput`
/// parses back. 0.000730 → "0.00073", 1369.863 → "1369.86".
func fxRateText(_ value: Double) -> String {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.numberStyle = .decimal
    f.usesGroupingSeparator = false
    f.usesSignificantDigits = true
    f.maximumSignificantDigits = 6
    f.minimumSignificantDigits = 1
    return f.string(from: NSNumber(value: value)) ?? String(value)
}
