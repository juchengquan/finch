# Exchange rates page redesign (grouped by currency + FX controls move here)

**Date:** 2026-07-18
**Status:** Design approved in discussion; plan follows.
**Motivation:** #490's auto-update appends ~1 row per currency per day, so the flat
row-per-(date,currency) list in `ExchangeRatesView` degrades into a history dump where
today's rate is buried. Also the auto-update toggle landed in Settings › Advanced,
disconnected from the page where rates live.

**Scope:** FinchApp UI only — no FinchCore/engine/schema change, no web change, nothing
new syncs. All writes stay on the existing `setExchangeRate` / `deleteExchangeRate`
chokepoints.

## Decisions (from brainstorm)

1. **Auto-update controls MOVE to the FX page** — Settings › Advanced loses its
   "Exchange rates" section entirely (toggle, "Last updated", footer, and the
   `exchangeAutoUpdateBinding` helper migrate).
2. **"Refresh now" with feedback** — manual fetch that bypasses toggle + 20h throttle,
   inline spinner while running, "Updated N rates" caption on success, error alert on
   failure. First place a fetch failure becomes visible.
3. **Tap a currency → history page** with a sparkline (only when ≥3 points) above the
   dated rows; per-row delete lives there, plus a "Delete all" action.
4. **Summary rows show both directions** — primary "1 EUR = 1.1461 USD" (stored
   USD-per-unit), caption "1 USD = 0.8725 EUR · <date>" (inverse) — kills the
   per-USD ambiguity.
5. **No pruning** — history is kept indefinitely (rows are tiny; grouped UI hides the
   volume). Manual cleanup = per-row delete or per-currency Delete all.

## Components

### 1. `Sync/RateAutoUpdater.swift` — result-returning core (approach A)

Refactor so one file owns all fetch logic, now reportable:

```swift
enum RefreshOutcome: Equatable {
    case updated(Int)     // wrote N rates, stamp written
    case failed           // network / non-200 / decode failure — nothing written
    case skipped          // no currencies in use — nothing to fetch
}

/// Unguarded fetch: builds URL from currenciesInUse, fetches, parses, writes each
/// row via setExchangeRate(source: "ECB"), stamps lastAutoUpdate ONLY on success.
static func refresh(store: FinchStore) async -> RefreshOutcome

/// Existing entry point, now: toggle + throttle guards, then `await refresh(store:)`
/// (discarding the outcome). Trigger in FinchApp.swift is unchanged.
static func refreshIfDue(store: FinchStore) async
```

`parse`, `isDue`, `currenciesInUse`, keys, and `minInterval` are unchanged. "Refresh
now" calls `refresh(store:)` directly — deliberate manual act, so it runs even when
the toggle is OFF and regardless of throttle, and still stamps on success (a manual
refresh satisfies "today's fetch", so the next auto-run throttles normally).

### 2. `PowerTools/ExchangeRatesView.swift` — summary page (rework)

