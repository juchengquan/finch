# Currencies page (round 2): Settings top-level, full currency list, per-currency tracking

**Date:** 2026-07-18
**Status:** Design approved in discussion; plan follows.
**Builds on:** #490 (FX auto-update) and #492 (grouped Exchange rates page). This round makes
the page currency-centric and gives users explicit control over WHAT auto-updates.

**Scope:** FinchApp UI + one small native-first FinchCore engine action (app_state KV,
schema-free — mirrors #479's `setBudgetOrder`). No table-schema change, no web change
(web ignores the new app_state key until it adopts it), `Schema.version` untouched.

## Decisions (from brainstorm)

1. **Move out of Power Tools** → a top-level row in the Settings root list, renamed
   **"Currencies"** (icon `dollarsign.circle`), page title "Currencies". Power Tools loses
   its "Exchange rates" link.
2. **Full currency list** (all 145 `Currencies.iso` codes): row line 1 = ISO code,
   line 2 = localized name + sign in brackets ("Euro (€)"); right side = latest stored
   USD-per-unit rate (4dp, "—" when none) + a **tracking toggle**.
3. **Toggle = tracked by auto-update**: ON = included in the daily Frankfurter fetch;
   OFF = not fetched (existing history untouched). Replaces the implicit
   accounts∪ledgers∪existing-rates fetch set.
4. **List order**: USD pinned first (hub — no toggle, rate 1.0000), then tracked A–Z,
   then all others A–Z; one continuous list (no section split between tracked/untracked)
   with a search bar filtering by code or name (case-insensitive, order preserved).
5. **Old controls stay on top**: the Auto-update section from #492 (master toggle,
   "Last updated", "Refresh now") stays above the list; "+" Add Rate toolbar button and
   `AddExchangeRateSheet` unchanged. Master toggle still governs WHETHER the auto-fetch
   runs; per-currency toggles govern WHAT it fetches.
6. **Toggle-ON fetches immediately** when the currency has no rate for Frankfurter's
   latest day: fire the existing one-shot `RateAutoUpdater.refresh(store:)` (manual-act
   semantics — ignores master toggle + throttle, stamps on success). Toggle-OFF writes
   only.
7. **Tap → history** unchanged (`ExchangeRateHistoryView`); it gains an empty state
   ("No rates yet.") since rate-less currencies now navigate too.

## Components

### 1. FinchCore — `setTrackedCurrencies` action (native-first, app_state KV)

Mirror `setBudgetOrder` (#479) exactly, but GLOBAL (not per-ledger — exchange rates are
ledger-independent):

- `ActionName.swift`: `case setTrackedCurrencies  // native-first (global FX fetch list; the web ignores the key until it adopts it)`
- `Store/Domain/App.swift`: handler validating `codes: [String]` (uppercase ISO strings;
  de-dup; drop USD), writing JSON array to `app_state.fxTrackedCurrencies` via
  `setAppState`.
- `Project/Projections+State.swift`: `Projection.trackedCurrencies(dbQueue:) -> [String]?`
  — `nil` when the key is absent (distinct from empty!), else the decoded array.
- FinchCore engine test: set → project round-trip + validation (mirrors the budget-order
  test).

### 2. FinchApp store — effective tracked set

- `FinchStore.swift`: published `trackedCurrencies: [String]?` refreshed at projection
  time (same spot as `budgetOrderByLedger`).
- **Effective set resolution** (pure helper, unit-tested):
  `fxEffectiveTracked(stored: [String]?, fallback: [String]) -> [String]` — stored array
  when the key exists (even if empty = user untracked everything), else the seeded
  default = the current implicit set (`RateAutoUpdater.currenciesInUse` result). Absent
  key ⇒ behavior identical to today; first toggle materializes the key (seed ± the
  toggled code).
- `RateAutoUpdater.refresh(store:)` fetches the effective set instead of
  `currenciesInUse(store:)` (which stays as the fallback provider). Empty effective set
  → `.skipped` as today.

### 3. `FxCurrencyInfo` — names & signs (pure, cached)

New `Common/FxCurrencyInfo.swift`:

- `fxCurrencyName(_ code: String) -> String` —
  `Locale.current.localizedString(forCurrencyCode:)`, falling back to the code.
- `fxCurrencySymbol(_ code: String) -> String?` — one-time static scan of
  `Locale.availableIdentifiers` building a code→symbol map (shortest symbol wins);
  `nil` when the best symbol is just the code again.
