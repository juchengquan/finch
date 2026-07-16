# Spec: Scheduled detail column on iPad/macOS (#414 deferral, CP2 — final piece)

**Date:** 2026-07-16
**Status:** design approved, ready for implementation plan
**Scope:** native app (`ios/`), regular-width shell only. The last of the three #414 deferrals (Ledger 3-col #414 · sidebar persistence #441 · Activity column #445 precede it). Compact/iPhone unchanged.

## Goal

The Scheduled tab joins the three-column shell: sidebar │ scheduled (calendar **or** list) │ **template detail**. Selecting a template — from a list row **or** a calendar occurrence — fills the third column with a read-only detail whose toolbar offers **Post now + Edit** (Edit opens the existing `ScheduledSheet`; approved deviation from CP1's Edit-only precedent since posting is the template's primary action).

## Current state (baseline)

- `ScheduledTab` has two modes (`.calendar` default / `.list`). List mode: `List(selection: $kbSel)` with `Button { editing = t }` rows already `.tag(t.id)`, swipe (Post/Edit/Delete) + context menus, and a macOS ↵-open handler (ScheduledTab.swift:110) keyed on `kbSel`. Calendar mode: `ScheduledCalendarView(templates:onEdit:onPost:onAdd:)` — `onEdit` maps to `editing = t` (sheet).
- `postNow(_:)` (ScheduledTab.swift:149) = `try store.apply(.postScheduled, Args(["templateId": .string(t.id)]))` + `errorMessage`.
- `ScheduledRow.nextRunDisplay` (ScheduledTab.swift:170-182) computes the true next occurrence via `Selectors.occurrencesInRange` over a ~400-day horizon, falling back to `template.nextRun` — the detail view needs the same figure.
- `ScheduledTemplate` fields: name, description, type (expense/income/transfer), amount (nil = variable), frequency, dayOfMonth, weekDay, accountId, fromAccountId (transfers), categoryId, startDate/endDate, nextRun, maxExecutions, installmentTotal/Paid, color.
- On regular width the tab currently renders in the 2-column `default:` branch. Nothing emits `scheduled:<id>` deep links today (Spotlight doesn't index templates).

## Design

### 1. `ScheduledDetailView(templateId: String)` — new inline detail view

- New file `ios/FinchApp/Sources/FinchApp/WriteScreens/ScheduledDetailView.swift`; live-resolves `store.scheduled.first { $0.id == templateId }` (reflects edits and posts); missing → `DetailPlaceholder(systemImage: "calendar", label: "Select a scheduled item")`.
- Sections (small `@ViewBuilder` funcs — macOS type-check discipline; money via store formatters):
  - **Header:** name + type icon colored per the list-row convention (transfer `arrow.left.arrow.right`/blue, income `arrow.down.circle`/green, expense `arrow.up.circle`/red) + amount (`store.displayMoney(amount, from: account currency)`) or "Variable".
  - **Schedule:** frequency (capitalized), **next run** (the same occurrences-based computation as `ScheduledRow.nextRunDisplay` — extracted, not duplicated; see §2), day-of-month / weekday when the frequency uses them, start/end dates when set.
  - **Posting:** account name; from-account when `fromAccountId` is set (transfers); category name when set.
  - **Progress:** installment "N of M" when `installmentTotal` is set; max executions when set.
  - **Description** when non-empty.
- **Toolbar:** **Post now** (`checkmark.circle`, its own `store.apply(.postScheduled, …)` + `errorAlert` — the same one-line call the tab uses) and **Edit** (`pencil`) presenting `ScheduledSheet(template:)`.

### 2. Shared next-run helper (extract, don't duplicate)

- Move the `nextRunDisplay` computation into an internal helper reachable by both `ScheduledRow` and `ScheduledDetailView` — e.g. `func scheduledNextRun(_ template: ScheduledTemplate, today: String) -> String` at file scope in ScheduledTab.swift or a small shared home; `ScheduledRow` switches to it (behavior identical), the detail view calls it.

### 3. `ScheduledTab` selection mode

- `var selection: Binding<String?>? = nil` (the established convention; single call site — `tabContent(.scheduled)`).
- Gated touch points (nil path byte-for-byte unchanged):
  1. List binding: `List(selection: selection ?? $kbSel)`.
  2. List row Button action: `if let selection { selection.wrappedValue = t.id } else { editing = t }`.
  3. macOS ↵ handler: add `selection == nil` to its condition.
  4. Calendar `onEdit` remap: `onEdit: { t in if let selection { selection.wrappedValue = t.id } else { editing = t } }` — **no changes inside `ScheduledCalendarView`**.
- Everything else identical: swipe/context actions, detected-charges section, `onPost`, `onAdd`, search, mode picker.

### 4. Shell wiring (`SplitViewShell`)

- `@State private var scheduledSelection: String?`, cleared in the ledger-switch `onChange` with its siblings.
- `case .scheduled:` `ThreeColumnShell` branch: list column `ScheduledTab(selection: $scheduledSelection)`; detail = stale-guarded (`store.scheduled.contains…`) `NavigationStack { ScheduledDetailView(templateId: id) }` else `DetailPlaceholder(systemImage: "calendar", label: "Select a scheduled item")`.

## Non-goals

- **No deep-link consumption** for `scheduled:` ids (unlike CP1): nothing emits them today — dead code; revisit if Spotlight ever indexes templates.
- No changes inside `ScheduledCalendarView`; no compact/iPhone changes; `ScheduledSheet` untouched.
- No Delete on the detail toolbar (stays on row swipe/context; the sheet has full control).

## Testing / verification

- **Builds:** FinchApp (iOS) + FinchMac (macOS); full `FinchAppTests` regression (nil path unchanged).
- **iPad simulator (scripted):** fresh sim (the #441 restoration-key gotcha), `-initialTab scheduled` → screenshot: sidebar │ scheduled (calendar) │ "Select a scheduled item" placeholder.
- **Manual checklist (PR body — taps unscriptable):**
  1. List mode: tap a row → detail fills; tap another → updates.
  2. Calendar mode: tap an occurrence → the template's detail fills (no sheet).
  3. Post now from the column → next-run advances in place; feed shows the posted transaction.
  4. Edit → sheet → save → detail reflects it.
  5. Delete the selected template (list swipe) → placeholder returns.
  6. iPhone: both modes still open the sheet on tap.

## Risks

- `ScheduledTab` is single-call-site and simpler than CP1's feed, but the calendar remap is a new pattern — the reviewer should verify `onPost`/`onAdd` closures are untouched and only `onEdit` is remapped.
- The extracted next-run helper must keep `ScheduledRow` behavior identical (pure move).
- CP1's final review found an ungated deep-link consumer in the hosted view — audit `ScheduledTab` for any other `focusedId`/router consumption before assuming there is none (baseline grep found none, but verify in review).