- **Section "Auto-update"** (no header; footer = the Frankfurter privacy text moved
  verbatim from Settings): `Toggle("Auto-update exchange rates")` with the same
  absent-key-default-ON binding; `LabeledContent("Last updated", …)` when a stamp
  exists (same `AppDate.h24Locale` formatting as today); a `Button("Refresh now")`
  row — trailing `ProgressView` while in flight, disabled while in flight, and after
  a successful run a secondary caption "Updated N rates" (state resets on next
  refresh; failure → `errorAlert` "Couldn't reach frankfurter.dev. Check your
  connection and try again."). The stamp/`Last updated` row refreshes because the
  view re-reads UserDefaults after the task completes (drive it from an
  `@State lastUpdated: Date?` refreshed on appear + after refresh, not a direct
  UserDefaults read in `body`).
- **Section "Rates"**: one row per currency, sorted A–Z. Row layout: currency code
  (medium weight) + `SourceBadge` of that currency's **latest** row; primary text
  `1 EUR = 1.1461 USD`; caption `1 USD = 0.8725 EUR · Jul 17` (inverse to 4
  significant decimals; date via abbreviated month-day format). Whole row is a
  `NavigationLink` to the history page. No swipe actions here. Empty state: current
  "No exchange rates. USD is the hub (rate 1)." line.
- **Toolbar**: `+` (Add Rate) unchanged; `AddExchangeRateSheet` untouched.

### 3. `PowerTools/ExchangeRateHistoryView.swift` — new file

- `init(currency: String)`; title = the code. Reads rows live from
  `store.exchangeRates` (filtered) so deletes update in place.
- **Sparkline section**: `Sparkline(values:)` (existing `Common/ChartViews`
  primitive) over rates in date-ascending order, height ~48pt, shown only when the
  currency has ≥3 rows.
- **Rows section**: date-descending list — date primary, trailing rate (`%.4f`) +
  `SourceBadge`; swipe + context-menu Delete per row (existing `deleteExchangeRate`
  args). `SourceBadge` becomes internal (drop `private`) in ExchangeRatesView.swift so
  the history view reuses it — same module, no move, no behavior change.
- **Toolbar ⋯ menu**: "Delete all EUR rates" → `confirmationDialog`; on confirm,
  loop `deleteExchangeRate` over the currency's rows. When the last row disappears
  (either path), `dismiss()` pops back to the summary.

### 4. `Tabs/SettingsTab.swift` — removal

Delete the "Exchange rates" `Section` from `SettingsAdvancedView` (SettingsTab.swift
~line 224–233) and the `exchangeAutoUpdateBinding` computed property (~line 286).
No other Settings change.

### 5. Derivation helpers — pure + unit-testable

Small file-scope helpers (in ExchangeRatesView.swift or a tiny `FxDerive.swift`;
internal so FinchAppTests reaches them):

```swift
/// Currency codes A–Z from a rate list.
func fxCurrencies(_ rates: [ExchangeRate]) -> [String]
/// Latest row for a currency (max date; on equal dates the later row in store order wins).
func fxLatest(_ rates: [ExchangeRate], _ currency: String) -> ExchangeRate?
/// Date-ascending rate values for the sparkline.
func fxSeries(_ rates: [ExchangeRate], _ currency: String) -> [Double]
```

Date strings are ISO `yyyy-MM-dd`, so lexicographic max/sort == chronological.

## Copy (new/changed strings → zh-Hans batch)

- "Refresh now"
- "Updated %lld rates"
- "Couldn't reach frankfurter.dev. Check your connection and try again."
- "Delete all %@ rates" (menu + dialog title) and dialog confirm "Delete %lld rates"
- Row formats "1 %@ = %@ USD" / "1 USD = %@ %@"
- Moved-not-new: "Auto-update exchange rates", "Last updated", Frankfurter footer.

## Error handling

- Refresh-now failure → error alert (above); auto path stays silent as designed.
- Delete failures surface via the existing `errorAlert(i18nMessage(error))` pattern.
- Both-direction math: inverse = `1 / rate`; rate > 0 is guaranteed by engine
  validation, but guard `rate > 0` before dividing anyway (show "—" otherwise).

## Testing

- **Unit (FinchAppTests):** `fxCurrencies` sorted/deduped; `fxLatest` picks max date;
  `fxSeries` ascending; `refresh(store:)` outcome mapping is exercised indirectly via
  existing parse/isDue tests (no network in tests — outcome enum is data-only).
- **Builds:** FinchApp + FinchMac.
- **Sim (ios-finch2):** grouped page shows one row per currency with both directions;
  tap → history with sparkline (seed EUR has history after a few fetches; if <3 rows,
  sparkline absent — verify rows render); Refresh now writes rows + updates stamp +
  shows count; toggle OFF then Refresh now still fetches; Delete all clears currency
  and pops; Settings › Advanced no longer shows the section.

## Out of scope

Web FX page changes; pruning/retention; rate charts beyond the sparkline; historical
backfill; a currency picker for display currency (lives in Settings › Ledger).
