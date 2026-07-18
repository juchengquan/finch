import Foundation
import FinchCore

/// Daily FX auto-refresh from Frankfurter (api.frankfurter.dev — no key, central-
/// bank reference rates; the app's only third-party network call). Fetches ONLY
/// the currency codes in use, stores USD-per-unit via the setExchangeRate
/// chokepoint (source "ECB"), fails silently (offline-first; manual entry wins
/// by being later). Governed by Settings › Advanced → Auto-update exchange rates.
@MainActor
enum RateAutoUpdater {
    static let toggleKey = "finch.fx.autoUpdate"
    static let stampKey = "finch.fx.lastAutoUpdate"
    static let minInterval: TimeInterval = 20 * 60 * 60   // ~daily, DST-proof

    static func refreshIfDue(store: FinchStore) async {
        let d = UserDefaults.standard
        guard d.object(forKey: toggleKey) == nil || d.bool(forKey: toggleKey) else { return }  // default ON
        guard isDue(now: Date(), last: d.object(forKey: stampKey) as? Date) else { return }
        let codes = currenciesInUse(store: store)
        guard !codes.isEmpty else { return }
        guard let url = URL(string: "https://api.frankfurter.dev/v2/rates?base=USD&quotes=\(codes.joined(separator: ","))") else { return }
        var req = URLRequest(url: url); req.timeoutInterval = 10
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
        let rows = parse(data)
        guard !rows.isEmpty else { return }
        for r in rows {
            try? store.apply(.setExchangeRate, Args([
                "date": .string(r.date), "currency": .string(r.currency),
                "rate": .double(r.ratePerUSD), "source": .string("ECB")]))
        }
        d.set(Date(), forKey: stampKey)
    }

    /// Pure + testable. Frankfurter rows are {date, base, quote, rate} with rate =
    /// quote-per-USD; we store the inverse (USD per unit). USD/invalid rows dropped.
    static func parse(_ data: Data) -> [(date: String, currency: String, ratePerUSD: Double)] {
        struct Row: Decodable { let date: String; let quote: String; let rate: Double }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return [] }
        return rows.compactMap { r in
            guard r.rate > 0, r.quote.uppercased() != "USD" else { return nil }
            let inv = 1.0 / r.rate
            return (r.date, r.quote.uppercased(), (inv * 1_000_000).rounded() / 1_000_000)
        }
    }

    static func isDue(now: Date, last: Date?) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= minInterval
    }

    static func currenciesInUse(store: FinchStore) -> [String] {
        var set = Set(store.accounts.compactMap { $0.currency })
        set.formUnion(store.ledgers.map { $0.base })
        set.formUnion(store.exchangeRates.map { $0.currency })
        set.remove("USD")
        return set.sorted()
    }
}
