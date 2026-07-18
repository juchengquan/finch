# Currencies page (round 2) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the FX page a top-level Settings "Currencies" page listing all 145 ISO currencies (code / name+sign, rate, tracking toggle), where the toggle set drives what the daily auto-update fetches.

**Architecture:** One new native-first FinchCore app_state action (`setTrackedCurrencies`, global key `fxTrackedCurrencies`, mirroring `setBudgetOrder`) + projection + store wiring. Pure helpers (`fxEffectiveTracked`, `FxCurrencyInfo`, `fxCurrencyRows`/`fxFilterRows`) carry the semantics and are unit-tested; the view rework (`ExchangeRatesView` → `CurrenciesView`) is thin. `RateAutoUpdater.refresh` fetches the effective tracked set.

**Tech Stack:** SwiftUI, GRDB (FinchCore), XCTest (FinchCoreTests + FinchAppTests), xcodegen.

**Design doc:** `plans/ios-macos/2026-07-18-currencies-page-design.md` (authoritative).

## Global Constraints

- Worktree `/tmp/finch-cur`, branch `feat/ios-currencies`. Commands run from `/tmp/finch-cur/ios` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Run `xcodegen generate` after creating/renaming any source file.
- Builds must pass for BOTH FinchApp (`-destination 'platform=iOS Simulator,name=ios-finch2'`) and FinchMac (`CODE_SIGNING_ALLOWED=NO`). No `Co-Authored-By`. PR → `feat/frontend`.
- No table-schema change; `Schema.version` and `packFormatVersion` untouched (app_state is schema-free). No web change.
- Rate semantics: stored `rate` = USD per 1 unit; USD is the hub (never stored, never toggleable).
- Copy (exact): "Currencies", "Track %@" (a11y), "No rates yet.", hub caption suffix "· hub". Auto-update section strings carry over from #492 unchanged.

---

### Task 1: FinchCore — `setTrackedCurrencies` action + projection (TDD)

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/ActionName.swift` (app_state cases block, ~line 110)
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Domain/App.swift` (handlers map ~line 8; new handler after `setBudgetOrder` ~line 93)
- Modify: `ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift` (after `budgetOrderByLedger`, ~line 93)
- Create: `ios/FinchCore/Tests/FinchCoreTests/TrackedCurrenciesTests.swift`

**Interfaces:**
- Consumes: `AppDomain.setAppState/getAppState`, `Args.to(_:)`, `Apply.apply(dbQueue:action:args:)`, `TestSeed.base()` (existing test seed).
- Produces: `ActionName.setTrackedCurrencies` (raw value `"setTrackedCurrencies"`, args `{codes: [String]}` — trimmed/uppercased/de-duped/sorted, USD + empties dropped, stored as JSON array under `app_state.fxTrackedCurrencies`) and `Projection.trackedCurrencies(dbQueue:) throws -> [String]?` (**nil when key absent** — distinct from empty). Tasks 2/5 rely on both.

- [ ] **Step 1: Write the failing test** — create `ios/FinchCore/Tests/FinchCoreTests/TrackedCurrenciesTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

/// setTrackedCurrencies persists the global FX auto-update fetch list into
/// app_state.fxTrackedCurrencies; the projection reads it back (nil when the
/// key was never written — seeded-default mode).
final class TrackedCurrenciesTests: XCTestCase {
    func test_setTrackedCurrencies_roundTrips_normalizes_andDistinguishesAbsentFromEmpty() throws {
        let q = try TestSeed.base()
        XCTAssertNil(try Projection.trackedCurrencies(dbQueue: q))   // absent ≠ []

        // normalizes: trims, uppercases, drops USD + empties, de-dups, sorts
        try Apply.apply(dbQueue: q, action: "setTrackedCurrencies",
                        args: Args(["codes": .array([.string(" eur "), .string("JPY"), .string("eur"), .string("USD"), .string("")])]))
        XCTAssertEqual(try Projection.trackedCurrencies(dbQueue: q), ["EUR", "JPY"])

        // empty list is stored and read back as [], not nil
        try Apply.apply(dbQueue: q, action: "setTrackedCurrencies", args: Args(["codes": .array([])]))
        XCTAssertEqual(try Projection.trackedCurrencies(dbQueue: q), [])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodegen generate && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchCoreTests/TrackedCurrenciesTests 2>&1 | grep -E "error:|TEST " | head -5
```
Expected: FAIL — `type 'ActionName' has no member 'setTrackedCurrencies'` / unknown action.

