import Foundation

/// Watch sub-project CP2 — shared App-Group constants + display helpers.
/// Foundation-only; compiled into FinchApp, FinchWatch, and the complication
/// extension so all three agree without a FinchCore dependency.
enum WatchStore {
    static let suite = "group.com.juchengquan.finch"
    static let key = "watchSnapshot"
}

/// Compact money for tiny watch faces. Static (CP3) so callers can format in
/// any currency — quick-add templates are denominated in the ITEM's currency,
/// not the snapshot's.
enum WatchMoney {
    /// "$842", "$12.3K", "¥1.2M".
    static func short(_ amount: Double, currency: String) -> String {
        let sym = currencySymbols[currency] ?? currency
        let mag = abs(amount)
        let sign = amount < 0 ? "-" : ""
        func trim(_ v: Double) -> String {
            let s = String(format: "%.1f", v)
            return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
        }
        if mag >= 1_000_000 { return "\(sign)\(sym)\(trim(mag / 1_000_000))M" }
        if mag >= 1_000 { return "\(sign)\(sym)\(trim(mag / 1_000))K" }
        return "\(sign)\(sym)\(Int(mag.rounded()))"
    }

    /// The currencies the app ships (seed ledger bases + majors); fallback is
    /// the raw code. A static map, not a Locale scan — the scan's first-match
    /// symbol depends on locale iteration order (e.g. "US$" vs "$") and would
    /// run per complication render.
    private static let currencySymbols: [String: String] = [
        "USD": "$", "SGD": "S$", "CNY": "¥", "JPY": "¥", "EUR": "€", "GBP": "£",
    ]
}

extension WatchSnapshotPayload {
    /// Compact currency in the snapshot's own currency (CP2 behavior, unchanged).
    func shortMoney(_ amount: Double) -> String { WatchMoney.short(amount, currency: currency) }

    /// Older than 24h — complications dim rather than hide stale data.
    var isStale: Bool { Date().timeIntervalSince(generatedAt) > 24 * 3600 }
}
