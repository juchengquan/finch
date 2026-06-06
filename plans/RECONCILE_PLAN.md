# Reconcile-to-statement — scoping plan

Status: **shipped** (PR #90) — guided reconcile flow + per-account checkpoint
(`accounts.last_reconciled_at`/`_balance`) + `transactions.cleared_at`. This doc
is kept as the design record.

> **v2 scope (planning): "add missing transactions during reconcile".** The
> shipped flow lets you tick rows and, for any leftover gap, *post an
> adjustment* — which papers over the gap instead of finding it. In practice a
> non-zero difference almost always means **a real transaction you forgot to
> log**, not a mystery delta. v2 makes "add the missing row" a first-class
> in-flow action so adjustment becomes the true last resort. **No schema change
> required** (see §11). Specced in §10 below.

finch already has a blunt *adjust-to-target* tool: the "Reconcile balance"
dialog on account detail posts a single Adjustment delta to force the balance
to a number (`adjustAccountBalance` in `mutations.ts`). That fixes the
*number* but tells you nothing about *what was wrong* — it papers over the
gap instead of finding it.

True reconciliation is the guided version: you tell finch the real statement
balance, tick off each transaction that appears on the statement, watch the
"cleared balance" climb toward the target, and only post an Adjustment for
whatever unexplained remainder is left. The result is a **dated checkpoint**:
"this account was verified correct up to Nov 30". That's the single most
trust-building feature in serious finance tools.

Sourced from `INSPIRATION_IDEAS.md` §1.1. Inspiration: Actual Budget's
reconciliation flow + Beancount's `balance` assertions + Fava's "last
reconciled N days ago" badge.

## 0. Confirmed product decisions

Decided going in — anything else is an open question (§7).

1. **The existing "Reconcile balance" dialog stays.** It's the quick
   blunt path (type a target, post one delta). Reconcile-to-statement is
   the *guided* path beside it, not a replacement. We'll rename the old
   one to "Adjust balance" to remove the naming collision.
2. **Clearing is per-account, per-transaction.** A transaction is
   "cleared" against a real statement or it isn't. Clearing is
   independent of the pending/confirmed status — a confirmed transaction
   can still be uncleared (logged but not yet seen on a statement).
3. **Reconciliation produces a dated checkpoint, not a lock.** Marking
   an account reconciled records the balance + date; it does NOT freeze
   the rows. (Period-locking is a separate, already-listed feature —
   `FEATURE_IDEAS.md` §7.3.) Editing a reconciled transaction is allowed
   but clears the green badge's "still valid" state (see §5.3).
4. **Adjustment for the remainder reuses the existing path.** The
   "post the unexplained difference" button calls the same
   `adjustAccountBalance` mutation the blunt dialog uses, tagged so we
   know it came from a reconcile session.
5. **No statement file import.** The user reads their real statement on
   paper / their bank's site and ticks rows here. No OFX/CSV/PDF
   parsing — that's the bank-integration line finch doesn't cross.

## 1. What changes vs. what doesn't

| Layer | Changes? |
|---|---|
| Schema | One column on `transactions` (`cleared_at`); two on `accounts` (`last_reconciled_at`, `last_reconciled_balance`). |
| Mutations | New `setCleared`, `reconcileAccount`; existing `adjustAccountBalance` gains an optional source tag. |
| Read path | Balance math unchanged. A new pure `reconcileState` selector computes cleared-balance + gap. |
| Existing UIs | "Reconcile balance" dialog renamed to "Adjust balance". Account detail gains a "Reconcile" entry point + a status badge. |
| New UIs | Reconcile mode on the account-detail transaction list (checkbox column + running tally bar). |

## 2. Data model

### 2.1 Transaction clearing

```sql
ALTER TABLE transactions ADD COLUMN cleared_at TEXT;  -- ISO datetime, NULL = uncleared
```

- `cleared_at` is set when the user ticks a row during reconciliation,
  cleared (set NULL) when they untick.
- Why a timestamp not a boolean: lets us answer "cleared during which
  session" later, and it's free — same storage cost as a flag in SQLite.
- No index needed initially; clearing is queried per-account alongside
  the existing `idx_txn_account_date` scan.

### 2.2 Account checkpoint

```sql
ALTER TABLE accounts ADD COLUMN last_reconciled_at TEXT;       -- ISO date of the statement
ALTER TABLE accounts ADD COLUMN last_reconciled_balance REAL;  -- statement balance, account currency
```

- These are the green checkpoint. `last_reconciled_at` drives the
  "reconciled 47 days ago" badge; `last_reconciled_balance` is shown as
  "✓ matched $2,431.07".
- Both nullable — an account that's never been reconciled shows a
  neutral "Never reconciled" state.

## 3. The reconcile math (pure selector)

```ts
// lib/select.ts (or lib/reconcile.ts)
export interface ReconcileState {
  /** Sum of cleared transactions + opening balance, in account currency. */
  clearedBalance: number;
  /** The target the user typed (statement ending balance). */
  statementBalance: number;
  /** statementBalance - clearedBalance. Zero = reconciled. */
  difference: number;
  /** Count of cleared / uncleared rows in the working set. */
  clearedCount: number;
  unclearedCount: number;
  /** True when |difference| < 0.005 (penny tolerance). */
  balanced: boolean;
}

export function reconcileState(
  account: AccountRow,
  txns: Tx[],
  statementBalance: number,
): ReconcileState;
```

- `clearedBalance` = `account.opening_balance` + Σ (cleared confirmed
  transactions in account currency). Mirrors `recomputeAccount`'s
  currency handling (native amount when the row currency matches the
  account, else `amount_base`).
- Pending rows never count toward cleared balance (they're not on a
  statement yet). They can still be *shown* in the list, greyed.
- Penny tolerance avoids float-noise false negatives.

## 4. Mutations

```ts
// 1. Toggle a single row's cleared state (optimistic in the store).
setCleared(transactionId: string, cleared: boolean): void

// 2. Finalise a reconciliation: stamp the account checkpoint, and
//    (optionally) post an Adjustment for the leftover difference.
reconcileAccount(args: {
  accountId: string;
  statementBalance: number;
  statementDate: string;
  postAdjustment: boolean;   // true → post the remainder as an Adjustment
}): void
```

- `reconcileAccount` writes `last_reconciled_at` + `last_reconciled_balance`,
  and if `postAdjustment` is true and a non-zero gap remains, calls the
  existing adjustment path with a `source: 'reconcile'` tag so the posted
  row reads "Reconciliation adjustment" rather than the manual label.
- Server side: both run inside the standard `withWrite` transaction;
  `setCleared` is a one-column UPDATE, `reconcileAccount` is an UPDATE +
  optional insert via the existing `adjustAccountBalance` helper.

## 5. UI surfaces

### 5.1 Entry point + status badge (account detail)

- The balance card gains a small reconcile status line:
  - Never reconciled → muted "Never reconciled · Reconcile" link.
  - Reconciled → "✓ Reconciled to $2,431.07 · Nov 30" + a relative
    "(47 days ago)" that turns warning-amber past ~35 days (configurable
    later).
- A "Reconcile" button (or ⋯-menu item) enters reconcile mode.

### 5.2 Reconcile mode (the core surface)

A focused mode over the account's transaction list:

```
┌─────────────────────────────────────────────┐
│ Reconcile · Checking                    [✕]  │
│ Statement balance  [ 2,431.07 ]  as of [Nov 30] │
│                                               │
│ Cleared $2,418.55  ·  Target $2,431.07        │
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░  Difference −$12.52        │
├───────────────────────────────────────────────┤
│ ☑ Nov 28  Whole Foods           −$84.32       │
│ ☑ Nov 27  Salary               +$3,000.00     │
│ ☐ Nov 26  Blue Bottle            −$6.75        │  ← tick to clear
│ ☐ Nov 24  Shell                 −$48.10        │
├───────────────────────────────────────────────┤
│ Difference −$12.52   [ Post adjustment ] [Done]│
└───────────────────────────────────────────────┘
```

- Checkbox column on each row; ticking updates the running
  cleared-balance + difference bar live (optimistic, no roundtrip per
  tick — `setCleared` syncs in the background).
- The difference bar is green at zero, amber otherwise.
- **Done** is enabled when balanced (difference ≈ 0) → calls
  `reconcileAccount` with `postAdjustment: false`.
- **Post adjustment** is the escape hatch: enabled when there's a
  non-zero gap → calls `reconcileAccount` with `postAdjustment: true`,
  posting the remainder and stamping the checkpoint in one action.
- Already-cleared rows from a prior session render pre-ticked, so a
  monthly reconcile only touches the new rows.

### 5.3 Editing a reconciled transaction

- Editing the amount/date of a row whose `cleared_at` is set (i.e. part
  of a past reconciliation) is allowed, but the account's
  "reconciled · still valid" badge flips to "reconciled · edited since"
  (amber) — a soft warning that the checkpoint may no longer hold.
  We detect this by comparing the latest transaction `updated_at` in the
  cleared set against `last_reconciled_at`. No hard lock (that's §7.3 in
  FEATURE_IDEAS).

## 6. Shipping order

Each step is independently mergeable:

1. **Schema + selector** — three columns, migration, `reconcileState`
   pure selector. Tests: cleared-balance math, penny tolerance,
   mixed-currency handling, pending exclusion. *No UI.*
2. **Mutations** — `setCleared` + `reconcileAccount` (store + server +
   api), `adjustAccountBalance` source tag. Tests: clearing toggles,
   checkpoint stamping, adjustment-for-remainder posts the right delta.
3. **Rename the existing dialog** — "Reconcile balance" → "Adjust
   balance" so the new feature owns the "Reconcile" name. Tiny, can
   ride with step 2 or stand alone.
4. **Reconcile mode UI** — the checkbox list + running tally + Done /
   Post-adjustment actions on account detail.
5. **Status badge** — the "✓ reconciled to $X · N days ago" line on the
   balance card + the "edited since" amber state.

PR slice for early value: **1+2** ship the engine + mutations (testable
without UI). **3+4+5** ship the experience.

## 7. Open questions

1. **"Stale reconcile" threshold.** When does the badge turn amber —
   35 days? 45? Per-account-type (a credit card statement is monthly,
   a rarely-used savings account maybe quarterly)? Recommendation: a
   single 35-day default, revisit if it's noisy.
2. **Clear-on-confirm shortcut?** Should confirming a pending
   transaction optionally auto-clear it, or are confirm (it happened)
   and clear (I saw it on a statement) always distinct? Recommendation:
   keep them distinct — conflating them defeats the point of clearing.
3. **Show pending rows in reconcile mode?** They can't be cleared (not
   on a statement yet), but hiding them might confuse ("where's the
   coffee I just logged?"). Recommendation: show them greyed + a
   "pending — not on a statement" hint, non-tickable.
4. **Multi-currency accounts.** The statement balance is in the account
   currency; the math already handles native amounts. Confirm the
   target input is labelled with the account currency, not the display
   currency. (Decision: yes — reconcile is always native, since that's
   what the statement shows.)
5. **Undo a reconciliation?** A "clear reconciliation checkpoint"
   action that nulls `last_reconciled_at/_balance` (leaving the cleared
   flags intact)? Low cost; recommendation: include it in the ⋯ menu.

## 8. Out of scope

- **Statement file import** (OFX/CSV/PDF parse) — the bank-integration
  line finch doesn't cross. The user reads their statement themselves.
- **Hard period locking** — preventing edits to reconciled rows. That's
  `FEATURE_IDEAS.md` §7.3, a separate feature; here we only *warn*.
- **Auto-matching** rows to statement lines — needs the imported
  statement we're explicitly not parsing.
- **Reconciliation history log** — a list of past reconciliations per
  account. Nice-to-have; the single `last_reconciled_*` checkpoint
  covers the 90% case. Revisit if asked.

## 9. Acceptance criteria

Engine (PRs 1-2):

- `bun test` covers `reconcileState` math: cleared sum, penny
  tolerance, pending exclusion, mixed-currency native handling.
- `setCleared` toggles a single row; `reconcileAccount` stamps the
  checkpoint and (when asked) posts an Adjustment equal to the
  remaining difference, after which `reconcileState.balanced` is true.
- Reconciling a 200-transaction account is a single SQL roundtrip for
  the checkpoint (clearing is incremental, one UPDATE per tick).

UI (PRs 3-5):

- A user can reconcile a month in under a minute for the common case
  (tick the new rows, hit Done).
- The difference bar updates instantly per tick with no visible lag.
- The "Post adjustment" escape hatch posts a correctly-signed delta and
  lands the account exactly on the statement balance.
- The status badge reflects reconciled / never / edited-since states
  correctly.

---

# v2 — Add missing transactions during reconcile

Status: **planning** — no code changes yet. Builds on the shipped flow above.

## 10. Scope

### 10.1 The gap this closes

Today, reconcile mode (`app/(main)/accounts/[id]/page.tsx`) lets you tick
rows and watch the difference bar. When the difference won't reach zero, the
only in-flow action is **Post adjustment** (`finishReconcile(true)` →
`reconcileAccount({ postAdjustment: true })`), which posts one opaque
Adjustment delta. That fixes the number but loses the information: *which
real-life transactions are missing*.

v2 adds the missing half: **add (or confirm) the real transactions from
inside reconcile mode**, watch each one close the gap, and reserve the
adjustment for a genuinely unexplained remainder.

### 10.2 In scope

1. **Quick-add inside reconcile mode.** An "Add missing transaction" affordance
   in the reconcile panel opens the existing add form pre-scoped to this
   account, and on save the new row is **auto-cleared** so it immediately
   counts toward the cleared balance and shrinks the difference. Implemented by
   composing two primitives that already exist: `addTransaction(...)` returns
   the new id → `setCleared(id, true)`.
2. **Confirm-and-clear a pending row in one tap.** During reconcile you often
   realise a *pending* row actually posted. Today pending rows are shown but
   not tickable (they can't be "cleared" while pending). Add a single
   "It posted — confirm & clear" action on a pending row that calls
   `confirmPending(id)` then `setCleared(id, true)`. (Revisits open question
   §7.2, which kept confirm and clear strictly separate — the reconcile context
   is the case where doing both at once is exactly right.)
3. **Gap framing.** When `difference ≠ 0`, reframe the copy from a bare number
   to an actionable hint: a positive difference (statement higher than cleared)
   → "You're {amount} short — likely a missing deposit/expense. Add it, or post
   an adjustment." The **Add missing transaction** button is the primary action;
   **Post adjustment** demotes to secondary while a gap looks explainable.

### 10.3 Explicitly NOT in scope (keep these as-is)

- **No merging of `status` (pending/confirmed) and `cleared_at`.** They stay two
  independent axes — *did it happen* vs *did I see it on a statement*. v2 only
  adds a one-tap shortcut that performs both transitions together; it does not
  collapse the model. (This directly answers the original request's "check as
  confirmed/nonconfirmed" phrasing: we keep them distinct on purpose.)
- **No statement file import** (OFX/CSV/PDF) — unchanged from §8.
- **No hard period lock** — unchanged (FEATURE_IDEAS §7.3).
- **No auto-matching** of added rows to statement lines.

### 10.4 UI sketch (extends §5.2)

```
┌─────────────────────────────────────────────┐
│ Reconcile · Checking                    [✕]  │
│ Statement balance [ 2,431.07 ] as of [Nov 30]│
│ Cleared $2,418.55 · Target $2,431.07          │
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░  You're $12.52 short       │
│                       ↳ likely a missing row   │
├───────────────────────────────────────────────┤
│ ☑ Nov 28 Whole Foods            −$84.32       │
│ ☐ Nov 26 Blue Bottle             −$6.75       │
│ ⏳ Nov 25 Rent (pending)  [confirm & clear]    │  ← 10.2(2)
├───────────────────────────────────────────────┤
│ [ + Add missing transaction ]                  │  ← 10.2(1), primary
│ Difference −$12.52   [ Post adjustment ] [Done]│  ← adjustment demoted
└───────────────────────────────────────────────┘
```

- **Add missing transaction** reuses `AddExpenseForm` (the same component the
  `/add` route and the add slider render), seeded with `account = this account`
  and `date = statement date`. On `onSaved(id)` the page calls
  `setCleared(id, true)` and stays in reconcile mode so the user can keep going.
- The pending-row action appears only on rows where `tx.pending` is true.

### 10.5 Work breakdown

All client-side; no new mutations, no server changes.

- `accounts/[id]/page.tsx`: add the quick-add entry point (open the existing
  add form scoped to this account; auto-clear on save), the pending-row
  "confirm & clear" action, and the gap-hint copy.
- Possibly a thin wrapper around `AddExpenseForm` to default + lock the account
  field and fire `onSaved(id)` — or reuse the form as-is if it already accepts
  an initial account (check before building).
- Tests: extend `reconcileState` coverage if any selector changes (none
  expected); otherwise this is a UI-composition change verified by the existing
  `setCleared` / `addTransaction` / `confirmPending` unit tests plus a manual
  smoke. Add a small test asserting "add a row + clear it drives
  `reconcileState.difference` to 0" if it can be expressed at the selector level.

### 10.6 Shipping order

One PR is fine — it's a UI composition over shipped mutations. If split:
1. Quick-add + auto-clear + gap-hint copy (the core of the request).
2. Pending-row confirm-and-clear shortcut.

## 11. Schema impact — none

v2 requires **no DB schema change**. Everything composes from columns and
mutations that already shipped in PR #90 and earlier:

| Need | Already exists |
|---|---|
| Mark a brand-new row as seen-on-statement | `transactions.cleared_at` + `setCleared` mutation |
| Create the missing row | `addTransaction` (returns the new id) |
| Confirm a pending row | `confirmPending` / `confirmPendingWithMatch` |
| Cleared-balance + difference math | `reconcileState` selector (`lib/reconcile.ts`) |
| Account checkpoint on finish | `accounts.last_reconciled_at` / `_balance` + `reconcileAccount` |

The only code that moves is the reconcile-mode UI wiring these together.
