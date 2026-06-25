# FX source + currency picker — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the free-text FX currency field with a searchable ISO 4217 picker, add a source dropdown (ECB/Yahoo/manual) + a color-coded source badge, and surface `source` on the rate model/projection.

**Architecture:** No engine/schema change. (1) FinchCore: `ExchangeRate` gains `source: String?`, the projection stops dropping it, and a new `Currencies.iso` constant holds the ISO codes. (2) FinchApp: `ExchangeRatesView`/`AddExchangeRateSheet` gain the searchable currency picker (reusing `SearchablePickerRow`), the source picker, and the badge.

**Tech Stack:** Swift / SwiftUI (iOS 17 / macOS 14), FinchCore, XcodeGen, XCTest.

## Global Constraints

- **No engine/schema change.** `exchange_rates.source` column, `setExchangeRate` `source: String?` arg, and the auto-`'derived'` provenance already exist.
- Currency picker = **full ISO 4217 list** (`Currencies.iso`) minus `USD` (the hub), via the existing `SearchablePickerRow` (searchable).
- Source = `["ECB", "Yahoo", "manual"]`, default **manual**; passed to `setExchangeRate`.
- Source badge colors: ECB → green/success, Yahoo → blue/accent, manual (and `nil`) → orange/warning.
- **Must build iOS AND macOS (FinchMac).** Sim `iPhone 17 Pro Max`. New files → `xcodegen generate`. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Conventional-commit; **no `Co-Authored-By` trailer**.

---

## File Structure

**Modify (FinchCore):** `ios/FinchCore/Sources/FinchCore/Project/Money.swift` (ExchangeRate), `ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift` (exchangeRates projection).
**Create (FinchCore):** `ios/FinchCore/Sources/FinchCore/Project/Currencies.swift` (`Currencies.iso`).
**Create (tests):** `ios/FinchCore/Tests/FinchCoreTests/FxSourceTests.swift`.
**Modify (FinchApp):** `ios/FinchApp/Sources/FinchApp/PowerTools/ExchangeRatesView.swift`.

---

### Task 1: `source` on the model/projection + `Currencies.iso`

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Project/Money.swift` (lines 5-12)
- Modify: `ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift` (lines 152-158)
- Create: `ios/FinchCore/Sources/FinchCore/Project/Currencies.swift`
- Test: `ios/FinchCore/Tests/FinchCoreTests/FxSourceTests.swift`

**Interfaces:**
- Produces: `ExchangeRate.source: String?` (init param defaulted `nil`); `Projection.exchangeRates` populates it; `Currencies.iso: [String]`.

- [ ] **Step 1: Write the failing tests**

Create `ios/FinchCore/Tests/FinchCoreTests/FxSourceTests.swift`:

```swift
import XCTest
@testable import FinchCore

final class FxSourceTests: XCTestCase {
    func test_projection_carries_source() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "setExchangeRate", args: Args([
            "date": .string("2026-05-01"), "currency": .string("EUR"), "rate": .double(1.1), "source": .string("ECB")]))
        try Apply.apply(dbQueue: q, action: "setExchangeRate", args: Args([
            "date": .string("2026-05-01"), "currency": .string("JPY"), "rate": .double(0.0064)]))   // no source
        let rates = try Projection.exchangeRates(dbQueue: q)
        XCTAssertEqual(try XCTUnwrap(rates.first { $0.currency == "EUR" }).source, "ECB")
        XCTAssertNil(try XCTUnwrap(rates.first { $0.currency == "JPY" }).source)
    }

    func test_currencies_iso_sane() {
        XCTAssertFalse(Currencies.iso.isEmpty)
        for c in ["EUR", "JPY", "BRL", "USD"] { XCTAssertTrue(Currencies.iso.contains(c), "missing \(c)") }
        XCTAssertEqual(Currencies.iso, Currencies.iso.sorted(), "must be sorted")
        XCTAssertEqual(Set(Currencies.iso).count, Currencies.iso.count, "must be unique")
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter FxSourceTests`
Expected: FAIL to compile — `ExchangeRate` has no `source`; `Currencies` undefined.

- [ ] **Step 3: Add `source` to `ExchangeRate`**

Replace `Money.swift` lines 5-12 with:
```swift
public struct ExchangeRate: Equatable, Hashable, Sendable, Codable {
    public let date: String
    public let currency: String
    public let rate: Double
    public let source: String?
    public init(date: String, currency: String, rate: Double, source: String? = nil) {
        self.date = date; self.currency = currency; self.rate = rate; self.source = source
    }
}
```

- [ ] **Step 4: Populate `source` in the projection**

In `Projections+State.swift`, replace the `exchangeRates` body (lines 153-157) with:
```swift
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT date, currency, rate, source FROM exchange_rates").map { r in
                ExchangeRate(date: r["date"], currency: r["currency"], rate: r["rate"], source: r["source"])
            }
        }
