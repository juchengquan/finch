# Month-sectioned account transactions — design

**Status:** design, approved 2026-07-22. Implementation plan to follow.
**Ask:** "In each account, like in all activities, we should also split transactions by months" — plus, from the brainstorm, per-month header figures on both surfaces.

## 1. What this builds

The **Activity feed** already groups its transactions into month sections behind a persisted
"Group by month" toggle. The **account detail** transaction list does not — it shows a flat
"Transactions" section (plus a separate "To confirm" pending bucket).

This change:

1. **Extracts** the feed's inline month-grouping into a shared, unit-tested pure helper, and
   **refactors the feed to use it** (so there is one implementation, not a second copy that can
   drift).
2. **Month-sections the account detail's confirmed transactions**, honoring the same toggle.
3. Adds a **per-month figure to both surfaces' section headers**: net change everywhere, plus
   the account's end-of-month balance on the account detail (only).

## 2. Decisions (from the brainstorm)

| # | Decision | Rationale |
|---|---|---|
| 1 | **Honor the shared `finch.feed.groupByMonth` toggle** | One Settings toggle governs both the feed and account detail; no new state. Off ⇒ both flat, on ⇒ both sectioned. |
| 2 | **Account header = net change · end-of-month balance; feed header = net change** | The account view has a natural place for a running balance; the feed spans accounts, so a balance there is meaningless. |
| 3 | **Pending stays ungrouped** | "To confirm (N)" remains its own bucket above the month sections — month headers on a small actionable list are noise. |
| 4 | **Account rows keep a date on every line** | Not adopting the feed's per-day date de-dup (`dateShownIds`); account rows carry a running balance, where a per-row date reads clearly. `TxRow` is called with its defaults (`showDate: true`), unchanged. |
| 5 | **Scope = Activity feed + Account detail** | Budget detail and Ledger detail also show flat transaction lists; left as a fast-follow (§8). |

The toggle key `finch.feed.groupByMonth` becomes a slight misnomer (no longer feed-only), but the
Settings label already reads generic ("Group by month") and renaming the key would reset every
user's stored preference — so **keep the key**, add a one-line comment noting both consumers.

## 3. Architecture — the shared helper

A new app-level file `ios/FinchApp/Sources/FinchApp/Common/MonthGrouping.swift`, pure and
testable (operates on `[Tx]`, no store/`Date()`/I/O):

```swift
enum MonthGrouping {
    struct Section: Identifiable { let id: String; let txns: [Tx] }   // id = "yyyy-MM"

    /// Group date-descending txns into month sections, order preserved.
    static func sections(_ txns: [Tx]) -> [Section] {
        var order: [String] = []; var byMonth: [String: [Tx]] = [:]
        for t in txns {
            let key = String(t.date.prefix(7))                        // "yyyy-MM"
            if byMonth[key] == nil { order.append(key) }
            byMonth[key, default: []].append(t)
        }
        return order.map { Section(id: $0, txns: byMonth[$0] ?? []) }
    }

    /// "2026-09" -> "September 2026" (device locale, wide month).
    static func label(_ key: String) -> String {
        guard let d = AppDate.isoDay.date(from: "\(key)-01") else { return key }
        return d.formatted(.dateTime.month(.wide).year())
    }

    /// Net change of a month's txns, in ledger-base amount (Tx.amount is base).
    static func net(_ txns: [Tx]) -> Double { txns.reduce(0) { $0 + $1.amount } }
}
```

This is a **verbatim lift** of the feed's existing grouping (`String(txn.date.prefix(7))`,
`monthLabel`) — behavior-preserving, so the feed cannot regress.

**`ActivityTab` refactor:** replace the inline `byMonth`/`order` loop in `recompute()` with
`MonthGrouping.sections(...)`, and the private `monthLabel` with `MonthGrouping.label`. The feed's
`DaySection` type is removed in favor of `MonthGrouping.Section`. The `dateShownIds` day-de-dup
logic stays in the feed (it is a separate feed concern, not month-grouping).

