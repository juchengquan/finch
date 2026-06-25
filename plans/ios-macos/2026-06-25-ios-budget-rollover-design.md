# Budget rollover UI (iOS)

**Date:** 2026-06-25
**Status:** Design approved, pending implementation
**Scope:** iOS `BudgetSheet` (form) + `BudgetDetailView` (display). **Pure UI — no engine/model/schema change.** iPad/Mac share the views. Tier-1 parity gap from the inventory (#303).

## Problem

The `BudgetRow` model already projects `rollover`/`rolloverLimit`/`carryForward`, the `createBudget`/`updateBudget` actions already persist `rollover` + `rolloverLimit`, and `carryForward` is already folded into the budget progress math (`base = amount + (expense ? carryForward : 0)`). But the iOS UI doesn't surface any of it: the budget **form** can't enable rollover or set a cap, and the **detail** never shows the carried-forward amount. The web has the rollover toggle + a carried-forward display.

## Goal

- **Form (`BudgetSheet`, expense budgets only):** a **Roll over unused budget** toggle; when on, an optional **cap** field (`rolloverLimit`). Persist both on create + edit; prefill on edit.
- **Detail (`BudgetDetailView`):** show the **carried-forward** amount inline (green "+$X carried") when `carryForward > 0`, and a subtle **"Rolls over"** caption when rollover is on.

## Non-goals

- No engine/model/schema/action change (all already support this).
- No change to the rollover *math* (`carryForward` is already in `base`/`remaining`/`pct`); display only.
- No rollover for income budgets (matches the web). No new budget frequencies.

## Key decisions (locked)

1. **Pure UI** — two view files; everything downstream already exists.
2. **Toggle + optional cap** (`rolloverLimit`) — the cap is backend-supported and enforced by the rollover engine (`carryForward = rollover_limit == nil ? leftover : min(leftover, rolloverLimit)`); iOS exposes it even though the web form doesn't yet.
3. **Expense-only** (hidden for income); the web's "disable for daily" caveat is N/A (the iOS form offers no daily frequency).
4. Detail shows **carried amount + a "Rolls over" caption**.

## Detailed design

### `BudgetSheet` (FinchApp)

- New state: `@State private var rollover: Bool`, `@State private var rolloverCap: String`.
- **Init prefill** (edit): `rollover = (template?.rollover ?? 0) != 0`; `rolloverCap = template?.rolloverLimit.map { RuleParse.numStr($0) } ?? ""` (or an equivalent integral-safe formatter — reuse the existing `%g`-safe `numStr`, or `String($0)` trimmed). New-budget defaults: `rollover = false`, `rolloverCap = ""`.
- **UI:** in the form, only when `kind == .expense`, a `Section` (or rows) with:
  - `Toggle("Roll over unused budget", isOn: $rollover)`
  - when `rollover` is on: `TextField("Cap carried amount (optional)", text: $rolloverCap).keyboardType(.decimalPad)` with caption "Limits how much unspent budget carries to the next period."
- **Save** (both create args and edit patch):
  - `"rollover": .bool(kind == .expense && rollover)`
  - `"rolloverLimit"`: if `kind == .expense && rollover`, the cap field parses to a number ≥ 0 → `.double(n)`; otherwise `.null` (clears any existing cap / when rollover off or income). (The existing `update` column map binds `.null` → SQL NULL; `create` accepts a nil `rolloverLimit`.)
- **Validation:** if `rollover` is on and `rolloverCap` is non-empty, it must parse via `DecimalInput.parse` to a value ≥ 0 → else `errorMessage = "Enter a valid rollover cap."`. (Empty cap = no cap = full leftover rolls over.)

### `BudgetDetailView` (FinchApp)

- On the existing "used of base" line, when `b.carryForward > 0` append, in `text-success`/green: `"(+\(store.displayMoneyBase(b.carryForward)) carried)"`.
- A subtle caption (e.g. near the cycle window or under the progress bar) `"Rolls over"` when `b.rollover != 0` (optionally `"Rolls over (cap \(displayMoneyBase(rolloverLimit)))"` when a cap is set).
- No other changes — the progress bar/remaining/over already include `carryForward`.

## Facts (already present — verified, no change)

- `BudgetRow`: `rollover: Int`, `rolloverLimit: Double?`, `carryForward: Double`, `type: String` (`Project/Budget.swift`).
- `Budgets.create` reads `rollover` via `isTruthy` + writes `rolloverLimit`; `Budgets.update`'s column map includes `rollover`→`rollover`, `rolloverLimit`→`rollover_limit` (`Store/Domain/Budgets.swift`).
- Progress: `base = amount + (type == "expense" ? carryForward : 0)` (`Selectors.swift` budgetProgress).
- Rollover engine clamps: `carryForward = rolloverLimit == nil ? leftover : min(leftover, rolloverLimit)` (budgets rollover step).
- `BudgetSheet` current fields: name, type (expense/income), amount, frequency (weekly/monthly/quarterly/yearly — no daily), group, categories. `BudgetDetailView` shows used/base, progress bar, remaining, cycle window, pending-amount chip — but **not** carryForward.

## Testing

- **No new FinchCore tests** — no new pure logic (actions + progress math already exist and are tested).
- **Build gate:** iOS + macOS (FinchMac); full FinchAppTests green.
- **Manual (sim):**
  - New expense budget → toggle **Roll over** on → set a cap → save → reopen: toggle on + cap prefilled. Income budget → no rollover row.
  - Edit: turn rollover off → cap clears (rolloverLimit null).
  - A budget whose prior cycle left money over shows **"(+$X carried)"** in the detail and a **"Rolls over"** caption; the progress bar/remaining reflect the larger base (already does).

## Out of scope

Engine/model/schema/action changes; rollover math; income rollover; new frequencies; a rollover cap on the web.
