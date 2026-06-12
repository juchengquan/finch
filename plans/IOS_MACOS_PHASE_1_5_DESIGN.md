# finch for iOS & macOS — Phase 1.5 Implementation Design

> **Status**: design spec — not yet an implementation plan. Once approved,
> this becomes the input to `writing-plans` to produce a step-by-step
> implementation plan for Phase 1.5.
>
> Companion documents:
>
> - `plans/IOS_MACOS_PLAN.md` — the direction brief
> - `plans/IOS_MACOS_PHASE_1_DESIGN.md` — the full design for Phase 1.0
>   (Accounts / Activity / Budgets / Settings; 4 tabs; ~1,500 lines TS to
>   port; **assumes this phase is complete**)
> - `plans/IOS_MACOS_ROADMAP.md` — the 8-phase arc (Phase 1.5 is sketched
>   there; this is the **full design** for that sketch)
> - `plans/IOS_MACOS_PHASE_1_5_DESIGN.md` (this file)
>
> _Audience: the engineers who will build the iOS app. Assumes Phase 1.0
> is complete and the `Project` + `Money` + `Audit` + `Pack` modules
> exist._

## See also

- `plans/IOS_MACOS_INDEX.md` — the navigation index
- `plans/IOS_MACOS_WIRE_FORMAT.md` §5 — the fixture format
- `plans/IOS_MACOS_PHASE_1_DESIGN.md` §1, §5, §8 — Phase 1.0 (the 4-tab shell + 7 selectors + parity suite)
- `plans/IOS_MACOS_PHASE_2_DESIGN.md` — Phase 2 (chokepoint + write screens)
- `plans/IOS_MACOS_PLAN.md` §2.4 — the selectors (read brains)

## §0. Map — 8-section template

The 8-section template maps to this spec's existing sections:

| Template section | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | §2 (Selector classification) + §3 (Selectors module layer rules) + §6 (Selectors module API surface) |
| §3. iOS UI surfaces | §5 (Insights tab UI) |
| §4. Cross-cutting concerns | §3 (Selectors module layer rules — the cross-domain DB access) |
| §5. Wire contracts | §6 (Selectors module API surface — the wire from selectors to chokepoint) |
| §6. CI / test infrastructure | §4 (JSON-golden parity test infrastructure) + §7 (Parity test file layout) |
| §7. Out of scope (firm) | §9 |
| §8. Spec self-review + open questions | §10 + §8 |

## §1. Goal & non-goals

**Goal** — Add the **Insights** tab (5th tab) + port the remaining 25
selectors from `lib/select.ts` + ship the **JSON-golden parity test
infrastructure** (the fixture export script + the `ParityTests` target's
selector assertions). Add the **per-ledger display-currency override
UI** in Settings. The app becomes "credible first release" coverage of
the web's read surface.

**Phase 1.5 is the last read-only phase**. Phase 2 adds the 74-action
write chokepoint.

**Non-goals (firm)**:

- Write paths — the 74-action chokepoint is Phase 2. The 25 selectors
  read; they don't write.
- The `accountBalance` / `selectTransactions` / `categorySpend` /
  `budgetProgress` / `merchantStats` / `anomalyScore` / `cycleWindow`
  selectors that Phase 1.0 ships — those are in Phase 1.0, not 1.5.
- New tabs beyond Insights. The web's 5 main tabs are: Accounts,
  Activity, Budgets, Insights, Settings. Phase 1.5 adds the 5th.
- The Insights tab is **read-only**. Forecast, weekly digest, and
  anomaly flagging are computed from existing data; nothing the user
  can edit.
- The per-ledger display-currency override UI uses the existing
  `displayCurrencyByLedger` semantics from the web's store
  (`lib/store/`); it does NOT add a new feature like "FX / base
  tools" (Phase 4).
- iPad / macOS adaptive layout (Phase 3)
- Power features (Phase 4): reconcile, rules engine, transfers CRUD,
  merchants / categories / tags admin, saved searches, bulk
  recategorize
- Auto-pack debounce + iCloud folder-watcher (Phase 5)
- App Intents / Siri / Share Extension receipts / Spotlight /
  notifications / biometric lock (Phase 6)
- Widgets / Watch / Live Activities (Phase 7)

**Estimated scope**: 25 selectors × ~50 lines each ≈ **1,250 lines TS
to port** + ~600 lines SwiftUI (Insights tab) + ~300 lines fixture
export script + ~750 lines new `ParityTests` files (25 selectors × ~30
lines each) + ~200 lines UI plumbing. **2-3 months of full-time work**
for a small team. This is larger than Phase 1.0.

## §2. Selector classification (what lands where)

