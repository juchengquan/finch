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

/// One row of the Currencies page.
struct FxCurrencyRow: Equatable {
    let code: String
    let label: String     // "Euro (€)" via FxCurrencyInfo
    let rate: Double?     // latest stored USD-per-unit; 1.0 for the hub; nil = none
    let tracked: Bool
    let isHub: Bool       // USD — pinned first, no toggle
}

/// USD hub first, then tracked A–Z, then the rest A–Z.
@MainActor
func fxCurrencyRows(all: [String], rates: [ExchangeRate], tracked: [String]) -> [FxCurrencyRow] {
    let trackedSet = Set(tracked)
    let codes = all.sorted()
    func row(_ code: String, tracked: Bool) -> FxCurrencyRow {
        FxCurrencyRow(code: code, label: FxCurrencyInfo.label(code),
                      rate: fxLatest(rates, code)?.rate, tracked: tracked, isHub: false)
    }
    var rows = [FxCurrencyRow(code: "USD", label: FxCurrencyInfo.label("USD"),
                              rate: 1.0, tracked: false, isHub: true)]
    rows += codes.filter { $0 != "USD" && trackedSet.contains($0) }.map { row($0, tracked: true) }
    rows += codes.filter { $0 != "USD" && !trackedSet.contains($0) }.map { row($0, tracked: false) }
    return rows
}

/// Case-insensitive search over code or label; empty query passes everything through.
func fxFilterRows(_ rows: [FxCurrencyRow], query: String) -> [FxCurrencyRow] {
    let q = query.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return rows }
    return rows.filter { $0.code.localizedCaseInsensitiveContains(q) || $0.label.localizedCaseInsensitiveContains(q) }
}

/// The tracked set after "activating" `code`, or **nil when no write is needed** —
/// the ledger base-currency picker calls this on save.
///
/// Two no-write cases: USD is the hub and is never tracked (`setTrackedCurrencies`
/// filters it out regardless), and an already-tracked code needs nothing. Callers
/// must pass the EFFECTIVE tracked set (`fxEffectiveTracked`), not the raw optional:
/// when the app_state key is still unset the effective set is the seeded default, and
/// basing the write on it materializes that default instead of wiping it to one entry.
func fxTrackedAfterActivating(_ code: String, tracked: [String]) -> [String]? {
    let c = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard !c.isEmpty, c != "USD" else { return nil }
    guard !tracked.contains(where: { $0.caseInsensitiveCompare(c) == .orderedSame }) else { return nil }
    return (tracked.map { $0.uppercased() } + [c]).sorted()
}
