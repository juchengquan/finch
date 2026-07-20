import Foundation
import FinchCore

/// What a fetch attempt did — drives "Refresh now" feedback (auto path discards it).
enum RefreshOutcome: Equatable {
    case updated(Int)   // wrote N rates; stamp written
    case failed         // every provider failed — nothing written
    case skipped        // no non-USD currencies in use — nothing to fetch
}

/// Daily FX auto-refresh. Tries a chain of free, no-key reference-rate providers
/// in order (Frankfurter/ECB → open.er-api.com → fawazahmed0 currency-api) and
/// uses the first that returns rates — so a provider being down/blocked falls
/// straight through to the next. Fetches ONLY the effective tracked set (user's
/// toggles, else the currencies in use), normalizes every provider to
/// USD-per-unit, and stores via the setExchangeRate chokepoint tagged with the
/// provider it came from. Fails silently (offline-first; manual entry wins by
/// being later). Governed by the master toggle on Settings › Currencies. The
/// app's only third-party network calls.
@MainActor
enum RateAutoUpdater {
    static let toggleKey = "finch.fx.autoUpdate"
    static let stampKey = "finch.fx.lastAutoUpdate"
    static let minInterval: TimeInterval = 20 * 60 * 60   // ~daily, DST-proof

    /// Guarded entry point (foreground trigger): toggle on (absent key = ON),
    /// ≥ minInterval since last success. Outcome discarded — auto path is silent.
    static func refreshIfDue(store: FinchStore) async {
        let d = UserDefaults.standard
        guard d.object(forKey: toggleKey) == nil || d.bool(forKey: toggleKey) else { return }  // default ON
        guard isDue(now: Date(), last: d.object(forKey: stampKey) as? Date) else { return }
        _ = await refresh(store: store)
    }

    /// Unguarded fetch (also the "Refresh now" path — a deliberate manual act, so
    /// it ignores toggle + throttle). Walks the provider chain and stops at the
    /// first that yields rates; stamps lastAutoUpdate ONLY on success.
    static func refresh(store: FinchStore) async -> RefreshOutcome {
        let codes = fxEffectiveTracked(stored: store.trackedCurrencies, fallback: currenciesInUse(store: store))
        guard !codes.isEmpty else { return .skipped }
        for provider in providers {
            guard let url = provider.url(codes) else { continue }
            var req = URLRequest(url: url); req.timeoutInterval = 10
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else { continue }
            let rows = provider.parse(data, codes)
            guard !rows.isEmpty else { continue }
            for r in rows {
                try? store.apply(.setExchangeRate, Args([
                    "date": .string(r.date), "currency": .string(r.currency),
                    "rate": .double(r.ratePerUSD), "source": .string(provider.source)]))
            }
            UserDefaults.standard.set(Date(), forKey: stampKey)
            return .updated(rows.count)
        }
        return .failed
    }

    // MARK: - Providers (tried in order; first non-empty success wins)

    /// One free reference-rate source: a URL builder (given the wanted codes) and
    /// a pure parser that normalizes its response to (date, CODE, USD-per-unit).
    struct Provider {
        let source: String
        let url: ([String]) -> URL?
        let parse: (Data, [String]) -> [(date: String, currency: String, ratePerUSD: Double)]
    }

    static let providers: [Provider] = [
        // 1) Frankfurter — ECB central-bank reference rates (server-side filtered).
        Provider(source: "ECB",
                 url: { codes in URL(string: "https://api.frankfurter.dev/v2/rates?base=USD&quotes=\(codes.joined(separator: ","))") },
                 parse: { data, _ in parseFrankfurter(data) }),
        // 2) open.er-api.com — free, broad coverage (returns all; we filter).
        Provider(source: "er-api",
                 url: { _ in URL(string: "https://open.er-api.com/v6/latest/USD") },
                 parse: { data, codes in parseErApi(data, codes: codes) }),
        // 3) fawazahmed0 currency-api — CDN-hosted static JSON, broadest coverage.
        Provider(source: "currency-api",
                 url: { _ in URL(string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json") },
                 parse: { data, codes in parseCurrencyApi(data, codes: codes) }),
    ]

    // MARK: - Parsers (pure + testable). All emit USD-per-unit, drop USD/invalid.

    /// Frankfurter: array of {date, quote, rate} with rate = quote-per-USD.
    static func parseFrankfurter(_ data: Data) -> [(date: String, currency: String, ratePerUSD: Double)] {
        struct Row: Decodable { let date: String; let quote: String; let rate: Double }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return [] }
        return rows.compactMap { r in
            guard r.rate > 0, r.quote.uppercased() != "USD" else { return nil }
            return (r.date, r.quote.uppercased(), round6(1.0 / r.rate))
        }
    }

    /// open.er-api.com: { time_last_update_unix, rates: { EUR: units-per-USD, … } }.
    static func parseErApi(_ data: Data, codes: [String]) -> [(date: String, currency: String, ratePerUSD: Double)] {
        struct Resp: Decodable { let time_last_update_unix: Double?; let rates: [String: Double] }
        guard let resp = try? JSONDecoder().decode(Resp.self, from: data) else { return [] }
        let date = resp.time_last_update_unix.map { isoDay(fromUnix: $0) } ?? todayISO()
        let want = Set(codes.map { $0.uppercased() })
        return resp.rates.compactMap { (code, unitsPerUSD) in
            let up = code.uppercased()
            guard want.contains(up), up != "USD", unitsPerUSD > 0 else { return nil }
            return (date, up, round6(1.0 / unitsPerUSD))
        }
    }

    /// fawazahmed0 currency-api: { date, usd: { eur: units-per-USD, … } } (lowercase codes).
    static func parseCurrencyApi(_ data: Data, codes: [String]) -> [(date: String, currency: String, ratePerUSD: Double)] {
        struct Resp: Decodable { let date: String; let usd: [String: Double] }
        guard let resp = try? JSONDecoder().decode(Resp.self, from: data) else { return [] }
        let want = Set(codes.map { $0.lowercased() })
        return resp.usd.compactMap { (code, unitsPerUSD) in
            let lc = code.lowercased()
            guard want.contains(lc), lc != "usd", unitsPerUSD > 0 else { return nil }
            return (resp.date, lc.uppercased(), round6(1.0 / unitsPerUSD))
        }
    }

    private static func round6(_ v: Double) -> Double { (v * 1_000_000).rounded() / 1_000_000 }
    private static func todayISO() -> String { AppDate.isoDay.string(from: Date()) }
    private static func isoDay(fromUnix t: Double) -> String { AppDate.isoDay.string(from: Date(timeIntervalSince1970: t)) }

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