The web's `lib/select.ts` exports **32 selectors**. Of those, **7 land
in Phase 1.0** (required by the 4 tabs + Account Detail) and **25 land
in Phase 1.5** (the Insights tab + supporting selectors).

### Phase 1.0 selectors (already specced; do not re-port in 1.5)

| Selector | Purpose | Used by |
|---|---|---|
| `accountBalance(accounts, accountId)` | Single account's current balance | Accounts tab (net worth footer) |
| `selectTransactions(txns, opts)` | Filtered/sorted transaction list | Activity tab |
| `categorySpend(txns, ledgerId, month?)` | Per-category spend for a month | Budgets tab (progress bars) |
| `budgetProgress(budget, ...)` | One budget's spent / limit / period | Budgets tab (each row) |
| `merchantStats(txns, ledgerId)` | Per-merchant aggregate stats | Activity tab (anomaly badge), Account Detail |
| `anomalyScore(tx, stats)` | Per-transaction anomaly z-score | Activity tab, Account Detail |
| `cycleWindow(freq, startDate, ...)` | Budget cycle window math | Budgets tab (`budgetProgress` dependency) |

**Total Phase 1.0: 7 selectors**.

### Phase 1.5 selectors (this spec)

| Selector | Purpose | Used by (web) |
|---|---|---|
| `currentMonth(txns, ledgerId?)` | Most recent month with activity | Insights, Budgets |
| `prevMonth(month)` | Previous month string | Insights, Budgets |
| `monthlySpending(txns, ledgerId, endMonth, n)` | Last N months of total spend | Insights (spending trend) |
| `dailySpending(txns, ledgerId, endDate, n)` | Last N days of daily spend | Insights (daily chart) |
| `netWorthByMonth(txns, accounts, endMonth, n)` | Last N months of net worth | Insights (net worth chart) |
| `netWorthExplained(txns, accounts, ledgerId, month)` | Net-worth delta decomposition | Insights (net worth explained) |
| `monthForecast(txns, accounts, ledgerId, n)` | Linear-regression forecast for next N months | Insights (forecast card) |
| `incomeCategoryFlow(txns, ledgerId, endMonth, n)` | Monthly income by category | Insights (income breakdown) |
| `monthlyCashflow(txns, ledgerId, endMonth, n)` | Monthly income vs expense | Insights (cashflow chart) |
| `topCategoryDeltas(txns, ledgerId, month, n)` | Top N categories by month-over-month delta | Insights (top movers) |
| `recentExpenses(txns, ledgerId, limit)` | Most recent N expenses | Insights (recent activity) |
| `findDuplicate(txns, candidate)` | Find a duplicate transaction | Activity tab (duplicate guard on add) |
| `weeklyDigest(txns, ledgerId, anchor)` | 7-day spend summary | Insights (weekly card), Phase 6 notifications |
| `holdingsForAccount(holdings, accountId)` | Holdings for one account | Insights (holdings breakdown) |
| `holdingValue(h)` | Current value of one holding | Insights (holdings breakdown) |
| `holdingGainLoss(h)` | Unrealized gain/loss for one holding | Insights (holdings breakdown) |
| `holdingsValueForAccount(holdings, accountId)` | Total value of holdings for one account | Insights (holdings breakdown) |
| `investmentAccountTotal(account, holdings)` | Total value of an investment account (cash + holdings) | Accounts tab (investment account row) |
| `accountForecast(txns, account, n)` | Forecast for one account over next N days | Account Detail (Phase 1.0 may or may not need) |
| `balanceSeries(txns, accountId, currentBalance)` | Historical balance series for one account | Account Detail (Phase 1.0 may or may not need) |
| `netWorthSeries(txns, accounts, ledgerId)` | Net worth time series | Insights (net worth chart) — `netWorthByMonth` may supersede |
| `netWorthByAccountType(accounts, ledgerId)` | Net worth broken down by account type | Insights (net worth explained) |
| `selectTransfers(txns, accounts, ledgerId)` | Paired transfer entries | Activity tab (transfer drill-down) |
| `unrealizedFx(txns, accounts, ledgerId)` | Unrealized FX gain/loss | Insights (FX card) |
| `suggestCategory(tx, options)` | Category suggestion for a new transaction | Phase 2 (Add Transaction form) — but port the selector now for parity coverage |

**Total Phase 1.5: 25 selectors**.

The 25 selectors are organized into **8 groups** in the `Selectors`
module (§4) by their output shape, not by feature:

1. **Time series** (8 selectors): `currentMonth`, `prevMonth`,
   `monthlySpending`, `dailySpending`, `netWorthByMonth`, `monthForecast`,
   `incomeCategoryFlow`, `monthlyCashflow`
