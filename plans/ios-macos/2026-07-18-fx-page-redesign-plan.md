# Exchange rates page redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Regroup the Exchange rates power tool by currency (latest rate both directions, tap → history with sparkline + deletes), move the auto-update controls there from Settings › Advanced, and add a "Refresh now" with visible feedback.

**Architecture:** FinchApp-only UI change. `RateAutoUpdater` gains a result-returning core `refresh(store:)` (outcome enum) that both the guarded `refreshIfDue` and the new manual button call. Pure grouping helpers (`fxCurrencies`/`fxLatest`/`fxSeries`/`fxDisplayDay`) live in `Common/FxDerive.swift` with unit tests. No FinchCore/engine/schema/web change; all writes stay on `setExchangeRate` / `deleteExchangeRate`.

**Tech Stack:** SwiftUI, existing `Sparkline` (Swift Charts) primitive, XCTest (FinchAppTests), xcodegen project generation.

**Design doc:** `plans/ios-macos/2026-07-18-fx-page-redesign-design.md` (authoritative).

## Global Constraints

- Worktree: `/tmp/finch-fxpage`, branch `feat/ios-fx-page`. All build/test commands run from `/tmp/finch-fxpage/ios` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- After creating any new source file, run `xcodegen generate` (project globs source dirs).
- Builds must pass for BOTH: FinchApp (`-destination 'platform=iOS Simulator,name=ios-finch2'`) and FinchMac (`CODE_SIGNING_ALLOWED=NO`).
- No `Co-Authored-By` trailer in commits. PR targets `feat/frontend`.
- Copy (exact strings): "Refresh now", "Updated %lld rates", "Nothing to update", "Couldn't reach frankfurter.dev. Check your connection and try again.", "Delete all %@ rates", "Auto-update exchange rates", "Last updated", footer "Fetches daily reference rates for your currencies from Frankfurter (frankfurter.dev, central-bank data). Only currency codes are sent."
- Rate semantics: stored `rate` = USD per 1 unit of `currency`; inverse (unit per USD) is display-only, guarded by `rate > 0` (else "—").

---

### Task 1: `RateAutoUpdater` — result-returning core

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Sync/RateAutoUpdater.swift`
- Test (existing, must stay green): `ios/FinchApp/Tests/FinchAppTests/RateAutoUpdaterTests.swift`

**Interfaces:**
- Consumes: existing `parse`, `isDue`, `currenciesInUse`, `toggleKey`, `stampKey`, `minInterval` (all unchanged).
- Produces: `enum RefreshOutcome: Equatable { case updated(Int); case failed; case skipped }` (file-scope, internal) and `@MainActor static func refresh(store: FinchStore) async -> RefreshOutcome` on `RateAutoUpdater`. Task 4's "Refresh now" calls `refresh`; `refreshIfDue(store:)` keeps its exact signature (FinchApp.swift trigger untouched).

- [ ] **Step 1: Refactor** — replace the body of `refreshIfDue` and add `RefreshOutcome` + `refresh`. The file's lines 15–33 (`refreshIfDue`) become:

```swift
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
        let codes = currenciesInUse(store: store)
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
```

and ABOVE the `enum RateAutoUpdater` declaration add:

```swift
/// What a fetch attempt did — drives "Refresh now" feedback (auto path discards it).
enum RefreshOutcome: Equatable {
    case updated(Int)   // wrote N rates; stamp written
    case failed         // URL/network/non-200/decode failure — nothing written
    case skipped        // no non-USD currencies in use — nothing to fetch
}
```

Everything else in the file (doc comment, keys, `parse`, `isDue`, `currenciesInUse`) stays byte-identical, except update the header comment's last line "Governed by Settings › Advanced → Auto-update exchange rates." to "Governed by the toggle on Power Tools › Exchange rates."

- [ ] **Step 2: Run the existing tests (behavior-preserving refactor — they must pass unchanged)**

Run (from `/tmp/finch-fxpage/ios`):
```bash
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/RateAutoUpdaterTests -quiet 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **` (3 tests).

- [ ] **Step 3: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Sync/RateAutoUpdater.swift
git commit -m "refactor(ios): RateAutoUpdater — result-returning refresh core for manual refresh"
```

