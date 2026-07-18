import Foundation
import FinchCore

/// Pure derivation helpers for the Exchange rates pages (grouped-by-currency
/// summary + per-currency history). Dates are ISO `yyyy-MM-dd` strings, so
/// lexicographic comparison == chronological.

/// Distinct currency codes, A–Z.
func fxCurrencies(_ rates: [ExchangeRate]) -> [String] {
    Set(rates.map(\.currency)).sorted()
}

/// Latest row for `currency` — max date; on equal dates the later row in list
/// order wins (mirrors upsert-last-wins intuition).
func fxLatest(_ rates: [ExchangeRate], _ currency: String) -> ExchangeRate? {
    rates.enumerated()
        .filter { $0.element.currency == currency }
        .max { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }?
        .element
}

/// Date-ascending rate values — the sparkline series.
func fxSeries(_ rates: [ExchangeRate], _ currency: String) -> [Double] {
    rates.filter { $0.currency == currency }.sorted { $0.date < $1.date }.map(\.rate)
}

/// "Jul 17" (or "Jul 17, 2026") for an ISO day; falls back to the raw string.
func fxDisplayDay(_ isoDay: String, withYear: Bool = false) -> String {
    guard let d = AppDate.isoDay.date(from: isoDay) else { return isoDay }
    return withYear ? d.formatted(.dateTime.month(.abbreviated).day().year())
                    : d.formatted(.dateTime.month(.abbreviated).day())
}

/// The FX auto-update fetch list: the user's explicit tracked set when the
/// app_state key exists (even empty = untracked everything), else the seeded
/// default (currencies in use).
func fxEffectiveTracked(stored: [String]?, fallback: [String]) -> [String] {
    stored ?? fallback
}
