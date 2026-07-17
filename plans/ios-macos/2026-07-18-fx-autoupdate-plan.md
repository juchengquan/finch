# FX auto-update — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (or executing-plans). Checkbox steps. Design doc beside this is authoritative (semantics: store the INVERSE of Frankfurter's quote-per-USD).

**Goal:** Daily auto-refresh of in-use exchange rates from Frankfurter v2, opt-in toggle default ON, written via `setExchangeRate`, silent offline. No engine change.

## Global Constraints
- Builds: FinchApp (iOS) + FinchMac (macOS) `** BUILD SUCCEEDED **`; new unit tests green, existing suites unbroken. No `Co-Authored-By`. No FinchCore/web changes. PR → `feat/frontend`.

---

### Task 1: `RateAutoUpdater` + unit tests

**Files:** Create `ios/FinchApp/Sources/FinchApp/Sync/RateAutoUpdater.swift`; Create `ios/FinchApp/Tests/FinchAppTests/RateAutoUpdaterTests.swift`.

- [ ] **Step 1 — service:**

```swift
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
        set.formUnion(store.ledgers.compactMap { $0.base })
        set.formUnion(store.exchangeRates.map { $0.currency })
        set.remove("USD")
        return set.sorted()
    }
}
```
(Verify `LedgerRow`'s base property name — `base` per CLAUDE/state; adjust `$0.base` if it's `baseCurrency`. `ExchangeRate.currency` exists.)

- [ ] **Step 2 — tests** (mirror suite idioms; no network in tests):

```swift
import XCTest
@testable import FinchApp

final class RateAutoUpdaterTests: XCTestCase {
    func test_parse_invertsQuotePerUSD_dropsUSDAndInvalid() throws {
        let json = #"[{"date":"2026-07-17","base":"USD","quote":"EUR","rate":0.87241},{"date":"2026-07-17","base":"USD","quote":"USD","rate":1},{"date":"2026-07-17","base":"USD","quote":"BAD","rate":0}]"#
        let rows = RateAutoUpdater.parse(Data(json.utf8))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].currency, "EUR")
        XCTAssertEqual(rows[0].ratePerUSD, 1.146296, accuracy: 0.000001)
    }
    func test_parse_malformed_returnsEmpty() {
        XCTAssertTrue(RateAutoUpdater.parse(Data("nope".utf8)).isEmpty)
    }
    func test_isDue_throttle() {
        XCTAssertTrue(RateAutoUpdater.isDue(now: Date(), last: nil))
        XCTAssertFalse(RateAutoUpdater.isDue(now: Date(), last: Date().addingTimeInterval(-3600)))
        XCTAssertTrue(RateAutoUpdater.isDue(now: Date(), last: Date().addingTimeInterval(-21*3600)))
    }
}
```
(`parse`/`isDue` are @MainActor-neutral statics — if the enum's @MainActor annotation makes the test await, either annotate tests @MainActor or move the pure funcs outside the actor; keep them pure.)

- [ ] **Step 3:** run the new tests (+ don't break others); build iOS. Commit both files: `feat(ios): RateAutoUpdater — daily Frankfurter FX refresh (parse/throttle unit-tested)`.

---

### Task 2: Trigger + Settings toggle

**Files:** Modify `ios/FinchApp/Sources/FinchApp/FinchApp.swift`, `ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift`.

- [ ] **Step 1 — trigger:** in the `scenePhase` `.active` branch (FinchApp.swift ~line 89, next to `gate.didBecomeActive()`), add (mirroring the Spotlight lock-gating nearby):

```swift
                    if !gate.isLocked { Task { await RateAutoUpdater.refreshIfDue(store: store) } }
```

- [ ] **Step 2 — Settings › Advanced:** in `SettingsAdvancedView`'s `List`, add before the "Database" section:

```swift
            Section {
                Toggle("Auto-update exchange rates", isOn: exchangeAutoUpdateBinding)
                if let last = UserDefaults.standard.object(forKey: RateAutoUpdater.stampKey) as? Date {
                    LabeledContent("Last updated", value: last.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppDate.h24Locale)))
                }
            } header: {
                Text("Exchange rates")
            } footer: {
                Text("Fetches daily reference rates for your currencies from Frankfurter (frankfurter.dev, central-bank data). Only currency codes are sent.")
            }
```
with a computed binding honoring default-ON:

```swift
    private var exchangeAutoUpdateBinding: Binding<Bool> {
        Binding(
            get: { UserDefaults.standard.object(forKey: RateAutoUpdater.toggleKey) == nil
                   || UserDefaults.standard.bool(forKey: RateAutoUpdater.toggleKey) },
            set: { UserDefaults.standard.set($0, forKey: RateAutoUpdater.toggleKey) })
    }
```

- [ ] **Step 3:** build BOTH platforms; commit: `feat(ios): FX auto-update trigger on foreground + Settings toggle (default on)`.

---

### Task 3: Verification (controller)
- [ ] Unit tests green; both builds. Sim (ios-finch2, has network): clear stamp → foreground the app → `sqlite3`: `SELECT date,currency,rate,source FROM exchange_rates ORDER BY date DESC` gains today's EUR row, `source='ECB'`, rate ≈ 1.14–1.15 (inverse sanity). Toggle OFF in Settings → clear stamp → relaunch → no new row. Toggle back ON. Screenshot the Settings section.

---

## Self-review notes
- Default-ON via absent-key semantics (`object(forKey:) == nil`) consistently in service + binding. ✓
- Silent failure paths: toggle off, throttled, empty set, bad URL, network error, non-200, decode failure — each returns without side effects; stamp only on success. ✓
- Manual entries win by being later upserts on the same (date,currency) key — no clobber semantics beyond that (documented). ✓
- New strings ("Auto-update exchange rates", footer, "Last updated" exists) → zh batch note. ✓