2. **Top-N deltas** (2 selectors): `topCategoryDeltas`, `recentExpenses`
3. **Explanations** (2 selectors): `netWorthExplained`,
   `netWorthByAccountType`
4. **Net worth** (1 selector): `netWorthSeries`
5. **Holdings** (4 selectors): `holdingsForAccount`, `holdingValue`,
   `holdingGainLoss`, `holdingsValueForAccount`
6. **Account totals** (3 selectors): `investmentAccountTotal`,
   `accountForecast`, `balanceSeries`
7. **Transfers / duplicates** (2 selectors): `selectTransfers`,
   `findDuplicate`
8. **Misc** (3 selectors): `weeklyDigest`, `unrealizedFx`,
   `suggestCategory`

(Counting `accountForecast` and `balanceSeries` separately in
"Account totals" gives 3, not 2. The 8 groups + 25 selectors check
out.)

## §3. Selectors module layer rules

Per the Phase 1.0 spec's §3, the `Selectors` module is the **8th
FinchCore module** (added in Phase 1.5; the 7 from Phase 1.0 stay
unchanged).

**Layer rules** (the only allowed import directions; enforced by
`FinchCoreArchitectureTests`):

- `Selectors` imports `DB`, `Money`, `Project`
- `Selectors` does NOT import `Schema`, `Audit`, `Pack`, `ICloud` —
  the selectors are read-only and don't depend on the pack engine

```
┌──────────┐
│  Money   │  (unchanged from Phase 1.0)
└────┬─────┘
     │
┌────┴─────┐
│ Project  │  (unchanged; the in-memory Tx[] cache)
└────┬─────┘
     │
┌────▼─────┐
│Selectors │  (NEW in Phase 1.5)
└────┬─────┘
     │
┌────▼─────┐
│  DB      │  (unchanged; raw SQL for some selectors)
└──────────┘
```

`Selectors` is a **read-only** module — it consumes the projected
`Tx[]` from `Project` and (for selectors that need it) raw DB rows
via `DB`. It does not write; it does not depend on `Audit` (the
audit gate is the import-time check, not a per-selector check).

**All 25 selectors are pure functions** over their inputs (no IO,
no time-dependent hidden state). They take either:
- A pre-projected `Tx[]` (matching the web's `lib/select.ts` shape)
- A pre-fetched `AccountRow[]` and `Holding[]` (for selectors that
  need accounts/holdings)
- A pre-fetched `RateSnapshot` (for FX selectors — this lives in
  the schema's `rates` table; see §6)

The web's selectors all read from the in-memory `Tx[]` (or
`AccountRow[]` / `Holding[]` arrays) — they don't hit the DB
directly. The Swift port matches: `FinchStore` keeps the projected
`Tx[]` in memory after open (from Phase 1.0); selectors read from
that array.

**Two exceptions** in the web's selectors that hit the DB directly:

- `monthForecast` reads historical `RateSnapshot` rows for FX
  conversion
- `weeklyDigest` reads the `app_state` table for the user's
  configured "first day of week" preference

Both of these are **narrow DB lookups** (one row each), not the
full transaction query. The Swift port handles them via a
`Selectors.DBContext` struct that holds a `GRDB.DatabaseReader`
reference:

```swift
public struct Selectors {
    public let db: any GRDB.DatabaseReader  // for narrow lookups
    public let money: Money

    public func monthForecast(txns: [Tx], accounts: [AccountRow], ledgerId: String, n: Int) throws -> [MonthForecast] {
        let rates = try db.read { db in try RateSnapshot.fetchAll(db) }  // one DB read
        return /* ... pure compute over (txns, accounts, rates) ... */
    }
}
```

This keeps the selector bodies pure (one DB read at the top, then
pure compute) while matching the web's pattern (which reads rates
via the store at call time).

## §4. JSON-golden parity test infrastructure

This is the **new piece** of Phase 1.5 — the JSON-golden parity
harness. Phase 1.0 has `.db` round-trip parity + `auditLedger`
parity + `Tx` projection parity. Phase 1.5 adds **per-selector
JSON-golden parity**.

### 4.1 — What the harness does

For each of the 25 ported selectors:

1. The web side has a `bun test lib/select.test.ts` test that
   constructs a known input, runs the selector, and asserts the
   output
2. The fixture export script (`frontend/scripts/export-fixtures.ts`,
   which already exists from Phase 1.0) **also** serializes the
   selector test inputs + expected outputs to JSON
3. The Swift `ParityTests` target reads the JSON, constructs the
   same input, runs the Swift selector, and asserts the output
   matches to the cent