```

- [ ] **Step 5: Create `Currencies.iso`**

Create `ios/FinchCore/Sources/FinchCore/Project/Currencies.swift`:
```swift
import Foundation

/// ISO 4217 active alphabetic currency codes — the option set for the FX rate
/// picker. Sorted + unique. (USD is included; the picker filters it out as the
/// hub.) Codes beyond the few in `Money.currencies` format via the `Money.format`
/// fallback (`"CODE 1.23"`), which is fine for a rate-entry picker.
public enum Currencies {
    public static let iso: [String] = [
        "AED", "AFN", "ALL", "AMD", "ANG", "AOA", "ARS", "AUD", "AWG", "AZN",
        "BAM", "BBD", "BDT", "BGN", "BHD", "BIF", "BMD", "BND", "BOB", "BRL",
        "BSD", "BTN", "BWP", "BYN", "BZD", "CAD", "CDF", "CHF", "CLP", "CNY",
        "COP", "CRC", "CUP", "CVE", "CZK", "DJF", "DKK", "DOP", "DZD", "EGP",
        "ERN", "ETB", "EUR", "FJD", "FKP", "GBP", "GEL", "GHS", "GIP", "GMD",
        "GNF", "GTQ", "GYD", "HKD", "HNL", "HTG", "HUF", "IDR", "ILS", "INR",
        "IQD", "IRR", "ISK", "JMD", "JOD", "JPY", "KES", "KGS", "KHR", "KMF",
        "KPW", "KRW", "KWD", "KYD", "KZT", "LAK", "LBP", "LKR", "LRD", "LSL",
        "LYD", "MAD", "MDL", "MGA", "MKD", "MMK", "MNT", "MOP", "MRU", "MUR",
        "MVR", "MWK", "MXN", "MYR", "MZN", "NAD", "NGN", "NIO", "NOK", "NPR",
        "NZD", "OMR", "PAB", "PEN", "PGK", "PHP", "PKR", "PLN", "PYG", "QAR",
        "RON", "RSD", "RUB", "RWF", "SAR", "SBD", "SCR", "SDG", "SEK", "SGD",
        "SHP", "SLE", "SOS", "SRD", "SSP", "STN", "SYP", "SZL", "THB", "TJS",
        "TMT", "TND", "TOP", "TRY", "TTD", "TWD", "TZS", "UAH", "UGX", "USD",
        "UYU", "UZS", "VED", "VES", "VND", "VUV", "WST", "XAF", "XCD", "XOF",
        "XPF", "YER", "ZAR", "ZMW", "ZWL",
    ]
}
```

- [ ] **Step 6: Run tests**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter FxSourceTests`
Expected: PASS (2 tests). If `test_currencies_iso_sane` flags "not sorted"/"duplicate", fix the array (the list above is sorted + unique).

- [ ] **Step 7: Full FinchCore suite (no regressions)**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test`
Expected: all pass. (The `source: String? = nil` default keeps other `ExchangeRate(...)` call sites valid.)

- [ ] **Step 8: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchCore/Sources/FinchCore/Project/Money.swift \
        ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift \
        ios/FinchCore/Sources/FinchCore/Project/Currencies.swift \
        ios/FinchCore/Tests/FinchCoreTests/FxSourceTests.swift
git commit -m "feat(ios): surface ExchangeRate.source + add Currencies.iso list"
```

---

### Task 2: `ExchangeRatesView` — currency picker, source picker, badge

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/PowerTools/ExchangeRatesView.swift`

**Interfaces:**
- Consumes: `ExchangeRate.source`, `Currencies.iso` (Task 1); existing `SearchablePickerRow`/`PickerOption`, `DecimalInput`, `AppDate.isoDay`, `store.apply`.

- [ ] **Step 1: Replace the file**

Replace the entire contents of `ios/FinchApp/Sources/FinchApp/PowerTools/ExchangeRatesView.swift` with:

```swift
import SwiftUI
import FinchCore

/// Phase 4 (FX tools) — view/add/delete exchange rates (units per USD hub).
/// setExchangeRate / deleteExchangeRate through the chokepoint.
struct ExchangeRatesView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var showingAdd = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if store.exchangeRates.isEmpty {
                Text("No exchange rates. USD is the hub (rate 1).").foregroundStyle(.secondary)
            }
            ForEach(store.exchangeRates, id: \.self) { rate in
                HStack {
                    Text(rate.currency).fontWeight(.medium)
                    SourceBadge(source: rate.source)
                    Spacer()
                    Text(String(format: "%.4f", rate.rate))
                    Text(rate.date).font(.caption).foregroundStyle(.secondary)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { delete(rate) } label: { Label("Delete", systemImage: "trash") }
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
    }

    private func delete(_ r: ExchangeRate) {
        do { try store.apply(.deleteExchangeRate, Args(["date": .string(r.date), "currency": .string(r.currency)])) }
        catch { errorMessage = i18nMessage(error) }
    }
}

