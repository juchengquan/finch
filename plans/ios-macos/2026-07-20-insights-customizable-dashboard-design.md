# Insights — customizable template dashboard — design

**Date:** 2026-07-20
**Status:** approved (grilled + brainstormed with user)
**Scope:** iOS/macOS app only (`ios/`), UI/state only. No engine, projection, or web changes.

## Problem

The Insights **Trends** view is a hardcoded `LazyVStack` of **16 cards** (the
file header still says "Six cards" — it grew unmanaged). It's an overwhelming
firehose, several cards overlap, and two fully duplicate other tabs. But the
richness is wanted — the answer isn't a fixed editorial cut, it's letting the
user **choose** what they see: pick a **template**, then **customize** (show/hide
+ reorder) the cards.

## Decision

Turn Trends into a **data-driven, customizable dashboard**: a **card registry**
(each card = stable id + title + view builder) rendered from a saved **layout**
(ordered list of enabled card ids), seeded by named **templates** and editable
via a **Customize** sheet. The **Breakdown** sibling mode (report + CSV/PDF
export) is untouched. Two cards that duplicate other tabs are removed from the
catalog.

## Architecture

### 1. Card registry — `InsightsCards.swift`

Replace the hardcoded card list with a registry of catalog entries:

```swift
struct InsightsCardEntry: Identifiable {
    let id: String                 // stable, persisted (e.g. "monthlySpending")
    let title: String              // shown in the Customize list
    let consumesRange: Bool        // true for the 3 time-series cards
    let make: (_ rangeMonths: Int) -> AnyView
}

enum InsightsCatalog {
    static let all: [InsightsCardEntry] = [ … 14 entries … ]
    static func entry(_ id: String) -> InsightsCardEntry? { all.first { $0.id == id } }
}
```

The Trends view iterates the **active layout's** ids, looks each up in the
catalog, and renders `entry.make(rangeMonths)` inside the shared `Card` chrome.
Only the 3 `consumesRange` cards use `rangeMonths`; the rest ignore it.

**Catalog (14)** — the current cards minus the two duplicates:

| id | Card | Range? |
|---|---|---|
| `tips` | InsightsCard | – |
| `monthlySpending` | MonthlySpendingCard | ✓ |
| `netWorth` | NetWorthCard | ✓ |
| `cashflow` | CashflowCard | ✓ |
| `savingsRate` | SavingsRateCard | – |
| `whatIf` | WhatIfCard | – |
| `categoryDeltas` | CategoryDeltasCard | – |
| `weeklyDigest` | WeeklyDigestCard | – |
| `incomeSankey` | IncomeSankeyCard | – |
| `spendingHeatmap` | SpendingHeatmapCard | – |
| `netWorthByType` | NetWorthByTypeCard | – |
| `categoryBreakdown` | CategoryBreakdownCard | – |
| `topMerchants` | TopMerchantsCard | – |
| `forecast` | ForecastCard | – |

**Removed from Insights entirely:** `RecentExpensesCard` (duplicates the
Activity tab) and `HoldingsCard` (duplicates `HoldingsView` + the Accounts
tab). Their struct definitions are deleted.

### 2. Templates — `InsightsTemplate`

```swift
enum InsightsTemplate: String, CaseIterable, Identifiable {
    case overview, spending, wealth, everything
    var title: String { … }        // "Overview" / "Spending" / "Wealth" / "Everything"
    var cardIDs: [String] { … }     // the ordered ids below
}
```

- **overview** (default): `tips, monthlySpending, savingsRate, netWorth, categoryBreakdown, forecast`
- **spending**: `monthlySpending, categoryBreakdown, topMerchants, categoryDeltas, spendingHeatmap`
- **wealth**: `netWorth, netWorthByType, cashflow, savingsRate, whatIf`
- **everything**: all 14, in catalog order

Applying a template sets the layout to its `cardIDs`. The pseudo-state
**"Custom"** is not an enum case — it's simply "the saved layout no longer
equals any template's `cardIDs`", surfaced as the menu label.

### 3. Layout persistence — `InsightsLayoutStore`

Per-device, **global** (not per-ledger), in `UserDefaults` — never the DB or
exports (matches the app's view-pref convention). A tiny `ObservableObject`
(or a struct persisted via a `@AppStorage`-encoded JSON) holding:

```swift
struct InsightsLayout: Codable {
    var order: [String]        // enabled card ids, in display order
    var templateName: String?  // the template this matches, or nil == "Custom"
}
```

- Key: `"finch.insights.layout"` (JSON-encoded).
- First run / unset → the **overview** template.
- Unknown ids in a persisted layout (e.g. a card removed in a future build) are
  ignored on read; new catalog cards simply stay absent until added via a
  template or Customize (no silent auto-insert).

### 4. UI

**Top of Trends** (inside the existing `[Trends | Breakdown]` segmented control):
- A **template menu** (`Menu`) whose label is the active template title (or
  "Custom"): tapping lists the four templates (one-tap apply) + a
  **"Customize…"** entry.
- The existing **3M / 6M / 1Y** range picker stays, global, applying to the 3
  time-series cards.

**Customize sheet** — a `List` of **all 14** catalog cards:
- each row: card title + an on/off `Toggle` (bound to membership in `order`),
- **drag-to-reorder** (`.onMove`, edit mode) controlling `order`,
- Done dismisses. Any edit that makes `order` differ from every template →
  `templateName = nil` ("Custom").
- Cross-platform: reuse the app's existing reorder/list-edit idiom.

**Breakdown mode:** unchanged.

## Non-goals (explicit)

- No per-card configuration (each card's own range/month/chart type) — the range
  stays a single global control.
- No per-ledger layouts; no DB persistence or cross-device sync.
- No engine/projection/web changes; no new selectors (cards keep their current
  selectors).
- Breakdown mode and its CSV/PDF export are untouched.

## Suggested phasing (for the plan, not a design constraint)

- **Phase 1:** registry + templates + `InsightsLayoutStore` + rewired Trends
  rendering from the layout + the template menu (switch presets). Delete the two
  duplicate cards. Ships a working template-switching dashboard.
- **Phase 2:** the Customize sheet (toggles + reorder) + "Custom" state.

## Testing

- **Pure logic is unit-testable** (`FinchAppTests`): `InsightsTemplate.cardIDs`
  membership; "layout matches template X vs Custom" detection; the read path
  dropping unknown ids and defaulting to overview when unset.
- `InsightsCatalog.all` ids are unique and every template's ids exist in the
  catalog (a guard test).
- Build gate: FinchApp (iOS) + FinchMac.
- Manual: switch templates; Customize toggles/reorders and persists across
  relaunch; range still drives the time-series cards; Breakdown unchanged.