The JSON format is one file per selector (25 files) at
`ios/FinchCore/Tests/Fixtures/selectors/<selector-name>.json`:

```json
{
  "selector": "monthlySpending",
  "cases": [
    {
      "name": "last 3 months of spending for a ledger with 5 months of data",
      "input": {
        "txns": [...],
        "ledgerId": "personal",
        "endMonth": "2026-06",
        "n": 3
      },
      "expected": [
        { "m": "2026-04", "v": 1234.56 },
        { "m": "2026-05", "v": 2345.67 },
        { "m": "2026-06", "v": 1500.00 }
      ]
    },
    ...
  ]
}
```

For selectors that take multiple inputs (e.g., `monthForecast`
takes `txns`, `accounts`, `ledgerId`, `n`), the JSON shape
mirrors the function signature.

### 4.2 — Fixture export script changes

The Phase 1.0 `frontend/scripts/export-fixtures.ts` already writes
the 8 audit-corruption `.finch` fixtures + 1 sample `.finch` + 1
pre-DE `.finch`. Phase 1.5 extends it to also write the 25
selector JSON fixtures.

The script becomes:

```typescript
// frontend/scripts/export-fixtures.ts
import { test } from 'bun:test';
import { /* selectors */ } from '@/lib/select';
import { /* fixture txns / accounts / etc. */ } from '@/lib/db/seed';

// Re-run every select.test.ts test case and serialize (input, expected) to JSON.
for (const testCase of extractTestCases('select.test.ts')) {
  // Run the test, capture the (input, output) tuple, serialize.
  const input = testCase.input;
  const expected = testCase.fn(input);
  writeFixture(testCase.name, { selector: testCase.selector, input, expected });
}
```

The script is invoked by the macos CI job (from
`IOS_MACOS_PHASE_1_DESIGN §9`) before `FinchCore` tests run, so
fixtures stay in sync with the web. The script is checked into the
repo at `frontend/scripts/export-fixtures.ts` with its own
`bun test` smoke test.

**The script's output is the source of truth for the Swift
parity tests.** If the web's `select.test.ts` test cases change,
the script regenerates the JSON, and the Swift parity tests run
against the new expected outputs.

### 4.3 — Swift `ParityTests` extension

Phase 1.0's `ParityTests` target has 3 test types:
`Tx` projection parity, `auditLedger` parity, `.db` round-trip
parity. Phase 1.5 adds a 4th: **per-selector JSON-golden parity**.

The Swift test runner discovers all `.json` files in
`ios/FinchCore/Tests/Fixtures/selectors/`, deserializes each, and
generates one Swift test case per JSON case. The test runner is
generic:

```swift
// ios/FinchCore/Tests/ParityTests/SelectorParityTests.swift
final class SelectorParityTests: XCTestCase {
    func test_AllSelectors() throws {
        let fixturesDir = Bundle.module.url(forResource: "Fixtures/selectors", withExtension: nil)!
        let jsonFiles = try FileManager.default.contentsOfDirectory(at: fixturesDir, ...)

        for jsonFile in jsonFiles {
            let fixture = try JSONDecoder().decode(SelectorFixture.self, from: Data(contentsOf: jsonFile))
            try runParityTest(fixture)
        }
    }

    private func runParityTest(_ fixture: SelectorFixture) throws {
        let store = try seededStore()
        let input = fixture.input.toSwiftValues(store: store)
        let actual = try runSelector(fixture.selector, input, store: store)
        XCTAssertEqual(actual, fixture.expected, "selector: \(fixture.selector), case: \(fixture.name)")
    }
}
```

**SwiftPM resource note**: `Bundle.module` is generated for
the test target, and is the **test target's** bundle. The
fixtures at `ios/FinchCore/Tests/Fixtures/` are accessed via
`Bundle.module` only if the SwiftPM `testTarget` declares
`resources: [.copy("Fixtures")]`. The `Package.swift`
configuration:

```swift
.testTarget(
    name: "ParityTests",
    dependencies: ["FinchCore"],
    resources: [.copy("Fixtures")]
)
```

Without this, `Bundle.module.url(forResource:withExtension:)`
returns `nil` and the force-unwrap crashes. The fixtures
are exported by the web's `frontend/scripts/export-fixtures.ts`
(per Phase 1.0 §8) and committed to `ios/FinchCore/Tests/Fixtures/`.

