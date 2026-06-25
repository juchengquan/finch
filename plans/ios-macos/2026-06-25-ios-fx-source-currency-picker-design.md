# FX source + currency picker (iOS Power Tools)

**Date:** 2026-06-25
**Status:** Design approved, pending implementation
**Scope:** iOS `ExchangeRatesView` (Power Tools → Exchange rates) + `ExchangeRate` model/projection + a new ISO currency list in FinchCore. **No engine/schema change.** iPad/Mac share the view.

## Problem

The iOS exchange-rate admin lags the web on two counts: (1) the **currency is free text** (`TextField("Currency (e.g. EUR)")`) — no validation, you can save "FOO"; (2) the **rate `source` is invisible and unsettable** — even though the `exchange_rates.source` column, the `setExchangeRate` `source` arg, and the auto-`'derived'` provenance all already exist, the iOS projection drops `source` and the form never sets it. The web shows a color-coded source badge and a validated currency dropdown + source dropdown.

## Goal

- **Validated currency picker:** replace the free-text field with a **searchable single-select** over a full ISO 4217 code list (excluding `USD`, the hub).
- **Source:** a dropdown `ECB / Yahoo / manual` (default **manual**), passed to `setExchangeRate`.
- **Source badge:** each rate row shows a color-coded badge (ECB green / Yahoo blue / manual orange; `nil` → "manual"), mirroring the web.
- Surface `source` on the `ExchangeRate` model + projection so the badge has data.

## Non-goals

- No live ECB/Yahoo fetching — `ECB`/`Yahoo` are just provenance labels a user can pick (matching the web); real ECB/Yahoo rates arrive via DB import.
- No per-currency symbol/decimals for codes beyond the 11 iOS already formats — those render via the existing `Money.format` fallback (`"BRL 1.23"`). Acceptable.
- No engine/schema change (both already support `source`); no web change.

## Key decisions (locked)

1. **Full ISO 4217 list** (~170 active codes) as a FinchCore constant `Currencies.iso: [String]` — the FX picker offers all of them (minus USD); `availableDisplayCurrencies` can't, since adding a rate introduces a *new* currency.
2. **Searchable picker** — reuse the existing `SearchablePickerRow` (`PickerOption{id,name}` + `@Binding selection`). Code is both id and name (search by code).
3. **Source dropdown** `ECB`/`Yahoo`/`manual`, default `manual` (web parity).
4. **No engine/schema change.**

## Detailed design

### Model + projection (FinchCore)

- `ExchangeRate` (`Project/Money.swift`) gains `public let source: String?` (init param defaulted `nil` so other call sites compile).
- The rates projection (`Projections+State.swift` — currently `SELECT date, currency, rate FROM exchange_rates`) becomes `SELECT date, currency, rate, source …` and passes `source: r["source"]` to the init.

### Currency list (FinchCore)

- New `ios/FinchCore/Sources/FinchCore/Project/Currencies.swift`: `public enum Currencies { public static let iso: [String] = [ "AED", "AFN", … ] }` — the ISO 4217 active alphabetic codes, sorted. (`USD` may be in the list; the picker filters it out.)

### `ExchangeRatesView` (FinchApp)

- **Add/edit form:**
  - Currency: `SearchablePickerRow(title: "Currency", options: Currencies.iso.filter { $0 != "USD" }.map { PickerOption(id: $0, name: $0) }, selection: $currency)` — replaces the free-text field. Default selection = first non-USD code (or empty → validated on save).
  - Source: a menu `Picker` over `["ECB", "Yahoo", "manual"]`, `@State source = "manual"`.
  - Rate (`.decimalPad`) + date unchanged.
  - Save passes `date`, `currency`, `rate`, **`source`** to `setExchangeRate` (the handler already accepts it; uppercasing/validation already there).
- **List row:** add a source badge — a small capsule with the source text (`rate.source ?? "manual"`), colored by source: ECB → `text-success`/green, Yahoo → `accent`/blue, manual (and nil) → `warning`/orange. Mirror the web's `SOURCE_STYLE` using the app's semantic colors (`Color.green`/`.accentColor`/`.orange` or the token equivalents). Keep the existing currency / rate / date columns.

### Formatting note

Rates are still shown via the existing `String(format: "%.4f", rate.rate)` (unchanged). Currencies beyond the 11 in `Money.currencies` only affect amount formatting elsewhere (fallback `"CODE 1.23"`), not this view.

## Facts (already present — no change)

- Schema `exchange_rates(date, currency, rate, source, PRIMARY KEY(date,currency))` (`Storage/Schema.swift`). `setExchangeRate` arg struct already has `source: String?` and writes it; guards (YMD, non-empty currency, rate>0, USD-hub) already correct. Auto-resolved rates insert `source = 'derived'` (`Entries.swift`).
- `SearchablePickerRow` exists (`WriteScreens/SearchablePickerRow.swift`): `PickerOption: Identifiable, Hashable {id, name}`, `SearchablePickerRow {title, options:[PickerOption], @Binding selection: String}`.
- Web parity: `SOURCES = ['ECB','Yahoo','manual']`, default `manual`; badge colors ECB=success, Yahoo=primary, manual=warning; null → "manual" fallback (`frontend/components/exchange-rates.tsx`).

## Testing

- **FinchCore:** projection carries `source` — seed a rate via `setExchangeRate` with `source: "ECB"`, project, assert `source == "ECB"`; a rate with no source projects `nil`. `Currencies.iso` is non-empty, contains common codes (EUR/JPY/BRL), and is sorted/unique.
- **Build gate:** iOS + macOS (FinchMac); full FinchAppTests green.
- **Manual (sim):** add a rate — currency is a searchable picker (type "bra" → BRL), source defaults to manual; the row shows the colored badge; pick source ECB → green badge; a free-text "FOO" can no longer be entered; delete still works.

## Out of scope

Live FX fetching; per-currency formatting for the long tail; editing the `source` of import/`derived` rows beyond re-adding; engine/web changes.
