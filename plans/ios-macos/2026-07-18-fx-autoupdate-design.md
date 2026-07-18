# FX rates auto-update (Frankfurter, free/no-key) — the app's first network fetch

**Date:** 2026-07-18
**Status:** Design; plan follows before any code (user-approved direction: opt-in toggle, default ON).
**Scope:** iOS-only service that refreshes exchange rates daily from **Frankfurter v2**
(`api.frankfurter.dev` — no key, no quotas, central-bank data; live-verified 2026-07-17 incl.
SGD/EUR/JPY/GBP). Rates are written through the existing `setExchangeRate` chokepoint, so they
persist, sync in packs, and reach the web side. Manual entry is untouched and always wins later
(same upsert). No engine/schema change.

## Semantics (verified)
- Our store: `rate` = **USD per 1 unit** of the currency ("Rate (per USD)"; seed EUR = 1.08).
- Frankfurter `GET /v2/rates?base=USD&quotes=EUR,SGD` returns **quote per USD** → store the
  **inverse** (`1 / rate`), rounded to 6 significant decimals. Response rows: `{date, base,
  quote, rate}`.
- USD itself is the hub (never stored). Currencies fetched = the union of account currencies +
  ledger base currencies + existing `exchange_rates` currencies, minus USD — typically 1–3 codes.
  Nothing else is sent (the URL contains only currency codes).

## Components (all in FinchApp; no FinchCore change)

1. **`Sync/RateAutoUpdater.swift`** — a small `@MainActor` service:
   - `static func refreshIfDue(store: FinchStore)` — guards: toggle on (`@AppStorage
     "finch.fx.autoUpdate"`, default **true**), ≥ 20h since `finch.fx.lastAutoUpdate`
     (UserDefaults — device-local by design; the *rates* sync, the *fetch schedule* shouldn't),
     non-empty currency set.
   - Fetch via `URLSession.shared` (async, 10s timeout). Decode with a **pure, unit-testable**
     `parse(data:) -> [(date: String, currency: String, ratePerUSD: Double)]` (inversion lives
     here).
   - Write each via `store.apply(.setExchangeRate, …)` with `source: "ECB"`; stamp
     `lastAutoUpdate` **only on success**. All failures are silent (`nil` network, HTTP ≠ 200,
     decode failure) — offline-first; next launch retries after the throttle.
2. **Trigger:** `FinchApp.swift`'s existing `scenePhase == .active` branch calls
   `Task { await RateAutoUpdater.refreshIfDue(store: store) }` (also fires on cold launch;
   skipped while locked — mirror the Spotlight gating).
3. **Settings › Advanced:** new "Exchange rates" section — `Toggle("Auto-update exchange
   rates")` + footer: *"Fetches daily reference rates for your currencies from Frankfurter
   (frankfurter.dev, central-bank data). Only currency codes are sent."* Shows "Last updated"
   caption when a stamp exists.

## Privacy/product notes
- First third-party network call in the app — isolated in one file, opt-out via the toggle
  (default ON per user decision), request contains currency codes only, HTTPS.
- macOS: same code compiles and runs (URLSession is cross-platform) — toggle governs both.

## Out of scope
Web-side auto-fetch; historical backfill; retry/backoff beyond the daily throttle; a visible
"refresh now" button (candidate follow-up in the FX Power Tool); localization batch.

## Testing
- **Unit (FinchAppTests):** `parse` — valid payload → inverted rates; malformed → empty;
  USD row ignored. Throttle logic factored testable (`isDue(now:last:)`).
- **Builds** both platforms. **Sim (ios-finch2):** toggle visible; with seed data (EUR),
  trigger foreground → `exchange_rates` gains today's EUR row with `source='ECB'` (DB check —
  the sim has network). Toggle OFF → no fetch (stamp cleared, relaunch, no new row).