---

### Task 2: `FxDerive` helpers + tests (TDD)

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Common/FxDerive.swift`
- Create: `ios/FinchApp/Tests/FinchAppTests/FxDeriveTests.swift`

**Interfaces:**
- Consumes: `FinchCore.ExchangeRate` (`date: String` ISO `yyyy-MM-dd`, `currency: String`, `rate: Double`, `source: String?`), `AppDate.isoDay`.
- Produces (file-scope internal funcs, used by Tasks 3–4):
  - `func fxCurrencies(_ rates: [ExchangeRate]) -> [String]`
  - `func fxLatest(_ rates: [ExchangeRate], _ currency: String) -> ExchangeRate?`
  - `func fxSeries(_ rates: [ExchangeRate], _ currency: String) -> [Double]`
  - `func fxDisplayDay(_ isoDay: String, withYear: Bool = false) -> String`

- [ ] **Step 1: Write the failing tests** — create `ios/FinchApp/Tests/FinchAppTests/FxDeriveTests.swift`:

```swift
import XCTest
@testable import FinchApp
import FinchCore

/// Pure grouping/derivation helpers behind the Exchange rates pages.
final class FxDeriveTests: XCTestCase {
    private let rates = [
        ExchangeRate(date: "2026-07-16", currency: "EUR", rate: 1.14, source: "ECB"),
        ExchangeRate(date: "2026-07-17", currency: "EUR", rate: 1.15, source: "ECB"),
        ExchangeRate(date: "2026-07-17", currency: "CAD", rate: 0.71, source: nil),
        ExchangeRate(date: "2026-07-15", currency: "EUR", rate: 1.13, source: "manual"),
    ]

    func test_currencies_sortedDeduped() {
        XCTAssertEqual(fxCurrencies(rates), ["CAD", "EUR"])
        XCTAssertEqual(fxCurrencies([]), [])
    }

    func test_latest_picksMaxDate_nilWhenAbsent() {
        XCTAssertEqual(fxLatest(rates, "EUR")?.rate, 1.15)
        XCTAssertEqual(fxLatest(rates, "CAD")?.rate, 0.71)
        XCTAssertNil(fxLatest(rates, "JPY"))
    }

    func test_latest_equalDates_laterRowInListOrderWins() {
        let dup = rates + [ExchangeRate(date: "2026-07-17", currency: "EUR", rate: 9.99, source: "manual")]
        XCTAssertEqual(fxLatest(dup, "EUR")?.rate, 9.99)
    }

    func test_series_dateAscending() {
        XCTAssertEqual(fxSeries(rates, "EUR"), [1.13, 1.14, 1.15])
        XCTAssertEqual(fxSeries(rates, "JPY"), [])
    }

    func test_displayDay_formats_andFallsBack() {
        // en_US-style abbreviated month-day; assert on components to stay locale-tolerant.
        let s = fxDisplayDay("2026-07-17")
        XCTAssertTrue(s.contains("17"))
        XCTAssertFalse(s.contains("2026"))
        XCTAssertTrue(fxDisplayDay("2026-07-17", withYear: true).contains("2026"))
        XCTAssertEqual(fxDisplayDay("garbage"), "garbage")
    }
}
```

- [ ] **Step 2: Run to verify failure** (file doesn't exist yet → compile error is the failure mode)

```bash
xcodegen generate && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/FxDeriveTests -quiet 2>&1 | tail -5
```
Expected: FAIL — `cannot find 'fxCurrencies' in scope` (and siblings).

- [ ] **Step 3: Implement** — create `ios/FinchApp/Sources/FinchApp/Common/FxDerive.swift`:

```swift
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
```

- [ ] **Step 4: Run to verify pass**

Same command as Step 2. Expected: `** TEST SUCCEEDED **` (5 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Common/FxDerive.swift ios/FinchApp/Tests/FinchAppTests/FxDeriveTests.swift
git commit -m "feat(ios): FxDerive — pure currency-grouping helpers for the FX pages (unit-tested)"
```

