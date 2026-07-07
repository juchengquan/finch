# iPad multi-column — Ledger 3-column + column-width polish — Design

**Date:** 2026-07-07
**Scope:** the "iPad multi-column" polish theme from the handoff backlog (`2026-06-25-ios-handoff.md`). Extends remediation #23's three-column treatment (Accounts/Budgets, `IOS_MACOS_UI_REMEDIATION_PLAN.md §23`) to the **Ledger** tab, and gives the split shells sensible **column widths**. iPad and macOS share `SplitViewShell`, so macOS gets both for free.

## Why Ledger (and why not Activity/Scheduled/Insights)

Remediation #23 gave three columns only to tabs with a real list→detail relationship. Since then, the Ledger tab became exactly that shape (#394: `LedgerListView` → `LedgerDetailView`), but it still renders as two columns — on iPad regular width, tapping a ledger *pushes* the detail over the full-width content column, losing the list.

- **Ledger** ✅ — has a genuine list (`LedgerListView`) and detail (`LedgerDetailView(ledgerId:)`) pair today. Mirroring the Accounts/Budgets pattern is mechanical.
- **Activity / Scheduled** ⏳ deferred — both edit via **sheets** (`EditTransactionSheet`, `ScheduledSheet`); there is no detail *view* to put in a third column. Building inline detail views is net-new UI that needs simulator verification — a follow-up CP, not this pass.
- **Insights / Settings** ⊘ — dashboards; #23's judgement stands ("a dashboard squeezed into a narrow middle column would be worse").

## Design

### 1. Ledger joins `ThreeColumnShell`

`SplitViewShell` gains a `.ledger` case (today it falls into the two-column `default`):

- sidebar │ **ledger list** │ **ledger detail**
- New `@State private var ledgerSelection: String?` alongside `accountSelection`/`budgetSelection`.
- Detail column guards stale ids (`store.ledgers.contains`) — covers delete-while-selected — else `DetailPlaceholder("Select a ledger", books.vertical)`.
- **Not** reset by the active-ledger `onChange` — the ledger list is global, not scoped by the active ledger; "make active" from the detail must not eject you.

`LedgerTab` and `LedgerListView` gain the standard optional selection binding (the #23 dual-mode convention):

- `selection == nil` (compact iPhone push, and the compact `ledgerPush()` path): unchanged — `NavigationLink(value:)` + `.navigationDestination`.
- `selection` non-nil (regular width): `List(selection:)` with `.tag(ledger.id)` rows; swipe/context actions unchanged.

### 2. Column widths

Nothing sets `navigationSplitViewColumnWidth` anywhere today; `.balanced` splits leave the middle column ~half the content width on iPad. Set on `ThreeColumnShell` only:

- sidebar: `min 180 / ideal 220 / max 280`
- list column: `min 300 / ideal 340 / max 420`

The detail column takes the rest. The two-column shell stays untouched (full-width dashboards are the point there).

## Out of scope (recorded decisions)

- **Persisted sidebar collapse / `columnVisibility` state.** iPadOS auto-collapses columns on rotation to portrait; naïvely persisting `NavigationSplitViewVisibility` would record that auto-collapse as a user preference and pin the sidebar closed after rotating back. Doing this right needs simulator verification of the rotation/multitasking matrix — deferred.
- **Activity/Scheduled detail columns** — need net-new inline detail views (see above).
- **iPad multi-window / scene-per-ledger** (`IOS_MACOS_ROADMAP.md` Phase 3 open question) — separate, larger item.

## Acceptance

- iPad regular width + macOS: Ledger section shows sidebar │ ledgers │ detail; selecting a ledger fills column 3; deleting the selected ledger returns the placeholder; "make active" keeps the selection.
- iPhone / compact (incl. the corner-control `ledgerPush()` path): behavior unchanged (push navigation).
- FinchApp + FinchMac + FinchWatch build; existing tests green (no logic change — this is view/shell wiring, verified by CI builds).
