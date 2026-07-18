import Foundation
import FinchCore

/// What a fetch attempt did — drives "Refresh now" feedback (auto path discards it).
enum RefreshOutcome: Equatable {
    case updated(Int)   // wrote N rates; stamp written
    case failed         // URL/network/non-200/decode failure — nothing written
    case skipped        // no non-USD currencies in use — nothing to fetch
}

/// Daily FX auto-refresh from Frankfurter (api.frankfurter.dev — no key, central-
/// bank reference rates; the app's only third-party network call). Fetches ONLY
/// the effective tracked set (user's toggles, else the currencies in use), stores
/// USD-per-unit via the setExchangeRate chokepoint (source "ECB"), fails silently
/// (offline-first; manual entry wins by being later). Governed by the master
/// toggle on Settings › Currencies. Frankfurter silently drops quote codes it
/// doesn't publish (verified: mixed requests return the supported subset, 200).
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
    /// it ignores toggle + throttle). Stamps lastAutoUpdate ONLY on success, so a
    /// manual refresh satisfies "today's fetch" and the next auto-run throttles.
    static func refresh(store: FinchStore) async -> RefreshOutcome {
        let codes = fxEffectiveTracked(stored: store.trackedCurrencies, fallback: currenciesInUse(store: store))
        guard !codes.isEmpty else { return .skipped }
        guard let url = URL(string: "https://api.frankfurter.dev/v2/rates?base=USD&quotes=\(codes.joined(separator: ","))") else { return .failed }
        var req = URLRequest(url: url); req.timeoutInterval = 10
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return .failed }
        let rows = parse(data)
        guard !rows.isEmpty else { return .failed }
        for r in rows {
            try? store.apply(.setExchangeRate, Args([
                "date": .string(r.date), "currency": .string(r.currency),
                "rate": .double(r.ratePerUSD), "source": .string("ECB")]))
        }
        UserDefaults.standard.set(Date(), forKey: stampKey)
        return .updated(rows.count)
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