---

### Task 3: `ExchangeRateHistoryView` + shared `SourceBadge`

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/PowerTools/ExchangeRateHistoryView.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/PowerTools/ExchangeRatesView.swift` (only the `SourceBadge` access level — line 49: `private struct SourceBadge` → `struct SourceBadge`)

**Interfaces:**
- Consumes: `fxSeries`, `fxDisplayDay` (Task 2), `SourceBadge(source: String?)` (this task makes it internal), `Sparkline(values: [Double])` (`Common/ChartViews/Sparkline.swift`), `store.apply(.deleteExchangeRate, Args(["date": .string(...), "currency": .string(...)]))`, `errorAlert($errorMessage)`, `i18nMessage(error)`.
- Produces: `struct ExchangeRateHistoryView: View` with `init(currency: String)` — Task 4 links to it.

- [ ] **Step 1: Make `SourceBadge` internal** — in `ExchangeRatesView.swift` line 49 change:

```swift
private struct SourceBadge: View {
```
to
```swift
struct SourceBadge: View {
```

- [ ] **Step 2: Create the history view** — `ios/FinchApp/Sources/FinchApp/PowerTools/ExchangeRateHistoryView.swift`:

```swift
import SwiftUI
import FinchCore

/// One currency's full rate history: trend sparkline (shown at ≥3 points) above
/// date-descending rows. Per-row delete + "Delete all" go through the
/// deleteExchangeRate chokepoint; when the last row goes, pop back.
struct ExchangeRateHistoryView: View {
    let currency: String
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteAll = false
    @State private var errorMessage: String?