- [ ] **Step 3: Implement.** In `ActionName.swift`, extend the app_state block (keep the comment style; the `(6)` count becomes `(7)`):

```swift
    // --- app_state (7) ---
    case setMobileTabIds
    case setDisplayCurrency
    case setBudgetOrder       // native-first (per-ledger manual budget order; the web ignores the key until it adopts it)
    case setTrackedCurrencies // native-first (global FX auto-update fetch list; the web ignores the key until it adopts it)
    case setBackupFrequency
    case setBackupRetention
    case reset
```

In `App.swift`, add to the `handlers` map after `.setBudgetOrder: setBudgetOrder,`:

```swift
        .setTrackedCurrencies: setTrackedCurrencies,
```

and add the handler after `setBudgetOrder` (before `setBackupFrequency`):

```swift
    static func setTrackedCurrencies(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let codes: [String] }
        let codes = try args.to(A.self).codes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty && $0 != "USD" }
        let unique = Array(Set(codes)).sorted()
        try setAppState(db, "fxTrackedCurrencies", String(data: try JSONEncoder().encode(unique), encoding: .utf8) ?? "[]")
    }
```

In `Projections+State.swift`, add after `budgetOrderByLedger`:

```swift
    /// The global FX auto-update fetch list (`app_state.fxTrackedCurrencies`).
    /// Nil when the key is absent (seeded-default mode) — distinct from empty.
    public static func trackedCurrencies(dbQueue: DatabaseQueue) throws -> [String]? {
        try dbQueue.read { db in
            guard let raw = try String.fetchOne(db, sql: "SELECT value FROM app_state WHERE key = 'fxTrackedCurrencies'"),
                  let data = raw.data(using: .utf8),
                  let list = try? JSONDecoder().decode([String].self, from: data) else { return nil }
            return list
        }
    }
```