`actual` and `expected` are `Decimal`-typed throughout; equality
is to the cent (matching the web's `select.test.ts` assertions).

### 4.4 — Test target structure

After Phase 1.5, the 3 SwiftPM test targets are:

- `FinchCoreTests` — unit tests for each module (`Money`, `DB`,
  `Schema`, `Project`, `Audit`, `Pack`, **`Selectors`**)
- `ParityTests` — the cross-implementation parity gate
  (`Tx` projection + `auditLedger` + `.db` round-trip + **per-
  selector JSON-golden**)
- `FinchAppTests` — UI snapshot tests for the **5 tabs**
  (Accounts, Activity, Budgets, Insights, Settings)

No structural change to the CI workflow; the macos job from
`IOS_MACOS_PHASE_1_DESIGN §9` runs unchanged. The fixture export
script's selector-export step is added to the `Export fixtures`
CI step.

## §5. Insights tab UI

The Insights tab is the 5th tab in the SwiftUI `TabView`. It's
**read-only** — every figure is computed from imported data; no
user input. The tab is scrollable (a single `ScrollView` with
vertically-stacked cards).

### 5.1 — Card layout

```
┌─────────────────────────────────────┐
│  Insights          June 2026  ◀ ▶   │
├─────────────────────────────────────┤
│  💰 Net worth                        │
│     $69,752.00                       │
│     ▲ $1,234.56 (1.8%) vs May       │
│     ┌────────────────────────────┐  │
│     │     [6-month line chart]   │  │
│     │     ──────────────────     │  │
│     │                            │  │
│     └────────────────────────────┘  │
│                                      │
│  📊 Monthly cashflow                 │
│     ┌────────────────────────────┐  │
│     │  [stacked bar chart:       │  │
│     │   green = income,          │  │
│     │   red = expense,           │  │
│     │   last 6 months]           │  │
│     └────────────────────────────┘  │
│                                      │
│  🔮 Forecast (next 30 days)         │
│     Expected spend:  $1,847.00       │
│     Range:          $1,500 - $2,200 │
│     [Method: linear regression      │
│      over last 90 days of spend]     │
│                                      │
│  📈 Top movers (this month)          │
│     🛒 Groceries      +$87 (vs May) │
│     ☕ Food & Dining   -$23 (vs May) │
│     🚗 Transport       +$45 (vs May)│
│     ...                              │
│                                      │
│  💼 Holdings (investment accounts)   │
│     Vanguard Brokerage               │
│       Cash:        $5,000.00         │
│       Holdings:    $37,318.55        │
│       Total:       $42,318.55        │
│       Gain/loss:   ▲ $1,234 (+3.2%) │
│                                      │
│  📅 Weekly digest                    │
│     This week (Sun → Sat):           │
│       Spent:      $234.56            │
│       Top cat:   Groceries ($87.23)  │
│       vs last week: ▼ $12 (-5%)      │
│                                      │
│  💱 Unrealized FX                    │
│     Total unrealized: ▲ $234.56     │
│     Per account:                     │
│       EUR account:    ▲ $123.45     │
│       JPY account:    ▲ $111.11     │
└─────────────────────────────────────┘
```

### 5.2 — Cards and their selectors

| Card | Selectors | Visual |
|---|---|---|
| Net worth | `netWorthByMonth` + `netWorthExplained` (header) + `netWorthSeries` (line chart data) | Swift Charts `LineChart` |
| Monthly cashflow | `monthlyCashflow` | Swift Charts stacked `BarChart` (income green, expense red) |
| Forecast | `monthForecast` | Text card (figure + range + method) |
| Top movers | `topCategoryDeltas` | List of (category, delta, vs-last-month) |
| Holdings | `holdingsValueForAccount` + `holdingValue` + `holdingGainLoss` + `holdingsForAccount` | Per-account block |
| Weekly digest | `weeklyDigest` | Text card (spent + top cat + delta) |
| Unrealized FX | `unrealizedFx` | Text card (total + per-account breakdown) |

### 5.3 — Per-ledger display-currency override UI

In **Settings → Active ledger → Display currency**, the user can
pick a currency different from the ledger's base. The choice is
persisted in the local DB's `app_state` table (key:
`displayCurrencyByLedger`, holding a JSON `{[ledgerId]: currency}`
map) — matching the web's `setDisplayCurrency` action in
`lib/db/domain/ledgers/mutations.ts:58-64`.

When the display currency changes, the **Insights tab re-renders
in real time** (the `FinchStore`'s `@Observable` state changes,
all card views re-evaluate their `Money.formatted(in:)` calls).

`Settings` shows the active ledger's current display currency
with a "Change" button. Tapping opens a picker sheet:

```
┌─────────────────────────────────────┐
│  Display currency        [Cancel]   │
├─────────────────────────────────────┤
│  ( ) USD — Ledger base              │
│  ( ) SGD                             │
│  ( ) CNY                             │
│  ( ) JPY                             │
│  ( ) EUR                             │
│  ( ) ...                             │
└─────────────────────────────────────┘
```

