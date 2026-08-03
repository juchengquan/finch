import Foundation
import FinchCore

/// What a fetch attempt did — drives "Refresh now" feedback (auto path discards it).
enum RefreshOutcome: Equatable {
    case updated(Int)                            // every requested code got a rate
    case partial(updated: Int, requested: Int)   // some did; the rest are still missing
    case failed                                  // every provider failed — nothing written
    case skipped                                 // no non-USD currencies in use — nothing to fetch
}

/// Daily FX auto-refresh. Walks a chain of free, no-key reference-rate providers
/// (Frankfurter/ECB → open.er-api.com → fawazahmed0 currency-api), asking each one
/// only for the codes still missing — so a provider being down, blocked, or simply
/// not carrying a currency falls through to the next. Fetches ONLY the effective
/// tracked set (user's toggles, else the currencies in use), normalizes every
/// provider to USD-per-unit, and stores via the setExchangeRate chokepoint tagged
/// with the provider each row came from. Fails silently (offline-first; manual entry
/// wins by being later). Governed by the master toggle on Settings › Currencies. The
/// app's only third-party network calls.
///
/// WHY PER-CURRENCY AND NOT FIRST-WINS. This used to stop at the first provider that
/// returned ANYTHING, which made a currency the first provider doesn't carry
/// permanently unreachable: with {EUR, BGN}, Frankfurter answers for EUR alone,
/// `!rows.isEmpty` reads as success, and the two providers that DO have BGN are never
/// asked — the row shows "—" forever while the screen reports "Updated 1 rates".
/// Coverage of the 154 non-USD codes finch offers is not uniform and no single
/// provider is complete (measured 2026-08-03: Frankfurter 151, missing BGN/VED/ZWL;
/// er-api 152, missing KPW/VED; currency-api 152, missing KPW/SYP) — but their UNION
/// is all 154, so asking each provider for the remainder reaches every currency.
///
/// Note that "missing" means ABSENT, never merely older. Frankfurter dates a large
/// minority of rows to the last publication day rather than today — euro-pegged
/// currencies (XPF, XAF, XOF, BAM …) fix on business days — and those are the
/// authoritative numbers, within ~0.2% of what the daily providers interpolate.
/// Re-fetching them from a later provider would trade a central-bank fix for a CDN's
/// approximation.
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
    /// it ignores toggle + throttle). Stamps lastAutoUpdate whenever anything was
    /// written, including a partial result — the stamp means "we reached a provider
    /// today", and re-running the chain minutes later would not find more.
    static func refresh(store: FinchStore) async -> RefreshOutcome {
        let codes = fxEffectiveTracked(stored: store.trackedCurrencies, fallback: currenciesInUse(store: store))
        guard !codes.isEmpty else { return .skipped }
        let (rows, missing) = await collect(codes: codes)
        guard !rows.isEmpty else { return .failed }
        // One batched write, NOT one apply per rate: per-rate applies fired
        // the full side-effect train (16 projections + Spotlight re-index +
        // widget/notification replans) N times on the MainActor and froze
        // the UI for seconds right after foregrounding (audit 2026-07-22).
        store.applyBatch(rows.map { r in
            (ActionName.setExchangeRate, Args([
                "date": .string(r.date), "currency": .string(r.currency),
                "rate": .double(r.ratePerUSD), "source": .string(r.source)]))
        })
        UserDefaults.standard.set(Date(), forKey: stampKey)
        // Union coverage is complete, so anything still missing here is a provider
        // that could not be reached — transient, not an unsupported currency.
        return missing.isEmpty ? .updated(rows.count)
                               : .partial(updated: rows.count, requested: codes.count)
    }

    // MARK: - The chain

    /// A rate normalized to USD-per-unit, tagged with the provider that supplied it.
    /// The tag is per-ROW, not per-fetch, because one refresh can now mix providers.
    struct Row: Equatable {
        let date: String
        let currency: String
        let ratePerUSD: Double
        let source: String
    }

    /// The network seam: a request in, `(body, statusCode)` out, `nil` if it never
    /// completed. Injected so the chain's control flow — which provider is asked for
    /// what, and how a rejected request recovers — is testable without the network.
    typealias Transport = (URLRequest) async -> (Data, Int)?

    static let liveTransport: Transport = { req in
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return nil }
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Ask each provider in turn for only the codes still missing, stopping as soon
    /// as nothing is missing or the chain runs out. Returns what was gathered plus
    /// whatever nobody answered for.
    ///
    /// In the common case — the first provider carries everything — this is still
    /// exactly one request.
    static func collect(codes: [String],
                        transport: Transport = liveTransport) async -> (rows: [Row], missing: [String]) {
        var missing = codes
        var rows: [Row] = []
        for provider in providers {
            guard !missing.isEmpty else { break }
            let got = await fetch(provider, missing, transport)
            guard !got.isEmpty else { continue }
            rows += got
            let have = Set(got.map(\.currency))
            missing = missing.filter { !have.contains($0) }
        }
        return (rows, missing)
    }

    /// One provider, including its own recovery from a rejected request.
    private static func fetch(_ provider: Provider, _ codes: [String],
                              _ transport: Transport) async -> [Row] {
        var ask = codes
        for _ in 0..<maxAttemptsPerProvider {
            guard !ask.isEmpty, let url = provider.url(ask) else { return [] }
            var req = URLRequest(url: url); req.timeoutInterval = 10
            guard let (data, status) = await transport(req) else { return [] }
            if status == 200 {
                // Filtered to what was ASKED, not just to what the parser emits:
                // `parseFrankfurter` ignores the code list and trusts the server's
                // `quotes=` filter, so without this an unrequested row would be
                // written and would make `.partial`'s counts disagree with reality.
                // The other two parsers already filter; this makes all three alike.
                let wanted = Set(ask)
                return provider.parse(data, ask)
                    .filter { wanted.contains($0.currency) }
                    .map { Row(date: $0.date, currency: $0.currency,
                               ratePerUSD: $0.ratePerUSD, source: provider.source) }
            }
            // A rejected request may name ONE offending code rather than being a
            // real outage. Drop it and retry, so a single exotic currency does not
            // cost every OTHER currency this provider's rates. nil means
            // unrecoverable and we fall through to the next provider.
            guard let reduced = provider.recover?(data, ask), reduced.count < ask.count else { return [] }
            ask = reduced
        }
        return []
    }

    /// Initial attempt plus recoveries. Bounded because `recover` is driven by a
    /// third party's error text.
    static let maxAttemptsPerProvider = 4

    // MARK: - Providers (asked in order, each for whatever is still missing)

    /// One free reference-rate source: a URL builder (given the wanted codes), a pure
    /// parser normalizing its response to (date, CODE, USD-per-unit), and an optional
    /// recovery from a rejected request.
    struct Provider {
        let source: String
        let url: ([String]) -> URL?
        let parse: (Data, [String]) -> [(date: String, currency: String, ratePerUSD: Double)]
        /// Given the error body and the codes asked, a SMALLER list worth retrying,
        /// or nil when the failure is not recoverable. Provider-specific by design —
        /// only Frankfurter rejects a whole query over one member.
        let recover: ((Data, [String]) -> [String]?)?
    }

    static let providers: [Provider] = [
        // 1) Frankfurter — central-bank reference rates (server-side filtered).
        Provider(source: "ECB",
                 url: { codes in URL(string: "https://api.frankfurter.dev/v2/rates?base=USD&quotes=\(codes.joined(separator: ","))") },
                 parse: { data, _ in parseFrankfurter(data) },
                 recover: recoverFrankfurter),
        // 2) open.er-api.com — free, broad coverage (returns all; we filter).
        Provider(source: "er-api",
                 url: { _ in URL(string: "https://open.er-api.com/v6/latest/USD") },
                 parse: { data, codes in parseErApi(data, codes: codes) },
                 recover: nil),
        // 3) fawazahmed0 currency-api — CDN-hosted static JSON, broadest coverage.
        Provider(source: "currency-api",
                 url: { _ in URL(string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json") },
                 parse: { data, codes in parseCurrencyApi(data, codes: codes) },
                 recover: nil),
    ]

    /// Frankfurter answers `422 {"status":422,"message":"invalid currency: VED"}` and
    /// rejects the ENTIRE query when a single quote is unsupported — so without this,
    /// one such code in the tracked set silently downgrades every other currency to a
    /// later provider. Deliberately coupled to the message wording: if that ever
    /// changes this returns nil, the provider is skipped, and we get the behaviour we
    /// would have had anyway.
    static func recoverFrankfurter(_ data: Data, _ codes: [String]) -> [String]? {
        struct Err: Decodable { let message: String? }
        guard let message = (try? JSONDecoder().decode(Err.self, from: data))?.message,
              let marker = message.range(of: "invalid currency:") else { return nil }
        let bad = message[marker.upperBound...]
            .split(separator: " ", omittingEmptySubsequences: true)
            .first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        guard let bad, codes.contains(bad) else { return nil }
        return codes.filter { $0 != bad }
    }

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