/// Color-coded provenance badge (mirrors the web's SOURCE_STYLE). nil → "manual".
private struct SourceBadge: View {
    let source: String?
    private var label: String { source ?? "manual" }
    private var color: Color {
        switch source {
        case "ECB": return .green
        case "Yahoo": return .blue
        default: return .orange   // manual / derived / nil
        }
    }
    var body: some View {
        Text(label)
            .font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .accessibilityLabel("source \(label)")
    }
}

private let fxSources = ["ECB", "Yahoo", "manual"]

struct AddExchangeRateSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    @State private var currency = ""
    @State private var rate = ""
    @State private var date = Date()
    @State private var source = "manual"
    @State private var errorMessage: String?

    private var currencyOptions: [PickerOption] {
        Currencies.iso.filter { $0 != "USD" }.map { PickerOption(id: $0, name: $0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                SearchablePickerRow(title: "Currency", options: currencyOptions, selection: $currency)
                HStack { Text("Rate (per USD)"); Spacer(); TextField("0.0000", text: $rate).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                DatePicker("As of", selection: $date, displayedComponents: .date)
                Picker("Source", selection: $source) { ForEach(fxSources, id: \.self) { Text($0).tag($0) } }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Add Rate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }.accessibilityLabel("Save").bold()
                }
            }
            .onAppear { if currency.isEmpty { currency = currencyOptions.first?.id ?? "" } }
        }
    }

    private func save() {
        errorMessage = nil
        guard !currency.isEmpty else { errorMessage = "Pick a currency."; return }
        guard let r = DecimalInput.parse(rate), r > 0 else { errorMessage = "Enter a rate > 0."; return }
        do {
            try store.apply(.setExchangeRate, Args([
                "date": .string(AppDate.isoDay.string(from: date)),
                "currency": .string(currency),
                "rate": .double(r),
                "source": .string(source)]))
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
```

- [ ] **Step 2: Build iOS + run the full FinchApp suite**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Build macOS (FinchMac)**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual verification on the simulator**

Launch (Settings › Power Tools › Exchange rates). Then:
- **Add:** Currency row pushes a searchable list — type "bra" → BRL; USD is absent. Source defaults to **manual**; pick **ECB**. Enter a rate, Save → the row shows a green **ECB** badge.
- A second rate with source **manual** → orange badge; **Yahoo** → blue.
- Free-text currency is no longer possible.
- Delete (swipe) still works.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(xcodebuild -project /Users/blackmount8/_repository/finch/ios/FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$IPHONE" "$APP"
xcrun simctl launch "$IPHONE" com.juchengquan.finch -initialTab settings
```

- [ ] **Step 5: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/PowerTools/ExchangeRatesView.swift
git commit -m "feat(ios): FX currency picker + source dropdown + source badge"
```

---

## Self-Review

**Spec coverage** (against `2026-06-25-ios-fx-source-currency-picker-design.md`):
- `ExchangeRate.source` + projection → Task 1 steps 3-4. ✓
- `Currencies.iso` full ISO list → Task 1 step 5. ✓
- Searchable currency picker (USD excluded) via `SearchablePickerRow` → Task 2 (`currencyOptions` + `SearchablePickerRow`). ✓
- Source dropdown (ECB/Yahoo/manual, default manual) passed to setExchangeRate → Task 2 (`source` state + `save`). ✓
- Color-coded source badge (nil → manual) → Task 2 (`SourceBadge`). ✓
- No engine/schema change; build iOS+macOS; full tests → Task 2 steps 2-3. ✓

**Placeholder scan:** No TBD/TODO; full code in every step; `Currencies.iso` is the literal list; sim step concrete. ✓

**Type consistency:** `ExchangeRate(date:currency:rate:source:)` with defaulted `source` keeps other call sites valid; projection passes `source: r["source"]` (String?); `SourceBadge(source: rate.source)` takes `String?`; `SearchablePickerRow(title:options:selection:)` matches its definition (`[PickerOption]` + `Binding<String>`); `currencyOptions` maps `Currencies.iso` → `PickerOption`; `save` passes `source` as `.string`. `fxSources`/`source` default "manual". ✓

---

## Out of scope

Live FX fetching; per-currency symbol/decimals for the long tail; engine/web/schema changes.