Picking a non-base currency triggers an FX conversion at the
active rate from the `rates` table (no rate editor in Phase 1.5;
that's Phase 4 "FX / base tools").

### 5.4 — Month navigation

The Insights tab header shows the current month with `◀ ▶`
arrows for month navigation. `◀` calls `prevMonth`; `▶` is
disabled at the current month (no future data).

`currentMonth(txns, ledgerId?)` is the initial value. As the user
navigates, all cards re-evaluate against the new "end month."

### 5.5 — Empty / loading / error states

- **Empty** (no data in the active ledger): centered icon + "No
  data for this ledger" + hint "Import a .finch from the
  Settings tab."
- **Loading** (the `FinchStore` is still projecting after a
  recent import): full-tab `ProgressView` (the import-time
  loading is in Settings; Insights re-renders as soon as the
  projection finishes)
- **Error** (a selector throws — should never happen in 1.5;
  selectors are pure): the affected card shows an inline error
  banner "Could not compute this figure" with a "Retry" button

### 5.6 — Accessibility

- Dynamic Type across all text (per the Phase 1.0 spec's §5)
- VoiceOver labels on every control
- Charts: each chart has a `Text` accessibility summary
  (e.g., "Net worth: $69,752.00, up 1.8% vs May") that's
  always rendered (not just on VoiceOver focus) so users can
  read it without enabling VoiceOver
- Color-blind support: the income/expense cashflow chart uses
  **green/red** but with a **pattern fill** in addition (the
  web's `lib/budgets/rollover.ts` does the same)

## §6. Selectors module API surface

The `Selectors` module exposes 25 functions. The signature
mirrors the web's `lib/select.ts` for direct portability. Inputs
are in the canonical `Tx` / `AccountRow` / `Holding` shapes
(ported in Phase 1.0). Outputs are typed Swift structs
(mostly value types).

```swift
// Selectors/TimeSeries.swift
public func currentMonth(txns: [Tx], ledgerId: String? = nil) -> String
public func prevMonth(month: String) -> String
public func monthlySpending(txns: [Tx], ledgerId: String, endMonth: String, n: Int) -> [MonthlySpending]
public func dailySpending(txns: [Tx], ledgerId: String, endDate: String, n: Int) -> [DailySpending]
public struct MonthlySpending: Equatable, Sendable { let m: String; let v: Decimal }
public struct DailySpending: Equatable, Sendable { let date: String; let value: Decimal }

// Selectors/NetWorth.swift
public func netWorthByMonth(txns: [Tx], accounts: [AccountRow], endMonth: String, n: Int) throws -> [NetWorthByMonth]
public func netWorthExplained(txns: [Tx], accounts: [AccountRow], ledgerId: String, month: String) throws -> NetWorthExplained
public func netWorthByAccountType(accounts: [AccountRow], ledgerId: String) -> [AccountTypeNetWorth]
public func netWorthSeries(txns: [Tx], accounts: [AccountRow], ledgerId: String) throws -> [NetWorthPoint]
public struct AccountTypeNetWorth: Equatable, Sendable {
    let accountType: String  // "checking", "savings", "investment", etc.
    let total: Decimal       // signed, in ledger base
}

// Selectors/Forecast.swift
public func monthForecast(txns: [Tx], accounts: [AccountRow], ledgerId: String, n: Int) throws -> [MonthForecast]
public struct MonthForecast: Equatable, Sendable {
    let month: String
    let expected: Decimal
    let low: Decimal
    let high: Decimal
    let method: ForecastMethod  // .linearRegression, .naiveAverage
}

// Selectors/Cashflow.swift
public func incomeCategoryFlow(txns: [Tx], ledgerId: String, endMonth: String, n: Int) -> [IncomeCategoryFlow]
public func monthlyCashflow(txns: [Tx], ledgerId: String, endMonth: String, n: Int) -> [MonthlyCashflow]
public struct MonthlyCashflow: Equatable, Sendable {
    let m: String; let inc: Decimal; let exp: Decimal
}

// Selectors/Deltas.swift
public func topCategoryDeltas(txns: [Tx], ledgerId: String, month: String, n: Int) -> [CategoryDelta]
public struct CategoryDelta: Equatable, Sendable {
    let categoryId: String; let categoryName: String
    let current: Decimal; let previous: Decimal; let delta: Decimal
}

// Selectors/Activity.swift
public func recentExpenses(txns: [Tx], ledgerId: String, limit: Int = 5) -> [RecentExpense]
public func findDuplicate(txns: [Tx], candidate: Tx) -> Tx?
public func selectTransfers(txns: [Tx], accounts: [AccountRow], ledgerId: String) -> [Transfer]

// Selectors/Weekly.swift
public func weeklyDigest(txns: [Tx], ledgerId: String, anchor: String) -> WeeklyDigest?
public struct WeeklyDigest: Equatable, Sendable {
    let anchor: String  // "YYYY-MM-DD"
    let totalSpent: Decimal
    let topCategory: String?
    let topCategoryAmount: Decimal
    let previousWeekDelta: Decimal
}

// Selectors/Holdings.swift
public func holdingsForAccount(holdings: [Holding], accountId: String) -> [Holding]
public func holdingValue(h: Holding) -> Decimal?
public func holdingGainLoss(h: Holding) -> Decimal?
public func holdingsValueForAccount(holdings: [Holding], accountId: String) -> Decimal
public func investmentAccountTotal(account: AccountRow, holdings: [Holding]) -> Decimal

// Selectors/Account.swift
public func accountForecast(txns: [Tx], account: AccountRow, n: Int) throws -> [AccountForecastPoint]
public func balanceSeries(txns: [Tx], accountId: String, currentBalance: Decimal) -> [Decimal]

// Selectors/FX.swift
public func unrealizedFx(txns: [Tx], accounts: [AccountRow], ledgerId: String) throws -> [UnrealizedFx]
public struct UnrealizedFx: Equatable, Sendable {
    let accountId: String; let currency: String
    let unrealized: Decimal  // signed, in ledger base
}

// Selectors/Suggestion.swift
public func suggestCategory(tx: Tx, options: [Category]) -> String?  // category id
```

All 25 functions are `throws` if they need a DB lookup (for
`RateSnapshot` or `app_state`); the rest are non-throwing pure
functions. Every function is `Equatable, Sendable` for the
parity tests.

**Note on `monthForecast`**: the web's `monthForecast` uses
linear regression over the last 90 days of spend. The Swift port
matches. The `ForecastMethod` enum lets the parity test verify
both implementations use the same method (if the web's
implementation changes, the parity test surfaces it).

## §7. Parity test file layout

After Phase 1.5, `ios/FinchCore/Tests/Fixtures/` contains:

```
Fixtures/
├── sample.finch                     # Phase 1.0: clean sample DB
├── pre-de.finch                     # Phase 1.0: pre-DE DB for migration round-trip
├── unbalanced.finch                 # Phase 1.0: audit corruption fixtures (× 8)
├── unsealed.finch
├── currency-mismatch.finch
├── kind-shape.finch
├── cross-ledger.finch
├── tb-nonzero.finch
├── balance-drift.finch
├── base-amount-mismatch.finch
├── tx-projection.json               # Phase 1.0: Tx[] golden for the sample DB
└── selectors/                       # NEW in Phase 1.5
    ├── currentMonth.json
    ├── prevMonth.json
    ├── monthlySpending.json
    ├── dailySpending.json
    ├── netWorthByMonth.json
    ├── netWorthExplained.json
    ├── monthForecast.json
    ├── incomeCategoryFlow.json
    ├── monthlyCashflow.json
    ├── topCategoryDeltas.json
    ├── recentExpenses.json
    ├── findDuplicate.json
    ├── weeklyDigest.json
    ├── holdingsForAccount.json
    ├── holdingValue.json
    ├── holdingGainLoss.json
    ├── holdingsValueForAccount.json
    ├── investmentAccountTotal.json
    ├── accountForecast.json
    ├── balanceSeries.json
    ├── netWorthSeries.json
    ├── netWorthByAccountType.json
    ├── selectTransfers.json
    ├── unrealizedFx.json
    └── suggestCategory.json
```

25 JSON files for selectors. Each is generated by
`frontend/scripts/export-fixtures.ts` and committed to git
(they're small — 1-10 KB each).

## §8. Open questions

The plan's §14.1 still-open questions mostly land in later phases.
For Phase 1.5 specifically:

**Not blocking Phase 1.5 (decide later)**:

- **Day-1 locales**: the iOS app uses `Localizable.strings`; the
  day-1 list is a product call. The web ships `en + zh-CN`. iOS
  defaults to `en`; `zh-CN` lands if/when the user base
  warrants. Not blocking 1.5.
- **iCloud folder naming polish**: the user-visible "finch/"
  subfolder name in iCloud Drive is auto-created; polish (icon,
  custom folder name) is a follow-up.
- **Insights tab on iPad layout**: in Phase 1.5, the Insights
  tab renders the same as on iPhone (a vertical stack of
  cards). The iPad-adaptive layout (Phase 3) will rearrange
  into a 2-column grid.

**Specifically for the JSON-golden harness**:

- **Fixture staleness**: if the web's `select.test.ts` test
  cases change, the fixture export script regenerates the JSON
  in CI. We commit the regenerated JSON. If a developer changes
  the web's selector logic without updating `select.test.ts`,
  the parity tests don't catch it. Mitigation: every PR to
  `lib/select.ts` must include an updated `select.test.ts` case
  (enforced by code review; not automated).
- **Number-of-cases per selector**: each JSON fixture has
  multiple test cases. How many? The web's `select.test.ts` has
  ~5-10 cases per selector; matching that gives ~150-250 total
  cases across the 25 selectors. That's a manageable test
  runtime (each case is millisecond-scale).

**Specifically for the Insights tab**:

- **`monthForecast` method**: the web uses linear regression
  over the last 90 days. Should the iOS port match exactly, or
  can it use a different method (e.g., a moving average)? Per
  the plan's §12, "parity suite" implies exact match. The Swift
  port matches exactly. If the web's method is later swapped
  for a better one, the parity test surfaces it.
- **Chart libraries**: Swift Charts is iOS 16+; we target iOS
  26+. The 2 chart types we need (line + stacked bar) are
  well-supported by Swift Charts. No third-party chart
  library needed.
- **Top-N defaults**: each list card (top movers, holdings,
  etc.) needs a default N (how many to show). The web uses
  N=5 for "top movers" and shows all holdings. Phase 1.5
  matches.

**Not blocking Phase 1.5 because they're Phase 2+ by design**:

- Phase 2 (write chokepoint) — `findDuplicate` and
  `suggestCategory` are read-side selectors that the write
  surface will consume. We port the selectors now so the parity
  suite is complete; Phase 2 wires them into the Add
  Transaction form.
- Phase 4 (power features) — saved searches, bulk recategorize.
  These may use selectors from Phase 1.5 but are not built in
  1.5.
- Phase 5 (auto-pack debounce) — `monthForecast` may be used by
  the "Sync now" UI to surface a forecast diff. Not built in
  1.5.

## §9. Out of scope (firm)

These are explicitly NOT in Phase 1.5:

- **Write paths** — the 74-action chokepoint is Phase 2.
- **iPad / macOS adaptive layout** — Phase 3. Phase 1.5's
  Insights tab renders the same on iPhone and (the Phase 3)
  iPad.
- **Power features** (reconcile, rules engine + builder, transfers
  CRUD, merchants / categories / tags admin, saved searches,
  bulk recategorize, FX / base tools) — Phase 4.
- **Auto-pack debounce + iCloud folder-watcher** — Phase 5.
- **Receipt attachments + App Intents / Siri / Share Extension
  receipts / Spotlight / notifications / biometric lock** —
  Phase 6.
- **Widgets / Live Activities / Watch** — Phase 7.
- **Row-level sync** — Phase 8.
- **In-app theme override** — Phase 1.5 follows the system
  light/dark setting.
- **Holding add / edit / price-update UI** — read-only display
  in Phase 1.5; full holdings CRUD is Phase 2.
- **Rate editor** — the per-ledger display-currency override
  uses the existing `rates` table values; editing rates is
  Phase 4 ("FX / base tools").
- **Saved searches** — Phase 4.
- **Anomaly threshold tuning** — the existing
  `anomalyScore` thresholds from the web are used as-is. UI
  for tuning thresholds is Phase 4.
- **Weekly digest notification** — the `weeklyDigest` selector
  is ported; using it in a local notification is Phase 6.

## §10. Spec self-review

(Inline review at write time; not part of the published spec.)

- **Placeholders**: none. Every section has concrete content.
  The 25-selector classification table is exhaustive.
- **Internal consistency**: §3's `Selectors` layer rules match
  the Phase 1.0 spec's §3 layer diagram. §6's API surface
  matches §2's 25-selector classification. §4's `ParityTests`
  extension matches the Phase 1.0 spec's §8.3 test target
  structure.
- **Scope**: focused on Phase 1.5. Phase 1.0's 7 selectors are
  explicitly enumerated as "do not re-port in 1.5." Phase 2+
  work is referenced but not designed here. §9 enumerates the
  firm out-of-scope items.
- **Ambiguity**: §2's 25-selector table includes the web's
  exact selector name + a 1-line purpose + the web consumer.
  §6's API surface has typed structs for non-trivial outputs
  (`MonthlySpending`, `MonthForecast`, `DailySpending`,
  `AccountTypeNetWorth`, etc.). §4's JSON fixture format is
  shown with a concrete example. The `Selectors.DBContext`
  pattern (§3) is explicit about which selectors need DB
  access and why. Cross-checked: all 25 selectors appear
  1:1 in §2's classification table, §6's API surface, and
  §7's fixture file list.
