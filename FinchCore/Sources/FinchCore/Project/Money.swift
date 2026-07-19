import Foundation

/// One projected exchange-rate row (`exchange_rates` table). `rate` is the
/// USD-per-1-unit price of `currency` on `date` (USD is the hub = 1).
public struct ExchangeRate: Equatable, Hashable, Sendable, Codable {
    public let date: String
    public let currency: String
    public let rate: Double
    public let source: String?
    public init(date: String, currency: String, rate: Double, source: String? = nil) {
        self.date = date; self.currency = currency; self.rate = rate; self.source = source
    }
}

/// Currency formatting + conversion, mirroring the web's `lib/fx.ts` +
/// `fmtNative` (lib/data.ts:51). Amounts are stored in the active ledger's base;
/// the tabs convert base→display (or account-ccy→base→display) via these.
public enum Money {
    /// The USD pivot — `latestRateMap` always pins it to 1 (fx.ts `HUB_CURRENCY`).
    public static let hubCurrency = "USD"

    private struct Cur { let sym: String; let decimals: Int }
    /// Symbol + decimal places per currency (mirrors the web `CURRENCIES` map;
    /// JPY shows 0 decimals). Unknown currencies fall back to "CODE " + 2 dp.
    private static let currencies: [String: Cur] = [
        "USD": Cur(sym: "$", decimals: 2),   "SGD": Cur(sym: "S$", decimals: 2),
        "EUR": Cur(sym: "€", decimals: 2),   "GBP": Cur(sym: "£", decimals: 2),
        "JPY": Cur(sym: "¥", decimals: 0),   "CNY": Cur(sym: "¥", decimals: 2),
        "AUD": Cur(sym: "A$", decimals: 2),  "CAD": Cur(sym: "C$", decimals: 2),
        "HKD": Cur(sym: "HK$", decimals: 2), "INR": Cur(sym: "₹", decimals: 2),
        "CHF": Cur(sym: "CHF ", decimals: 2),
    ]

    /// Format an amount already denominated in `currency` (no conversion).
    /// Mirrors `fmtNative`: `sign + symbol + grouped-abs`, U+2212 minus.
    public static func format(_ amount: Double, currency: String, signed: Bool = false) -> String {
        let c = currencies[currency] ?? Cur(sym: currency + " ", decimals: 2)
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = c.decimals
        nf.maximumFractionDigits = c.decimals
        nf.locale = Locale(identifier: "en_US")
        let absStr = nf.string(from: NSNumber(value: abs(amount))) ?? "0"
        let sign = amount < 0 ? "\u{2212}" : (signed ? "+" : "")
        return sign + c.sym + absStr
    }

    /// The display symbol for `currency` — the same prefix `format` uses (e.g. "$",
    /// "S$", "€"; unknown currencies fall back to "CODE ").
    public static func symbol(for currency: String) -> String {
        (currencies[currency] ?? Cur(sym: currency + " ", decimals: 2)).sym
    }

    /// Latest USD-per-1-unit rate per currency (USD pinned to 1). Mirrors
    /// `latestRateMap` (fx.ts): for each currency keep the row with the max date.
    public static func latestRateMap(_ rates: [ExchangeRate]) -> [String: Double] {
        var latest: [String: (date: String, rate: Double)] = [:]
        for r in rates {
            if let prev = latest[r.currency], !(r.date > prev.date) { continue }
            latest[r.currency] = (r.date, r.rate)
        }
        var m = latest.mapValues { $0.rate }
        m[hubCurrency] = 1
        return m
    }

    /// Convert `amount` from→to via the USD pivot: `(amount * rf) / rt`. Returns
    /// nil when either currency is unrated (callers fall back / pass through).
    public static func convert(_ amount: Double, from: String, to: String,
                               rates: [String: Double]) -> Double? {
        if from == to { return amount }
        guard let rf = rates[from], let rt = rates[to], rt != 0 else { return nil }
        return (amount * rf) / rt
    }
}