- [ ] **Step 4: Run to verify it passes** — same command as Step 2. Expected: `** TEST SUCCEEDED **` (1 test). Also run the full FinchCoreTests once (`-only-testing:FinchCoreTests`) — no regressions.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Store/ActionName.swift ios/FinchCore/Sources/FinchCore/Store/Domain/App.swift ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift ios/FinchCore/Tests/FinchCoreTests/TrackedCurrenciesTests.swift
git commit -m "feat(core): setTrackedCurrencies — global FX fetch list in app_state (native-first)"
```

---

### Task 2: Store wiring + effective-set resolution; `RateAutoUpdater` fetches it (TDD)

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/FinchStore.swift` (internal vars block ~line 70; projection block ~lines 220–228)
- Modify: `ios/FinchApp/Sources/FinchApp/Common/FxDerive.swift` (append)
- Modify: `ios/FinchApp/Sources/FinchApp/Sync/RateAutoUpdater.swift` (`refresh`'s first line)
- Modify: `ios/FinchApp/Tests/FinchAppTests/FxDeriveTests.swift` (append)

**Interfaces:**
- Consumes: `Projection.trackedCurrencies(dbQueue:)` (Task 1), `RateAutoUpdater.currenciesInUse(store:)` (existing).
- Produces: `FinchStore.trackedCurrencies: [String]?` (internal var, refreshed on every reproject) and `func fxEffectiveTracked(stored: [String]?, fallback: [String]) -> [String]` — Task 5's view and `RateAutoUpdater.refresh` use both.

- [ ] **Step 1: Write the failing test** — append to `FxDeriveTests.swift` (inside the existing `FxDeriveTests` class):

```swift
    func test_effectiveTracked_absentFallsBack_emptyIsRespected() {
        XCTAssertEqual(fxEffectiveTracked(stored: nil, fallback: ["CAD", "EUR"]), ["CAD", "EUR"])
        XCTAssertEqual(fxEffectiveTracked(stored: [], fallback: ["CAD", "EUR"]), [])   // user untracked everything
        XCTAssertEqual(fxEffectiveTracked(stored: ["JPY"], fallback: ["CAD", "EUR"]), ["JPY"])
    }
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/FxDeriveTests 2>&1 | grep -E "error:|TEST " | head -4
```
Expected: FAIL — `cannot find 'fxEffectiveTracked' in scope`.

- [ ] **Step 3: Implement.** Append to `FxDerive.swift`:

```swift
/// The FX auto-update fetch list: the user's explicit tracked set when the
/// app_state key exists (even empty = untracked everything), else the seeded
/// default (currencies in use).
func fxEffectiveTracked(stored: [String]?, fallback: [String]) -> [String] {
    stored ?? fallback
}
```

In `FinchStore.swift`, after `var budgetOrderByLedger: [String: [String]] = [:]   // per-ledger manual budget order (app_state)` add:

```swift
    var trackedCurrencies: [String]?                    // global FX auto-update fetch list (app_state); nil = seeded default
```

In the projection block, after `let budgetOrderByLedger = try Projection.budgetOrderByLedger(dbQueue: q)` add:

```swift
            let trackedCurrencies = try Projection.trackedCurrencies(dbQueue: q)
```

and after `self.budgetOrderByLedger = budgetOrderByLedger` add:

```swift
            self.trackedCurrencies = trackedCurrencies
```

In `RateAutoUpdater.swift`, `refresh(store:)`'s first line changes from:

```swift
        let codes = currenciesInUse(store: store)
```
to:
```swift
        let codes = fxEffectiveTracked(stored: store.trackedCurrencies, fallback: currenciesInUse(store: store))
```
(`currenciesInUse` stays — it is the fallback provider and the seed for the first toggle write.)

- [ ] **Step 4: Run to verify pass** — same command as Step 2 plus `-only-testing:FinchAppTests/RateAutoUpdaterTests`. Expected: both `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/FinchStore.swift ios/FinchApp/Sources/FinchApp/Common/FxDerive.swift ios/FinchApp/Sources/FinchApp/Sync/RateAutoUpdater.swift ios/FinchApp/Tests/FinchAppTests/FxDeriveTests.swift
git commit -m "feat(ios): effective tracked-currency set drives the FX auto-update fetch"
```

---

### Task 3: `FxCurrencyInfo` — localized names & signs, cached (TDD)

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Common/FxCurrencyInfo.swift`
- Create: `ios/FinchApp/Tests/FinchAppTests/FxCurrencyInfoTests.swift`

**Interfaces:**
- Consumes: Foundation `Locale` only.
- Produces: `@MainActor enum FxCurrencyInfo` with `static func name(_ code: String) -> String`, `static func symbol(_ code: String) -> String?`, `static func label(_ code: String) -> String` ("Euro (€)"; no bracket when no distinct symbol). Tasks 4–5 use `label`.

- [ ] **Step 1: Write the failing test** — create `ios/FinchApp/Tests/FinchAppTests/FxCurrencyInfoTests.swift`:

```swift
import XCTest
@testable import FinchApp

/// Localized currency names + signs (cached). @MainActor per suite idiom.
@MainActor
final class FxCurrencyInfoTests: XCTestCase {
    func test_name_localizedWithCodeFallback() {
        XCTAssertNotEqual(FxCurrencyInfo.name("EUR"), "EUR")   // a real localized name exists
        XCTAssertEqual(FxCurrencyInfo.name("ZZZ"), "ZZZ")      // bogus code falls back to itself
    }
    func test_symbol_shortestDistinct_orNil() {
        XCTAssertEqual(FxCurrencyInfo.symbol("USD"), "$")
        XCTAssertEqual(FxCurrencyInfo.symbol("EUR"), "€")
        XCTAssertNil(FxCurrencyInfo.symbol("ZZZ"))
    }
    func test_label_composition_andRepeatIsCached() {
        XCTAssertEqual(FxCurrencyInfo.label("EUR"), "\(FxCurrencyInfo.name("EUR")) (€)")
        XCTAssertEqual(FxCurrencyInfo.label("ZZZ"), "ZZZ")     // no bracket without a distinct symbol
        XCTAssertEqual(FxCurrencyInfo.label("EUR"), FxCurrencyInfo.label("EUR"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodegen generate && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/FxCurrencyInfoTests 2>&1 | grep -E "error:|TEST " | head -4
```
Expected: FAIL — `cannot find 'FxCurrencyInfo' in scope`.

- [ ] **Step 3: Implement** — create `ios/FinchApp/Sources/FinchApp/Common/FxCurrencyInfo.swift`:

```swift
import Foundation

/// Localized currency names + signs for the Currencies page. The symbol table
/// is built once by scanning available locales (shortest distinct symbol per
/// code wins — "€", not "EUR"); labels are memoized per code so 145-row list
/// refreshes and search keystrokes don't re-hit Locale.
@MainActor
enum FxCurrencyInfo {
    private static var labelCache: [String: String] = [:]

    private static let symbolByCode: [String: String] = {
        var best: [String: String] = [:]
        for id in Locale.availableIdentifiers {
            let loc = Locale(identifier: id)
            guard let code = loc.currency?.identifier, let sym = loc.currencySymbol else { continue }
            if sym == code { continue }   // "CHF" as its own symbol is not a sign
            if let cur = best[code], cur.count <= sym.count { continue }
            best[code] = sym
        }
        return best
    }()

    static func name(_ code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }

    static func symbol(_ code: String) -> String? {
        symbolByCode[code.uppercased()]
    }

    /// "Euro (€)" — bracket omitted when no distinct symbol exists.
    static func label(_ code: String) -> String {
        if let hit = labelCache[code] { return hit }
        let n = name(code)
        let l = symbol(code).map { "\(n) (\($0))" } ?? n
        labelCache[code] = l
        return l
    }
}
```

- [ ] **Step 4: Run to verify pass** — same command as Step 2. Expected: `** TEST SUCCEEDED **` (3 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Common/FxCurrencyInfo.swift ios/FinchApp/Tests/FinchAppTests/FxCurrencyInfoTests.swift
git commit -m "feat(ios): FxCurrencyInfo — cached localized currency names + signs"
```

---

### Task 4: Row models — `fxCurrencyRows` / `fxFilterRows` (TDD)

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Common/FxDerive.swift` (append)
- Modify: `ios/FinchApp/Tests/FinchAppTests/FxDeriveTests.swift` (append a new class)

**Interfaces:**
- Consumes: `fxLatest` (existing), `FxCurrencyInfo.label` (Task 3), `FinchCore.ExchangeRate`.
- Produces: `struct FxCurrencyRow: Equatable { let code: String; let label: String; let rate: Double?; let tracked: Bool; let isHub: Bool }`, `@MainActor func fxCurrencyRows(all: [String], rates: [ExchangeRate], tracked: [String]) -> [FxCurrencyRow]` (USD hub first with rate 1.0, then tracked A–Z, then the rest A–Z), `func fxFilterRows(_ rows: [FxCurrencyRow], query: String) -> [FxCurrencyRow]`. Task 5's view iterates these.

- [ ] **Step 1: Write the failing test** — append to `FxDeriveTests.swift` as a NEW class (main-actor because rows use `FxCurrencyInfo`):

```swift
/// Currencies-page row models: ordering (hub → tracked A–Z → rest A–Z) + search.
@MainActor
final class FxCurrencyRowsTests: XCTestCase {
    private let rates = [
        ExchangeRate(date: "2026-07-17", currency: "EUR", rate: 1.15, source: "ECB"),
    ]

    func test_rows_hubFirst_thenTrackedAZ_thenRestAZ_withRates() {
        let rows = fxCurrencyRows(all: ["JPY", "EUR", "USD", "CAD", "AED"], rates: rates, tracked: ["JPY", "EUR"])
        XCTAssertEqual(rows.map(\.code), ["USD", "EUR", "JPY", "AED", "CAD"])
        XCTAssertTrue(rows[0].isHub)
        XCTAssertEqual(rows[0].rate, 1.0)
        XCTAssertFalse(rows[0].tracked)
        XCTAssertEqual(rows[1].rate, 1.15)          // EUR has a stored rate
        XCTAssertTrue(rows[1].tracked)
        XCTAssertNil(rows[2].rate)                  // JPY tracked but no rate yet
        XCTAssertFalse(rows[3].tracked)
    }

    func test_filter_byCodeOrName_caseInsensitive_orderPreserved() {
        let rows = fxCurrencyRows(all: ["JPY", "EUR", "USD", "CAD"], rates: rates, tracked: ["EUR"])
        XCTAssertEqual(fxFilterRows(rows, query: "").map(\.code), rows.map(\.code))
        XCTAssertEqual(fxFilterRows(rows, query: "eur").map(\.code), ["EUR"])
        XCTAssertEqual(fxFilterRows(rows, query: "yen").map(\.code), ["JPY"])   // matches localized name
        XCTAssertTrue(fxFilterRows(rows, query: "zzzzz").isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/FxCurrencyRowsTests 2>&1 | grep -E "error:|TEST " | head -4
```
Expected: FAIL — `cannot find 'fxCurrencyRows' in scope`.

- [ ] **Step 3: Implement** — append to `FxDerive.swift`:

```swift
/// One row of the Currencies page.
struct FxCurrencyRow: Equatable {
    let code: String
    let label: String     // "Euro (€)" via FxCurrencyInfo
    let rate: Double?     // latest stored USD-per-unit; 1.0 for the hub; nil = none
    let tracked: Bool
    let isHub: Bool       // USD — pinned first, no toggle
}

/// USD hub first, then tracked A–Z, then the rest A–Z.
@MainActor
func fxCurrencyRows(all: [String], rates: [ExchangeRate], tracked: [String]) -> [FxCurrencyRow] {
    let trackedSet = Set(tracked)
    let codes = all.sorted()
    func row(_ code: String, tracked: Bool) -> FxCurrencyRow {
        FxCurrencyRow(code: code, label: FxCurrencyInfo.label(code),
                      rate: fxLatest(rates, code)?.rate, tracked: tracked, isHub: false)
    }
    var rows = [FxCurrencyRow(code: "USD", label: FxCurrencyInfo.label("USD"),
                              rate: 1.0, tracked: false, isHub: true)]
    rows += codes.filter { $0 != "USD" && trackedSet.contains($0) }.map { row($0, tracked: true) }
    rows += codes.filter { $0 != "USD" && !trackedSet.contains($0) }.map { row($0, tracked: false) }
    return rows
}

/// Case-insensitive search over code or label; empty query passes everything through.
func fxFilterRows(_ rows: [FxCurrencyRow], query: String) -> [FxCurrencyRow] {
    let q = query.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return rows }
    return rows.filter { $0.code.localizedCaseInsensitiveContains(q) || $0.label.localizedCaseInsensitiveContains(q) }
}
```

- [ ] **Step 4: Run to verify pass** — same command as Step 2. Expected: `** TEST SUCCEEDED **` (2 tests). (If `test_filter_byCodeOrName…` fails on "yen" because the test runner's locale isn't English, relax that assertion to query `"JP"` — name matching is locale-dependent by design.)

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Common/FxDerive.swift ios/FinchApp/Tests/FinchAppTests/FxDeriveTests.swift
git commit -m "feat(ios): Currencies-page row models — hub/tracked/rest ordering + search filter"
```

---

### Task 5: `CurrenciesView` + Settings rewiring + history empty state

**Files:**
- Rename: `git mv ios/FinchApp/Sources/FinchApp/PowerTools/ExchangeRatesView.swift ios/FinchApp/Sources/FinchApp/PowerTools/CurrenciesView.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/PowerTools/CurrenciesView.swift` (replace the `ExchangeRatesView` struct; `SourceBadge`, `fxSources`, `AddExchangeRateSheet` in the same file stay untouched)
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift` (root list ~line 137: add Currencies row; `SettingsPowerToolsView` ~line 141: drop the Exchange rates link)
- Modify: `ios/FinchApp/Sources/FinchApp/PowerTools/ExchangeRateHistoryView.swift` (empty state)

**Interfaces:**
- Consumes: `fxCurrencyRows`/`fxFilterRows` (Task 4), `fxEffectiveTracked` (Task 2), `FxCurrencyInfo` (Task 3), `ActionName.setTrackedCurrencies` (Task 1), `RateAutoUpdater.refresh/currenciesInUse/stampKey/toggleKey`, `Currencies.iso`, `ExchangeRateHistoryView(currency:)`, `fxLatest`.
- Produces: `struct CurrenciesView: View` (replaces `ExchangeRatesView` everywhere — grep must find no remaining references).

- [ ] **Step 1: Rename file** — `git mv` as above, then in the file replace the header comment + struct declaration. The struct `ExchangeRatesView` (from #492) is replaced in full by:

```swift
/// Settings › Currencies — the FX home. Auto-update controls on top (master
/// toggle, last-updated, manual refresh), then ALL ISO currencies (hub first,
/// tracked A–Z, rest A–Z, searchable): code + localized name (sign), latest
/// USD-per-unit rate, and a tracking toggle that drives what the daily
/// Frankfurter fetch requests. Tap → per-currency history. Writes stay on the
/// setExchangeRate / deleteExchangeRate / setTrackedCurrencies chokepoints.
struct CurrenciesView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var showingAdd = false
    @State private var errorMessage: String?
    @State private var refreshing = false
    @State private var lastUpdated: Date?
    @State private var refreshNote: LocalizedStringKey?
    @State private var query = ""

    /// The user's explicit tracked set, or the seeded default before first toggle.
    private var effectiveTracked: [String] {
        fxEffectiveTracked(stored: store.trackedCurrencies,
                           fallback: RateAutoUpdater.currenciesInUse(store: store))
    }

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

            Section("Currencies") {
                ForEach(fxFilterRows(fxCurrencyRows(all: Currencies.iso, rates: store.exchangeRates, tracked: effectiveTracked), query: query), id: \.code) { row in
                    NavigationLink {
                        ExchangeRateHistoryView(currency: row.code)
                    } label: {
                        currencyRow(row)
                    }
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle("Currencies")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add rate")
            }
        }
        .sheet(isPresented: $showingAdd) { AddExchangeRateSheet() }
        .errorAlert($errorMessage)
        .onAppear { lastUpdated = UserDefaults.standard.object(forKey: RateAutoUpdater.stampKey) as? Date }
    }

    private func currencyRow(_ row: FxCurrencyRow) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.code).fontWeight(.medium)
                Text(row.isHub ? "\(row.label) · hub" : row.label)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(row.rate.map { String(format: "%.4f", $0) } ?? "—")
                .foregroundStyle(row.rate == nil ? Color.secondary : Color.primary)
            if !row.isHub {
                Toggle("", isOn: Binding(get: { row.tracked }, set: { setTracked(row.code, $0) }))
                    .labelsHidden()
                    .accessibilityLabel(Text("Track \(row.code)"))
            }
        }
        .padding(.vertical, 2)
    }

    /// Tracking writes materialize the app_state key (seed ± code). Toggling ON a
    /// currency with no stored rate fetches immediately (manual-act semantics).
    private func setTracked(_ code: String, _ on: Bool) {
        var set = Set(effectiveTracked)
        if on { set.insert(code) } else { set.remove(code) }
        do {
            try store.apply(.setTrackedCurrencies, Args(["codes": .array(set.sorted().map { JSONValue.string($0) })]))
            if on && fxLatest(store.exchangeRates, code) == nil { refreshNow() }
        } catch { errorMessage = i18nMessage(error) }
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

(The #492 helpers `currencyRow(code:latest:)` and `inverseText` are gone — replaced by the denser row above. `import SwiftUI` / `import FinchCore` at the top of the file stay.)

- [ ] **Step 2: Rewire Settings.** In `SettingsTab.swift` root list, after the Power Tools row add:

```swift
                NavigationLink { CurrenciesView() } label: { Label("Currencies", systemImage: "dollarsign.circle") }
```

and in `SettingsPowerToolsView` delete the line:

```swift
            NavigationLink("Exchange rates") { ExchangeRatesView() }
```

Then verify: `grep -rn "ExchangeRatesView" ios/FinchApp` → no matches.

- [ ] **Step 3: History empty state.** In `ExchangeRateHistoryView.swift` `body`, wrap the rows section:

```swift
            Section {
                if rows.isEmpty {
                    Text("No rates yet.").foregroundStyle(.secondary)
                }
                ForEach(rows, id: \.self) { rate in
```
(rest of the ForEach unchanged), and hide "Delete all" when empty by wrapping the toolbar `Menu` content:

```swift
                Menu {
                    if !rows.isEmpty {
                        Button(role: .destructive) { showDeleteAll = true } label: {
                            Label("Delete all \(currency) rates", systemImage: "trash")
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("More")
```

- [ ] **Step 4: Build iOS**

```bash
xcodegen generate && xcodebuild -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -quiet build 2>&1 | grep -E "error:" ; echo done
```
Expected: no `error:` lines.

- [ ] **Step 5: Commit**

```bash
git add -A ios/FinchApp/Sources/FinchApp/PowerTools ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift
git commit -m "feat(ios): Currencies page — Settings top-level, full ISO list with tracking toggles"
```

---

### Task 6: Verification (controller)

- [ ] Full suites: `-only-testing:FinchAppTests` and `-only-testing:FinchCoreTests` → both `** TEST SUCCEEDED **`, no count regressions.
- [ ] macOS build: `xcodebuild -project FinchApp.xcodeproj -scheme FinchMac CODE_SIGNING_ALLOWED=NO -quiet build` → clean (SettingsRootList is shared with macOS Preferences — the Currencies row must compile there).
- [ ] Sim (ios-finch2): install + launch → Settings root shows "Currencies"; Power Tools list has no Exchange rates entry. On the page: auto-update section on top; USD pinned ("US Dollar ($) · hub", 1.0000, no toggle); tracked block (seeded EUR/CAD) then A–Z rest; search narrows by code and name. DB proofs via `sqlite3`: toggle JPY ON → `app_state.fxTrackedCurrencies` materializes containing "JPY" and (network permitting) a JPY row lands with `source='ECB'`; toggle OFF → key updated, history rows intact. Tap a rate-less currency → history shows "No rates yet." with no Delete-all menu item.
- [ ] Screenshot the page for the PR if it adds clarity.

---

## Self-review notes

- Spec coverage: decisions 1→Task 5 (rewiring), 2→Tasks 3–5 (row layout), 3→Tasks 1–2 (semantics), 4→Task 4 (ordering/search), 5→Task 5 (section carried over), 6→Task 5 `setTracked` (fetch on ON when `fxLatest == nil`), 7→Task 5 Step 3 (empty state). ✓
- Names consistent: `setTrackedCurrencies` / `fxTrackedCurrencies` / `trackedCurrencies` / `fxEffectiveTracked` / `FxCurrencyRow` used identically across tasks. ✓
- Locale-dependent test ("yen") has an explicit relaxation note in Task 4 Step 4. ✓
- zh-Hans: "Currencies", "Track %@", "No rates yet.", "· hub" suffix → accumulated batch (separate effort).