    private var rows: [ExchangeRate] {
        store.exchangeRates.filter { $0.currency == currency }.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            let series = fxSeries(store.exchangeRates, currency)
            if series.count >= 3 {
                Section {
                    Sparkline(values: series)
                        .frame(height: 48)
                }
            }
            Section {
                ForEach(rows, id: \.self) { rate in
                    HStack {
                        Text(fxDisplayDay(rate.date, withYear: true))
                        Spacer()
                        Text(String(format: "%.4f", rate.rate))
                        SourceBadge(source: rate.source)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(rate) } label: { Label("Delete", systemImage: "trash") }
                    }
                    .contextMenu {
                        Button(role: .destructive) { delete(rate) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
        .navigationTitle(currency)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) { showDeleteAll = true } label: {
                        Label("Delete all \(currency) rates", systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("More")
            }
        }
        .confirmationDialog("Delete all \(currency) rates", isPresented: $showDeleteAll, titleVisibility: .visible) {
            Button("Delete \(rows.count) rates", role: .destructive) { deleteAll() }
        }
        .errorAlert($errorMessage)
    }

    private func delete(_ r: ExchangeRate) {
        do {
            try store.apply(.deleteExchangeRate, Args(["date": .string(r.date), "currency": .string(r.currency)]))
            if rows.isEmpty { dismiss() }
        } catch { errorMessage = i18nMessage(error) }
    }

    private func deleteAll() {
        do {
            for r in rows {
                try store.apply(.deleteExchangeRate, Args(["date": .string(r.date), "currency": .string(r.currency)]))
            }
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
```

- [ ] **Step 3: Build iOS** (view is unreferenced until Task 4 — a compile check is the test here; its behavior is sim-verified in Task 5):

```bash
xcodegen generate && xcodebuild -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -quiet build 2>&1 | grep -E "BUILD|error:" ; echo done
```
Expected: no `error:` lines (silent `-quiet` success), `done`.

- [ ] **Step 4: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/PowerTools/ExchangeRateHistoryView.swift ios/FinchApp/Sources/FinchApp/PowerTools/ExchangeRatesView.swift
git commit -m "feat(ios): ExchangeRateHistoryView — per-currency history with sparkline + deletes"
```

---

### Task 4: Summary page rework + Settings removal

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/PowerTools/ExchangeRatesView.swift` (replace the `ExchangeRatesView` struct — lines 1–46 of the file; `SourceBadge`, `fxSources`, `AddExchangeRateSheet` stay untouched)
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift` (delete the "Exchange rates" Section, lines 225–234, and `exchangeAutoUpdateBinding`, lines 285–291)

**Interfaces:**
- Consumes: `RefreshOutcome` + `RateAutoUpdater.refresh(store:)` (Task 1), `fxCurrencies`/`fxLatest`/`fxDisplayDay` (Task 2), `ExchangeRateHistoryView(currency:)` (Task 3), `SourceBadge`, `AddExchangeRateSheet` (unchanged), `AppDate.h24Locale`.
- Produces: the final `ExchangeRatesView`; nothing downstream.

- [ ] **Step 1: Replace `ExchangeRatesView`** — the whole struct (file lines 1–46) becomes:

```swift
import SwiftUI
import FinchCore

/// Phase 4 (FX tools) — the FX home. Auto-update controls (moved here from
/// Settings › Advanced in the page redesign), manual "Refresh now", and rates
/// grouped one-row-per-currency (latest rate, both directions); history and
/// deletes live in ExchangeRateHistoryView. Writes stay on the
/// setExchangeRate / deleteExchangeRate chokepoints.
struct ExchangeRatesView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var showingAdd = false
    @State private var errorMessage: String?
    @State private var refreshing = false
    @State private var lastUpdated: Date?
    @State private var refreshNote: LocalizedStringKey?

    var body: some View {
        List {
            Section {
                Toggle("Auto-update exchange rates", isOn: autoUpdateBinding)
                if let lastUpdated {
                    LabeledContent("Last updated", value: lastUpdated.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppDate.h24Locale)))
                }
                Button { refreshNow() } label: {
                    HStack {
                        Text("Refresh now")
                        Spacer()
                        if refreshing {
                            ProgressView()
                        } else if let refreshNote {
                            Text(refreshNote).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(refreshing)
            } footer: {
                Text("Fetches daily reference rates for your currencies from Frankfurter (frankfurter.dev, central-bank data). Only currency codes are sent.")
            }

            Section("Rates") {
                if store.exchangeRates.isEmpty {
                    Text("No exchange rates. USD is the hub (rate 1).").foregroundStyle(.secondary)
                }
                ForEach(fxCurrencies(store.exchangeRates), id: \.self) { code in
                    if let latest = fxLatest(store.exchangeRates, code) {
                        NavigationLink {
                            ExchangeRateHistoryView(currency: code)
                        } label: {
                            currencyRow(code: code, latest: latest)
                        }
                    }
                }
            }
        }
        .navigationTitle("Exchange rates")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add rate")
            }
        }
        .sheet(isPresented: $showingAdd) { AddExchangeRateSheet() }
        .errorAlert($errorMessage)
        .onAppear { lastUpdated = UserDefaults.standard.object(forKey: RateAutoUpdater.stampKey) as? Date }
    }

    /// Latest rate both ways: primary = stored USD-per-unit, caption = inverse.
    private func currencyRow(code: String, latest: ExchangeRate) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(code).fontWeight(.medium)
                SourceBadge(source: latest.source)
            }
            Text("1 \(code) = \(String(format: "%.4f", latest.rate)) USD")
            Text("1 USD = \(inverseText(latest.rate)) \(code) · \(fxDisplayDay(latest.date))")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func inverseText(_ rate: Double) -> String {
        rate > 0 ? String(format: "%.4f", 1.0 / rate) : "—"
    }

    /// A deliberate manual act — bypasses toggle + throttle (RateAutoUpdater.refresh).
    private func refreshNow() {
        refreshing = true
        refreshNote = nil
        Task {
            let outcome = await RateAutoUpdater.refresh(store: store)
            refreshing = false
            lastUpdated = UserDefaults.standard.object(forKey: RateAutoUpdater.stampKey) as? Date
            switch outcome {
            case .updated(let n): refreshNote = "Updated \(n) rates"
            case .skipped: refreshNote = "Nothing to update"
            case .failed: errorMessage = String(localized: "Couldn't reach frankfurter.dev. Check your connection and try again.")
            }
        }
    }

    /// Absent key == ON (default-ON semantics shared with RateAutoUpdater).
    private var autoUpdateBinding: Binding<Bool> {
        Binding(
            get: { UserDefaults.standard.object(forKey: RateAutoUpdater.toggleKey) == nil
                   || UserDefaults.standard.bool(forKey: RateAutoUpdater.toggleKey) },
            set: { UserDefaults.standard.set($0, forKey: RateAutoUpdater.toggleKey) })
    }
}
```

(The old `delete(_:)` helper and per-row swipe/context delete disappear from this view — deletes now live in the history page.)

- [ ] **Step 2: Remove the Settings section** — in `SettingsTab.swift` delete lines 225–234:

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

and the now-unused binding (lines 285–291 plus its doc comment):

```swift
    /// Absent key == ON (default-ON semantics shared with RateAutoUpdater).
    private var exchangeAutoUpdateBinding: Binding<Bool> {
        Binding(
            get: { UserDefaults.standard.object(forKey: RateAutoUpdater.toggleKey) == nil
                   || UserDefaults.standard.bool(forKey: RateAutoUpdater.toggleKey) },
            set: { UserDefaults.standard.set($0, forKey: RateAutoUpdater.toggleKey) })
    }
```

Verify no other `exchangeAutoUpdateBinding` references remain: `grep -rn exchangeAutoUpdateBinding ios/FinchApp` → no matches.

- [ ] **Step 3: Build iOS**

```bash
xcodebuild -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -quiet build 2>&1 | grep -E "BUILD|error:" ; echo done
```
Expected: no `error:` lines, `done`.

- [ ] **Step 4: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/PowerTools/ExchangeRatesView.swift ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift
git commit -m "feat(ios): Exchange rates page — grouped by currency, FX controls moved here, Refresh now"
```

---

### Task 5: Verification (controller)

- [ ] Full unit suite: `xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests -quiet 2>&1 | tail -3` → `** TEST SUCCEEDED **` (162 existing + 5 new).
- [ ] macOS build: `xcodebuild -project FinchApp.xcodeproj -scheme FinchMac CODE_SIGNING_ALLOWED=NO -quiet build 2>&1 | grep -E "BUILD|error:" ; echo done` → no errors.
- [ ] Sim (ios-finch2): install + launch. Power Tools › Exchange rates shows the Auto-update section (toggle, Last updated, Refresh now) and one row per currency with both directions + source badge. Tap Refresh now → spinner → "Updated N rates", DB gains today's rows (`sqlite3 <container>/Library/Application Support/finch.sqlite3 "SELECT date,currency,rate,source FROM exchange_rates ORDER BY date DESC"`), stamp row updates. Toggle OFF → Refresh now still fetches. Tap EUR → history renders (sparkline only if ≥3 rows); swipe-delete a row; ⋯ → Delete all → confirm → pops back and currency row gone. Settings › Advanced no longer shows an Exchange rates section.
- [ ] Screenshot the reworked page for the PR if it adds clarity.

---

## Self-review notes

- Spec coverage: decisions 1–5 map to Tasks 4 / 1+4 / 3 / 4(`currencyRow`) / 3(Delete all, no pruning). Helpers + tests = Task 2. Settings removal = Task 4. ✓
- `refreshNote` as `LocalizedStringKey?` keeps "Updated %lld rates"/"Nothing to update" localizable via interpolated Text keys. ✓
- Type consistency: `RefreshOutcome` cases used in Task 4 match Task 1; helper names in Tasks 3–4 match Task 2 signatures. ✓
- zh-Hans: new strings listed in Global Constraints join the accumulated batch (separate effort, not this PR).
