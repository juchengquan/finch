import Foundation
import FinchCore

/// How a stored rate is shown on the read side — the Currencies list, its picker
/// twin, and one currency's history.
///
/// The engine keeps every rate as USD per 1 unit. Printed as that bare figure
/// ("%.4f"), KRW read "0.0007" — almost every digit gone — and nothing said which
/// way round it was. So a rate is shown as the same sentence the hand-entry form
/// (`ManualRateSheet`) asks in, against USD, the hub every rate is stored against:
///
/// - **The figure shown is at least 1.** A currency worth a dollar or more reads
///   "1 EUR = 1.0842 USD"; one worth less reads the other way round,
///   "1 USD = 1,369.86 KRW" — how a bank quotes a small-unit currency.
/// - **The direction is per currency, decided by its latest rate**, so a currency's
///   history never flips mid-list as it drifts across 1.
/// - **Six significant digits at most, four at least**, in the user's locale: the
///   precision follows the size of the figure rather than a fixed four decimals.

/// Whether `currency` reads "1 USD = x CUR" rather than "1 CUR = x USD" — true when
/// its latest rate is under a dollar.
func fxReadsInverted(latest usdPerUnit: Double?) -> Bool {
    guard let usdPerUnit, usdPerUnit > 0 else { return false }
    return usdPerUnit < 1
}

/// A stored USD-per-unit rate as a sentence: "1 EUR = 1.0842 USD", or inverted,
/// "1 USD = 1,369.86 KRW". Nil for USD itself — the hub has no rate to show.
func fxRateDisplay(_ usdPerUnit: Double, currency: String, inverted: Bool,
                   locale: Locale = .autoupdatingCurrent) -> String? {
    guard currency != "USD" else { return nil }
    // Inverting a non-positive figure has no meaning; the engine refuses such a
    // rate, but a legacy row should still print as stored.
    if inverted, usdPerUnit > 0 {
        return "1 USD = \(fxRateNumber(1 / usdPerUnit, locale: locale)) \(currency)"
    }
    return "1 \(currency) = \(fxRateNumber(usdPerUnit, locale: locale)) USD"
}

/// `fxRateDisplay` in the direction the rate itself calls for — for a single
/// figure with no history around it (a Currencies row).
func fxRateDisplay(_ usdPerUnit: Double, currency: String,
                   locale: Locale = .autoupdatingCurrent) -> String? {
    fxRateDisplay(usdPerUnit, currency: currency,
                  inverted: fxReadsInverted(latest: usdPerUnit), locale: locale)
}

/// The history sparkline's series in the direction its rows read, so the line
/// rises when the figures beside it do.
func fxDisplaySeries(_ rates: [ExchangeRate], _ currency: String) -> [Double] {
    let series = fxSeries(rates, currency)
    guard fxReadsInverted(latest: fxLatest(rates, currency)?.rate) else { return series }
    return series.map { $0 > 0 ? 1 / $0 : 0 }
}

/// A rate figure: 4–6 significant digits, never an exponent, grouped and with the
/// decimal mark of `locale`. 1369.863 → "1,369.86", 1.08 → "1.080", 1 → "1.000".
/// The four-digit floor keeps a currency's history in an even column.
func fxRateNumber(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
    let f = NumberFormatter()
    f.locale = locale
    f.numberStyle = .decimal
    f.usesSignificantDigits = true
    f.minimumSignificantDigits = 4
    f.maximumSignificantDigits = 6
    return f.string(from: NSNumber(value: value)) ?? String(value)
}