## 4. Account detail changes

`AccountDetailView.transactionsSection(_:)`:

- Read the toggle: `@AppStorage("finch.feed.groupByMonth") private var groupByMonth = true`.
- **Pending** ("To confirm (N)") is unchanged — its own ungrouped `Section` above the rest.
- **Confirmed**:
  - `groupByMonth == false` → the existing single flat `Section("Transactions")` (unchanged).
  - `groupByMonth == true` → one `Section` per `MonthGrouping.sections(confirmed)`, header =
    `monthHeader(section)`.
- The row builder `txRow(_:)` and its `TxRow(...)` call are **unchanged** (defaults keep the date
  and running balance per row).

**Header:** `"<label>   <net> · <bal>"` rendered as the section header. Both figures are
privacy-aware base→display:

- **net** = `store.displayMoneyBase(MonthGrouping.net(section.txns))`, signed.
- **bal** = `store.displayMoneyBase(store.runningBalanceBase(for: section.txns.first!))` — the
  running balance *after the newest transaction in the month*. Because the list is
  date-descending, that is the section's first row, so the header balance equals that row's own
  running-balance line exactly (same `runningBalanceBase` cache). `section.txns` is never empty
  (a section only exists because it has txns), so `.first!` is safe.

Header layout: label leading; `net · bal` trailing, `.caption`/secondary, consistent with the
existing header density. `.textCase(nil)` so the month label isn't upper-cased.

## 5. Activity feed changes

The feed's month headers are currently the plain `MonthGrouping.label(section.id)`. Add the
net-change figure:

- header = `"<label>   <net>"`, `net = store.displayMoneyBase(MonthGrouping.net(section.txns))`.
- No balance (the feed spans accounts).

Applies only when `groupByMonth == true` (the feed's existing flat mode is unchanged). Note the
feed already caps rows at `visibleCount` (pagination), so a section's `net` is the net of the
**shown** txns of that month — acceptable and consistent with what the user sees; the last visible
month may be partial. (Documented, not a bug: the figure describes the visible rows.)

## 6. Money, privacy, edge cases

- **Currency:** `Tx.amount` is ledger-**base**; both figures go through `displayMoneyBase`
  (base→display), the same helper the account's running-balance rows already use, so they stay
  mutually consistent and are masked to `••••` under privacy mode.
- **Toggle off:** both surfaces render exactly as today (flat) — no month sections, no header
  figures.
- **A month with only pending items:** produces no confirmed section (pending shows in its own
  bucket); no empty month header.
- **FX / multi-currency account:** figures are in display currency via the shared helper — no
  special-casing; the account's header balance (`displayMoney(a.balance, from:)`, account
  currency) is a separate existing element and is untouched.
- **Sorting:** account detail already orders `store.transactions(for:)` date-descending; sections
  inherit that order (newest month first).

## 7. Testing

- **`MonthGroupingTests` (FinchAppTests)** — pure-helper unit tests:
  - `sections` groups by `yyyy-MM`, preserves date-descending order, one section per distinct
    month, a single-month input → one section, empty input → empty.
  - `label` maps `"2026-09"` → the wide-month/year string; a malformed key returns the key.
  - `net` sums signed base amounts; empty → 0.
- **On device (`idb`):** account detail with the toggle **on** shows month headers with
  `net · bal`, the `bal` matching the newest row's running-balance line; toggle **off** → flat;
  the feed's headers show `net`; a foreign-currency account renders figures in display currency;
  privacy mode masks them.
- Both `FinchApp` and `FinchMac` build.

## 8. Out of scope

- **Budget detail / Ledger detail** month sectioning (same flat-list treatment; a mechanical
  fast-follow reusing `MonthGrouping` once this ships).
- Per-day date de-dup in account detail (decision #4 — keep per-row dates).
- Renaming the `finch.feed.groupByMonth` key (would reset stored prefs; not worth it).
- Any change to the feed's pagination or the account's opening-balance/holdings/sparkline sections.
