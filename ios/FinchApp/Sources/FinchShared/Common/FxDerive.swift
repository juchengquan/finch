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
///
/// `tracked` and `grouped` answer two DIFFERENT questions and are deliberately not
/// one flag. `tracked` is live — it is what the row's switch shows. `grouped` is the
/// answer as of whenever the caller froze it, and it alone decides ordering and which
/// section the row lands in. The Currencies page freezes `grouped` when it opens so a
/// row never relocates out from under the finger that just toggled it; callers with
/// nothing to freeze (the base-currency picker) simply pass the same set twice.
struct FxCurrencyRow: Equatable {
    let code: String
    let label: String     // "Euro (€)" via FxCurrencyInfo
    let rate: Double?     // latest stored USD-per-unit; 1.0 for the hub; nil = none
    let tracked: Bool     // LIVE — drives the switch
    let grouped: Bool     // FROZEN — drives ordering + section membership
    let isHub: Bool       // USD — pinned first, no toggle
}

/// USD hub first, then grouped A–Z, then the rest A–Z.
///
/// `grouping` has no default on purpose: every call site has to say whether it is
/// ordering by the live set or by a frozen one, because defaulting it to `tracked`
/// would let the Currencies page silently fall back to relocating rows mid-visit.
@MainActor
func fxCurrencyRows(all: [String], rates: [ExchangeRate],
                    tracked: [String], grouping: [String]) -> [FxCurrencyRow] {
    let trackedSet = Set(tracked)
    let groupedSet = Set(grouping)
    let codes = all.sorted()
    func row(_ code: String, grouped: Bool) -> FxCurrencyRow {
        FxCurrencyRow(code: code, label: FxCurrencyInfo.label(code),
                      rate: fxLatest(rates, code)?.rate, tracked: trackedSet.contains(code),
                      grouped: grouped, isHub: false)
    }
    var rows = [FxCurrencyRow(code: "USD", label: FxCurrencyInfo.label("USD"),
                              rate: 1.0, tracked: false, grouped: false, isHub: true)]
    rows += codes.filter { $0 != "USD" && groupedSet.contains($0) }.map { row($0, grouped: true) }
    rows += codes.filter { $0 != "USD" && !groupedSet.contains($0) }.map { row($0, grouped: false) }
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
