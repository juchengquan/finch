# Spec: privacy mode — one-tap mask for every rendered amount (web #416 → iOS/macOS)

**Date:** 2026-07-12
**Status:** design approved, ready for implementation plan
**Scope:** native app (`ios/`), `FinchApp` + `FinchMac` (shared sources). Port of the web feature shipped in #416 (`frontend/lib/use-privacy.ts` + `use-money.ts`); closes one of the two new parity gaps recorded in the handoff (#424).

## Goal

A one-tap **privacy mode** that masks every money figure the app renders — so it can be shown on a train without broadcasting balances — matching the web behavior: masked display strings, untouched math, per-device persistence, instant toggle.

## Web reference (what we're porting)

- `MONEY_MASK = '••••'`; when on, every `useMoney` formatter returns the mask instead of the figure.
- Numeric helpers (`toBase`) stay real — privacy only affects *formatted strings*, never math.
- Per-device flag in `localStorage` key **`finch.privacy`** (`'1'` = on) — never the DB, never exports.
- Toggled from the command palette ("privacy" entry, eye icon).

## Design

### 1. State — `FinchStore.privacyMode`

- `@Published public var privacyMode: Bool` on `FinchStore` (`FinchStore+ViewHelpers.swift` or the main class body, implementer's choice of file):
  - initialized from `UserDefaults.standard.bool(forKey: "finch.privacy")`;
  - persisted back on every change (e.g. `didSet` writing the key).
- Key name **`finch.privacy`** mirrors the web. UserDefaults is per-device and outside the SQLite DB / `.finch` pack, so the flag never syncs or exports — same guarantee as web.
- `@Published` means every store-observing view re-renders on toggle; no other plumbing.

### 2. Masking — the three core formatters

- Mask constant: `public static let moneyMask = "••••"` on `FinchStore` (same glyphs as web's `MONEY_MASK`).
- Early-return the mask when `privacyMode` is on, in exactly these three (all in `FinchStore+ViewHelpers.swift`):
  - `displayMoneyBase(_:)`
  - `displayMoney(_:from:)`
  - `displayMoney(_:forLedger:)`
- Everything else inherits: `subtotalDisplay(for:)` and `netWorthDisplay` delegate to `displayMoneyBase`; every screen (feed rows, accounts, budgets, scheduled, ledger list, Insights cards) formats through these helpers (verified in the #422 audit).
- **Not masked** (matching web): numeric helpers (`toBase`, selector outputs), chart *geometry* (bar heights, ring fills, budget progress — shapes stay real; only their money *labels* mask), percentages, counts, input `TextField`s, and `FinchCore.Money.format` itself (the engine formatter also feeds CSV/PDF export — exports are explicit user actions and stay real, as on web).

### 3. The four direct `Money.format` view sites

- `WriteScreens/AccountDetailView.swift:99` (last-reconciled balance) → masked: replace with a store-gated render (e.g. `store.privacyMode ? FinchStore.moneyMask : Money.format(...)` or route through a small store helper `displayNative(_:currency:)` — implementer's choice, one consistent mechanism for both files).
- `WriteScreens/SplitEditorView.swift:74-75` ("Transaction total" / "Allocated" `LabeledContent`) → masked, same mechanism.
- `WriteScreens/SplitEditorView.swift:126` (validation error "Splits must add up to X") → **stays real**: it's actionable feedback mid-edit, and the split editor's TextFields necessarily show typed digits anyway.

### 4. Toggles

- **`PrivacyToggleButton`** (new small view, e.g. in `Shell/AdaptiveShell.swift` next to `LedgerBarButton` or its own file): `Image(systemName: store.privacyMode ? "eye.slash" : "eye")`, accessibility label "Privacy mode", action `store.privacyMode.toggle()`. Added to the toolbars of **all 5 primary tabs** (Accounts, Budgets, Scheduled, Insights, Settings) in the trailing cluster next to the existing `+`/overflow items. Unlike `LedgerBarButton` it is **not** compact-gated — the eye is useful on iPad/Mac toolbars too; if it renders awkwardly in the regular-width toolbar the implementer may compact-gate it to match, noting so in the report.
- **Command palette** (`Shell/CommandPalette.swift`): append `PaletteCommand(title: "Toggle Privacy Mode", systemImage: "eye") { _ in FinchStore.shared.privacyMode.toggle() }` (palette closures receive the router; use `FinchStore.shared` for the store — it's the same instance the app injects).
- **macOS menu** (`Shell/FinchCommands.swift`): a "Hide Amounts" toggle-style item with `⌘⇧H`, calling the same `FinchStore.shared.privacyMode.toggle()`; title may flip ("Hide Amounts"/"Show Amounts") or stay static — implementer's choice, note it.

## Non-goals

- **No masking of widgets, Watch glance/complication, Spotlight, or notifications** (in-app only, per the scope decision; the snapshot/payload paths are untouched). A privacy-aware widget pass can be its own follow-up.
- No change to `FinchCore` (the engine's `Money.format` stays pure; CSV/PDF exports stay real).
- No masking of amount input fields or the split-validation error.
- No new persistence surface (UserDefaults only; nothing in the DB/pack).

## Testing / verification

- **Unit tests (`FinchAppTests`):**
  - `displayMoneyBase`/`displayMoney(from:)`/`displayMoney(forLedger:)` return `"••••"` when `privacyMode` is on and the real formatted string when off (build a store, flip the flag).
  - Toggling `privacyMode` persists to `UserDefaults` key `finch.privacy` and re-reads on a fresh store init (round-trip; clean up the key in `tearDown`).
- **Builds:** `FinchApp` (iOS) + `FinchMac` (macOS) — the toggle button and menu item are cross-platform code paths; keep any iOS-only toolbar placements guarded like the neighboring items.
- **Simulator visual check:** toggle the eye on each tab — every amount (summary cards, rows, Insights cards incl. savings-rate/net-worth/recent-expenses, account detail incl. reconciled balance, split editor totals) shows `••••`; charts keep their shapes; toggle off restores figures instantly; relaunch preserves the state.

## Risks

- A formatted amount that bypasses the three helpers would leak: the #422 audit found and fixed the strays, but the reviewer should re-grep `Money.format(` in `FinchApp/Sources` to confirm the only remaining view sites are the four addressed here (plus any native-currency-intentional ones inside the store itself).
- `UserDefaults`-backed `@Published` needs the write in `didSet` (not `willSet`) so tests reading the key immediately after toggling see the new value.
- Shared sources: everything here compiles into both FinchApp and FinchMac — no `WatchConnectivity`-style platform traps, but keep toolbar placements consistent with the neighboring `#if os(iOS)` guards.