- `fxCurrencyLabel(_ code: String) -> String` — "Euro (€)"; omits the bracket when the
  symbol is nil (avoids "CHF (CHF)").
- Unit tests: EUR/USD/JPY have short symbols and names; bogus code falls back to the
  code with no bracket; label composition.

### 4. `CurrenciesView` (rework of `ExchangeRatesView`)

Renamed page: `PowerTools/ExchangeRatesView.swift` → `PowerTools/CurrenciesView.swift`
(git mv; `AddExchangeRateSheet` + `SourceBadge` move with it; `SettingsPowerToolsView`
drops its link; Settings root gains
`NavigationLink { CurrenciesView() } label: { Label("Currencies", systemImage: "dollarsign.circle") }`).

- **Auto-update section**: unchanged from #492 (toggle, Last updated, Refresh now,
  Frankfurter footer).
- **Currency list section** with `.searchable` text field:
  - Row order: USD → tracked A–Z → untracked A–Z. Search filters by code or
    `fxCurrencyName` containment, preserving that order.
  - Row: leading VStack — code (`.fontWeight(.medium)`) over `fxCurrencyLabel` caption
    (secondary); trailing — latest rate via `fxLatest` (`%.4f`, "—" if none; source
    badge only on the USD-pinned "hub" caption is NOT shown — badges live in history
    now) and the tracking `Toggle` (accessibility label "Track <code>"). USD row: rate
    "1.0000", caption "US Dollar ($) · hub", no toggle.
  - Whole row navigates to `ExchangeRateHistoryView(currency:)`; the old grouped-row
    both-directions caption from #492 is replaced by this denser layout (inverse
    direction still visible inside history via rows; acceptable trade for 145-row
    density).
- **Toggle handler**: build the new tracked array (effective set ± code), apply
  `.setTrackedCurrencies`; on toggle-ON where the currency has **no stored rate at all**
  (`fxLatest == nil`) fire `Task { await RateAutoUpdater.refresh(store: store) }` and show
  the same spinner/feedback plumbing as Refresh now (reuse `refreshing`/`refreshNote`
  state; errors → the page's `errorAlert`).
- **History empty state**: `ExchangeRateHistoryView` shows "No rates yet." (secondary
  text) when the currency has no rows, instead of an empty list; "Delete all" hidden
  when empty. (It no longer auto-pops on empty arrival via toggle-less navigation —
  keep the existing pop-after-delete behavior only.)

### 5. Search & performance

145 static rows with two computed strings each — precompute the display models once per
`store.exchangeRates` change (a small memoized array in the view or a helper
`fxCurrencyRows(rates:tracked:) -> [Row]`, unit-tested for ordering), so `.searchable`
filtering is a cheap array filter, not 145 Locale lookups per keystroke.

## Copy (new strings → zh-Hans batch)

- "Currencies" (Settings row + nav title), "Search" placeholder (system default),
- "US Dollar ($) · hub" (assembled: name/symbol from Locale + literal "hub" suffix),
- "Track %@" (toggle a11y label), "No rates yet."
- Removed: none (Auto-update strings carry over).

## Error handling

- `setTrackedCurrencies` failures surface via `errorAlert(i18nMessage(error))`.
- Toggle-ON fetch failure: error alert (same as Refresh now); the toggle STAYS on —
  tracking is recorded, the rate arrives on a later refresh.
- Locale lookups can't fail (fallback to code).

## Testing

- **FinchCore:** engine round-trip + validation test for `setTrackedCurrencies`.
- **FinchAppTests:** `fxEffectiveTracked` (nil→fallback, []→[], set→set),
  `fxCurrencyRows` ordering (USD first, tracked A–Z, rest A–Z) + search filter,
  `FxCurrencyInfo` name/symbol/label fallbacks.
- **Builds:** FinchApp + FinchMac.
- **Sim (ios-finch2):** Settings root shows Currencies (Power Tools doesn't); list order
  + search; toggle JPY ON → rate fills within seconds (DB row, `source='ECB'`) and
  `app_state.fxTrackedCurrencies` materializes; toggle OFF → key updates, history
  intact; auto-run next foreground fetches only tracked codes (URL check via proxy is
  overkill — DB-diff acceptable); history empty state for a rate-less currency.

## Out of scope

Web adoption of `fxTrackedCurrencies`; per-ledger tracking; currency pickers elsewhere
(account/display currency) — unchanged; pruning; localization batch.
