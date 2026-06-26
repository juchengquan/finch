# Widgets CP2 — configurable Account + Budget widgets (iOS)

**Date:** 2026-06-26
**Status:** Design approved, pending implementation
**Scope:** FinchCore (`WidgetSnapshot` expansion) + FinchApp (the snapshot writer) + `FinchWidget` (two new `AppIntentConfiguration` widgets). **No engine/DB/App-Group change.** Second CP of the "deepen widgets" sub-project.

## Problem

CP1 added lock-screen families to the single static **FinchOverview** widget. There's no way to pin **a specific account's balance** or **a specific budget's progress** — WidgetKit configurable widgets (the user long-presses → picks which account/budget) aren't used yet, and the shared snapshot only carries aggregates.

## Key findings (verified — additive)

- `WidgetSnapshot` (FinchCore) currently: `netWorth`, `currency`, `budgetUsedPct`, `weeklySpent`, `generatedAt`. The app writes it on every mutation; the widget reads it from the App Group. The watch decodes the same JSON into its own struct (extra keys are ignored — safe to add fields).
- At write time the app has everything for per-item data: `store.accounts` (`AccountRow.id/name/balance/currency`) and `store.budgets` + `Selectors.budgetProgress(...).pct`. No new queries.
- The widget extension depends only on FinchCore and **cannot reach `FinchStore`/the DB** — so the configuration picker's options must come from the **snapshot**. `AppIntents` is a system framework available to the extension on iOS 17; the configuration intent + a snapshot-backed `EntityQuery` will live **in `FinchWidget/` directly** (no project.yml/FinchCore change). This is the app's first `AppIntentConfiguration`.
- `Money.format(_:currency:)` (FinchCore) formats a native amount in its own currency — reuse it for per-account balances.

## CP2 decisions (locked)

1. **Two new configurable widgets** (FinchOverview stays as-is): **Account** (pick account → balance) and **Budget** (pick budget → usage ring).
2. **Snapshot expansion is optional-typed + defaulted** (`accounts: [..]? = nil`, `budgets: [..]? = nil`) so old snapshots decode (synthesized Codable handles missing keys for optionals); consumers use `?? []`.
3. Account balance shown in the account's **native currency** (`AccountSnapshotItem.balance` = native `account.balance`, `currency` = `account.currency`) via `Money.format`.
4. Config intent + entities + snapshot-backed queries live in `FinchWidget/WidgetIntents.swift`.

## Detailed design

### FinchCore — `WidgetSnapshot` expansion (`Project/WidgetSnapshot.swift`)

```swift
public struct AccountSnapshotItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String; public let name: String; public let balance: Double; public let currency: String
    public init(id: String, name: String, balance: Double, currency: String) { … }
}
public struct BudgetSnapshotItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String; public let name: String; public let usedPct: Int
    public init(id: String, name: String, usedPct: Int) { … }
}
```
Add to `WidgetSnapshot`: `public var accounts: [AccountSnapshotItem]?` and `public var budgets: [BudgetSnapshotItem]?` (memberwise init gains both, **defaulted `= nil`** so existing call sites compile and old JSON decodes).

### FinchApp — writer (`Widgets/WidgetSnapshot.swift` `build(from:)`)

Populate the two arrays (native balance / per-budget pct):
```swift
let accts = store.accounts.map {
    AccountSnapshotItem(id: $0.id, name: $0.name ?? "Account", balance: $0.balance, currency: $0.currency ?? store.displayCurrency)
}
let buds = store.budgets.map {
    BudgetSnapshotItem(id: $0.id, name: $0.name, usedPct: Selectors.budgetProgress($0, store.txns, store.today, store.categoryNodes).pct)
}
```
Pass `accounts: accts, budgets: buds` into the `WidgetSnapshot(...)` init.

### FinchWidget — `WidgetIntents.swift` (new)

- `WidgetAccountEntity: AppEntity { id, name }` + `static var defaultQuery = WidgetAccountQuery()` + display representations.
- `WidgetAccountQuery: EntityQuery` — `entities(for:)` and `suggestedEntities()` read `AppGroup.readWidgetSnapshot()?.accounts ?? []` → map to entities (NOT `FinchStore`).
- `SelectAccountIntent: WidgetConfigurationIntent` — `@Parameter(title: "Account") var account: WidgetAccountEntity?`; `title`/`description`.
- Same trio for budgets: `WidgetBudgetEntity`, `WidgetBudgetQuery` (reads `…?.budgets ?? []`), `SelectBudgetIntent` (`@Parameter var budget: WidgetBudgetEntity?`).

### FinchWidget — the two widgets (`FinchWidget.swift`)

- **`AccountWidget`** = `AppIntentConfiguration(kind: "FinchAccount", intent: SelectAccountIntent.self, provider: AccountProvider())`.
  - `AccountProvider: AppIntentTimelineProvider` — entry resolves the chosen item: `AppGroup.readWidgetSnapshot()?.accounts?.first { $0.id == configuration.account?.id }`.
  - View: account name + `Money.format(item.balance, currency: item.currency)`; families `.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline`. Placeholder "Pick an account" when unconfigured or the id is gone.
- **`BudgetWidget`** = `AppIntentConfiguration(kind: "FinchBudget", intent: SelectBudgetIntent.self, provider: BudgetProvider())`.
  - View: budget name + a usage `Gauge`/ring of `usedPct`; families `.systemSmall, .accessoryCircular`. Placeholder "Pick a budget".
- Add both to `FinchWidgetBundle` (alongside `FinchWidget`).

### Reuse

`AppGroup.readWidgetSnapshot()`, `Money.format(_:currency:)`, the existing `FinchOverview` widget (unchanged), the snapshot write trigger (already fires on every mutation).

## Facts (verified)

- `WidgetSnapshot` + writer `build(from:)` shapes as quoted in the survey; `store.accounts: [AccountRow]` (id/name/balance/currency), `store.budgets` + `Selectors.budgetProgress(_:_:_:_:).pct`, `store.displayCurrency`.
- `FinchWidget` target deps = FinchCore only; iOS 17 (AppIntentConfiguration + AppEntity/EntityQuery available); `import AppIntents` needs no project.yml change.
- No existing `AppIntentConfiguration`/`WidgetConfigurationIntent` (CP2 is the first). `Money.format` in FinchCore.
- 0 open PRs touch widgets; other session in Insights/i18n/scheduled.

## Testing

- **FinchCore:** `WidgetSnapshot` Codable round-trip **with** `accounts`/`budgets` populated, **and** decoding an old JSON blob without those keys → both `nil` (back-compat). `AccountSnapshotItem`/`BudgetSnapshotItem` round-trip.
- **FinchApp:** the writer populates `accounts`/`budgets` from a seeded store (if a writer test exists; else a FinchCore-level check of the item builders).
- **Build gate:** iOS (FinchApp embeds FinchWidget) + macOS (FinchMac); full FinchAppTests + FinchCore green.
- **Manual (sim):** add the **finch Account** widget → long-press → Edit → pick an account → shows its balance; add **finch Budget** → pick a budget → shows its ring. Unconfigured → "Pick…" placeholder.

## Out of scope (CP3 / later)

Interactive quick-add `Button(intent:)` (CP3); the Watch complication (separate sub-project); per-account sparkline history (snapshot carries no history); editing the FinchOverview widget's content.
