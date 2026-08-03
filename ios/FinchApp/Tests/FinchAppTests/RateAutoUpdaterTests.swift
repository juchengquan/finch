import XCTest
@testable import FinchApp

/// RateAutoUpdater's pure pieces (no network in tests). The enum is @MainActor,
/// so the class is @MainActor too (suite idiom — see DeepLinkRouterTests).
@MainActor
final class RateAutoUpdaterTests: XCTestCase {
    // MARK: Frankfurter (provider 1)
    func test_frankfurter_invertsQuotePerUSD_dropsUSDAndInvalid() throws {
        let json = #"[{"date":"2026-07-17","base":"USD","quote":"EUR","rate":0.87241},{"date":"2026-07-17","base":"USD","quote":"USD","rate":1},{"date":"2026-07-17","base":"USD","quote":"BAD","rate":0}]"#
        let rows = RateAutoUpdater.parseFrankfurter(Data(json.utf8))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].currency, "EUR")
        XCTAssertEqual(rows[0].ratePerUSD, 1.146250, accuracy: 0.000001)   // 1/0.87241, 6-dp
    }
    func test_frankfurter_malformed_returnsEmpty() {
        XCTAssertTrue(RateAutoUpdater.parseFrankfurter(Data("nope".utf8)).isEmpty)
    }

    // MARK: open.er-api.com (provider 2) — filters to requested codes, uppercase output.
    func test_erApi_filtersToCodes_invertsAndDropsUSDInvalid() throws {
        let json = #"{"time_last_update_unix":1721260801,"rates":{"USD":1,"EUR":0.87241,"JPY":155.0,"BAD":0}}"#
        let rows = RateAutoUpdater.parseErApi(Data(json.utf8), codes: ["EUR", "JPY"]).sorted { $0.currency < $1.currency }
        XCTAssertEqual(rows.map(\.currency), ["EUR", "JPY"])               // USD + BAD dropped; codes-only
        XCTAssertEqual(rows[0].ratePerUSD, 1.146250, accuracy: 0.000001)   // 1/0.87241
        XCTAssertEqual(rows[1].ratePerUSD, 1.0 / 155.0, accuracy: 0.000001)
    }
    func test_erApi_malformed_returnsEmpty() {
        XCTAssertTrue(RateAutoUpdater.parseErApi(Data("nope".utf8), codes: ["EUR"]).isEmpty)
    }

    // MARK: fawazahmed0 currency-api (provider 3) — lowercase keys → uppercase output.
    func test_currencyApi_filtersUppercases_invertsAndDropsUSD() throws {
        let json = #"{"date":"2026-07-17","usd":{"eur":0.87241,"jpy":155.0,"usd":1}}"#
        let rows = RateAutoUpdater.parseCurrencyApi(Data(json.utf8), codes: ["EUR"])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].currency, "EUR")                            // lowercased key → uppercased out
        XCTAssertEqual(rows[0].date, "2026-07-17")
        XCTAssertEqual(rows[0].ratePerUSD, 1.146250, accuracy: 0.000001)
    }
    func test_currencyApi_malformed_returnsEmpty() {
        XCTAssertTrue(RateAutoUpdater.parseCurrencyApi(Data("nope".utf8), codes: ["EUR"]).isEmpty)
    }

    func test_isDue_throttle() {
        XCTAssertTrue(RateAutoUpdater.isDue(now: Date(), last: nil))
        XCTAssertFalse(RateAutoUpdater.isDue(now: Date(), last: Date().addingTimeInterval(-3600)))
        XCTAssertTrue(RateAutoUpdater.isDue(now: Date(), last: Date().addingTimeInterval(-21*3600)))
    }

    // MARK: recoverFrankfurter — one bad code must not sink the whole query

    func test_recoverFrankfurter_dropsTheNamedCode() {
        let body = Data(#"{"status":422,"message":"invalid currency: VED"}"#.utf8)
        XCTAssertEqual(RateAutoUpdater.recoverFrankfurter(body, ["EUR", "VED", "JPY"]), ["EUR", "JPY"])
    }
    func test_recoverFrankfurter_unrecoverable_returnsNil() {
        // Not a code we asked for, wrong wording, and non-JSON all fall through to
        // the next provider rather than looping.
        XCTAssertNil(RateAutoUpdater.recoverFrankfurter(
            Data(#"{"status":422,"message":"invalid currency: XXX"}"#.utf8), ["EUR"]))
        XCTAssertNil(RateAutoUpdater.recoverFrankfurter(
            Data(#"{"status":500,"message":"upstream exploded"}"#.utf8), ["EUR"]))
        XCTAssertNil(RateAutoUpdater.recoverFrankfurter(Data("nope".utf8), ["EUR"]))
    }
}

/// The provider chain itself — which provider is asked for WHAT. This is the whole
/// substance of the fallthrough, and it used to be unreachable from a test because
/// the loop did its own URLSession calls inline. Driven here through the injected
/// `Transport`, so no network and no FinchStore.
@MainActor
final class RateAutoUpdaterChainTests: XCTestCase {

    /// Records every request and replies from a canned table keyed by host.
    private func transport(_ reply: @escaping (String, [String]) -> (Data, Int)?,
                           log: Log) -> RateAutoUpdater.Transport {
        { req in
            let url = req.url!
            let host = url.host ?? ""
            let quotes = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "quotes" }?.value
            let asked = quotes.map { $0.split(separator: ",").map(String.init) } ?? []
            log.calls.append((host, asked))
            return reply(host, asked)
        }
    }

    private final class Log { var calls: [(host: String, asked: [String])] = [] }

    private func frankfurter(_ pairs: [(String, Double)]) -> Data {
        Data(("[" + pairs.map { #"{"date":"2026-08-03","base":"USD","quote":"\#($0.0)","rate":\#($0.1)}"# }
            .joined(separator: ",") + "]").utf8)
    }
    private func erApi(_ pairs: [(String, Double)]) -> Data {
        Data((#"{"time_last_update_unix":1785715200,"rates":{"# +
             pairs.map { #""\#($0.0)":\#($0.1)"# }.joined(separator: ",") + "}}").utf8)
    }
    private func currencyApi(_ pairs: [(String, Double)]) -> Data {
        Data((#"{"date":"2026-08-03","usd":{"# +
             pairs.map { #""\#($0.0.lowercased())":\#($0.1)"# }.joined(separator: ",") + "}}").utf8)
    }

    /// The common case must not get slower: everything covered by provider 1 means
    /// one request and no fallthrough.
    func test_firstProviderCoversEverything_asksOnce() async {
        let log = Log()
        let t = transport({ host, _ in
            host.contains("frankfurter") ? (self.frankfurter([("EUR", 0.87), ("JPY", 155)]), 200) : nil
        }, log: log)
        let (rows, missing) = await RateAutoUpdater.collect(codes: ["EUR", "JPY"], transport: t)
        XCTAssertEqual(log.calls.count, 1)
        XCTAssertEqual(rows.map(\.currency).sorted(), ["EUR", "JPY"])
        XCTAssertTrue(rows.allSatisfy { $0.source == "ECB" })
        XCTAssertTrue(missing.isEmpty)
    }

    /// The reported bug: provider 1 answers but omits a code. The next provider must
    /// be asked, and asked for the REMAINDER only.
    func test_partialCoverage_fallsThroughForTheRemainderOnly() async {
        let log = Log()
        let t = transport({ host, _ in
            if host.contains("frankfurter") { return (self.frankfurter([("EUR", 0.87)]), 200) }
            if host.contains("er-api") { return (self.erApi([("EUR", 0.87), ("BGN", 1.70)]), 200) }
            return nil
        }, log: log)
        let (rows, missing) = await RateAutoUpdater.collect(codes: ["EUR", "BGN"], transport: t)
        XCTAssertEqual(log.calls.count, 2)
        XCTAssertTrue(missing.isEmpty)
        // er-api was asked for BGN alone — EUR was already in hand.
        XCTAssertEqual(rows.first { $0.currency == "EUR" }?.source, "ECB")
        XCTAssertEqual(rows.first { $0.currency == "BGN" }?.source, "er-api")
        XCTAssertEqual(rows.count, 2)
    }

    /// A 422 naming one code must not cost the others their ECB rates, and the code
    /// itself must still reach a provider that has it.
    func test_rejectedCode_isDroppedAndRetried_thenPickedUpDownstream() async {
        let log = Log()
        let t = transport({ host, asked in
            if host.contains("frankfurter") {
                guard !asked.contains("VED") else {
                    return (Data(#"{"status":422,"message":"invalid currency: VED"}"#.utf8), 422)
                }
                return (self.frankfurter([("EUR", 0.87)]), 200)
            }
            if host.contains("er-api") { return (self.erApi([("EUR", 0.87)]), 200) }   // no VED
            // Offers EUR too — it must be ignored, because EUR is already in hand.
            return (self.currencyApi([("EUR", 0.87), ("VED", 210.0)]), 200)
        }, log: log)
        let (rows, missing) = await RateAutoUpdater.collect(codes: ["EUR", "VED"], transport: t)
        XCTAssertTrue(missing.isEmpty)
        XCTAssertEqual(rows.first { $0.currency == "EUR" }?.source, "ECB")        // recovered, not downgraded
        XCTAssertEqual(rows.first { $0.currency == "VED" }?.source, "currency-api")
        // Frankfurter asked twice: the full set, then the same set minus the code
        // its 422 named. Only Frankfurter encodes the codes in its URL — the other
        // two fetch everything and filter — so downstream "asked only for the
        // remainder" is observed through what they CONTRIBUTE, below.
        XCTAssertEqual(log.calls.filter { $0.host.contains("frankfurter") }.map(\.asked),
                       [["EUR", "VED"], ["EUR"]])
        XCTAssertEqual(rows.filter { $0.source == "currency-api" }.map(\.currency), ["VED"])
        XCTAssertEqual(rows.count, 2)                                            // no duplicate EUR
    }

    /// An unparseable rejection must fall through, not spin against the bound.
    func test_unrecoverableRejection_skipsProviderWithoutLooping() async {
        let log = Log()
        let t = transport({ host, _ in
            if host.contains("frankfurter") { return (Data("<html>502</html>".utf8), 502) }
            if host.contains("er-api") { return (self.erApi([("EUR", 0.87)]), 200) }
            return nil
        }, log: log)
        let (rows, missing) = await RateAutoUpdater.collect(codes: ["EUR"], transport: t)
        XCTAssertEqual(log.calls.filter { $0.host.contains("frankfurter") }.count, 1)
        XCTAssertEqual(rows.map(\.currency), ["EUR"])
        XCTAssertEqual(rows[0].source, "er-api")
        XCTAssertTrue(missing.isEmpty)
    }

    /// A provider returning MORE than was asked for must not have the extra written:
    /// parseFrankfurter trusts the server's `quotes=` filter and emits whatever came
    /// back, so the chain filters to the asked set itself.
    func test_providerReturningExtras_onlyTheAskedCodesAreKept() async {
        let log = Log()
        let t = transport({ host, _ in
            host.contains("frankfurter")
                ? (self.frankfurter([("EUR", 0.87), ("CHF", 0.80)]), 200)   // CHF unasked
                : nil
        }, log: log)
        let (rows, missing) = await RateAutoUpdater.collect(codes: ["EUR"], transport: t)
        XCTAssertEqual(rows.map(\.currency), ["EUR"])
        XCTAssertTrue(missing.isEmpty)
    }

    /// Nobody answers: report it rather than writing a stamp over an empty result.
    func test_everyProviderFails_reportsAllMissing() async {
        let log = Log()
        let t = transport({ _, _ in nil }, log: log)
        let (rows, missing) = await RateAutoUpdater.collect(codes: ["EUR", "JPY"], transport: t)
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(missing.sorted(), ["EUR", "JPY"])
        XCTAssertEqual(log.calls.count, RateAutoUpdater.providers.count)
    }

    /// A code no provider carries stays missing — and does NOT stop the others from
    /// being written, which is what `.partial` reports.
    func test_codeNobodyCarries_staysMissing_othersStillCollected() async {
        let log = Log()
        let t = transport({ host, _ in
            if host.contains("frankfurter") { return (self.frankfurter([("EUR", 0.87)]), 200) }
            if host.contains("er-api") { return (self.erApi([("EUR", 0.87)]), 200) }
            return (self.currencyApi([("EUR", 0.87)]), 200)
        }, log: log)
        let (rows, missing) = await RateAutoUpdater.collect(codes: ["EUR", "ZZZ"], transport: t)
        XCTAssertEqual(rows.map(\.currency), ["EUR"])
        XCTAssertEqual(missing, ["ZZZ"])
        XCTAssertEqual(log.calls.count, RateAutoUpdater.providers.count)
    }
}
