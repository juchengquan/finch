# Budget-detail month sections — design

**Status:** design, approved 2026-07-22. Fast-follow to #595 (`plans/ios-macos/2026-07-22-account-month-sections-design.md` §8).

## What this builds — and what it deliberately does not

The #595 design §8 named "Budget detail and Ledger detail" as flat transaction lists to
month-section next. Exploring the code corrected that:

- **Ledger detail needs no change.** `LedgerDetailView` has no transaction list of its own — it
  shows net worth / this-month / accounts and a **"View all activity"** link that pushes
  `ActivityFeedView`, which #595 already month-sectioned. The ledger's transactions are already
  grouped. **Out of scope, nothing to do.**
- **Budget detail** (`BudgetDetailView`) has two transaction lists — **"This cycle"** (the current
  cycle) and **"Selected cycle"** (a past cycle, from the #587 history drill-in). Both are scoped to
  **one budget cycle window** (`Selectors.budgetMatchedTransactions` → `cycleWindow`), not a full
  history.

Because a budget list is a single cycle, month-sectioning only helps when that cycle spans more than
one calendar month — a **monthly** budget's cycle is ~one month, so sectioning would add a single
redundant header. So we section **only when the transactions actually span >1 month**; otherwise the
list stays flat. This self-adjusts: monthly budgets stay clean; quarterly/yearly (and off-calendar)
cycles get useful sections. No per-frequency special-casing.

## Behaviour

For each of the two lists (`transactionsSection`'s "This cycle" and `cycleSection`'s "Selected
cycle"), given the matched `txns`:

- Compute `let secs = MonthGrouping.sections(txns)` **once**.
- If `groupByMonth && secs.count > 1` → render one `Section` per month, header =
  `MonthGrouping.label(section.id)` leading + `store.displayMoneyBase(MonthGrouping.net(section.txns))`
  trailing (`.textCase(nil)`, `.foregroundStyle(.secondary)`). Rows via the existing `txnRow`.
- Else → the current flat `Section("This cycle")` / `Section("Selected cycle")`.
- Empty case unchanged ("No matching transactions").

Decisions:

| decision | value | rationale |
|---|---|---|
| Header figure | **net change only** | a budget has no running balance (unlike an account); net is the meaningful per-month figure |
| Section threshold | **`secs.count > 1`** | monthly budgets → flat (no redundant header); multi-month cycles → sectioned |
| Toggle | honor **`finch.feed.groupByMonth`** | same shared toggle as the feed + account detail |
| Row style | keep the existing custom `txnRow` | Budget detail uses its own compact row (merchant · date · amount), not the shared `TxRow`; unchanged |
| When sectioned | the single "This cycle"/"Selected cycle" header is **replaced** by the month headers | SwiftUI List sections don't nest; the cycle context is already shown above (progress bars / selected-cycle figures) |

## Money / edge cases

- `Tx.amount` is ledger-base; `net` sums it, formatted via `store.displayMoneyBase` (privacy-aware —
  masks under privacy mode, base→display), consistent with the rows below it.
- Toggle off → both lists flat (unchanged).
- One-month cycle (typical monthly budget) → `secs.count == 1` → flat (no header).
- `budgetMatchedTransactions` returns cycle-scoped, date-descending txns; sections inherit that order
  (newest month first).

## Scope

- **Only `BudgetDetailView.swift`.** `LedgerDetailView` untouched (already covered via the feed).
- Reuses the existing `MonthGrouping` helper (#595) — no engine or selector change, no new file.
- No new unit test (the pure helper is already tested in #595; this is view wiring — verified by
  build + on-device: a quarterly/yearly budget shows month sections, a monthly one stays flat).
