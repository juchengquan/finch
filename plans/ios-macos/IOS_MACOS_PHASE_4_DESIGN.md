# finch for iOS & macOS — Phase 4 Implementation Design

> _Web facts verified against commit `22c9896` (SCHEMA_VERSION `2026-06-14T00:00:00Z`), 2026-06-13.
> See `_WEB_DRIFT_CHECKLIST.md`._

> **Status**: design spec — not yet an implementation plan. Once
> approved, this becomes the input to `writing-plans` to produce
> a step-by-step implementation plan for Phase 4.
>
> Companion documents:
>
> - `plans/ios-macos/IOS_MACOS_PLAN.md` — direction brief
> - `plans/ios-macos/IOS_MACOS_PHASE_1_DESIGN.md` — Phase 1.0 full design
> - `plans/ios-macos/IOS_MACOS_PHASE_1_5_DESIGN.md` — Phase 1.5 full design
> - `plans/ios-macos/IOS_MACOS_PHASE_2_DESIGN.md` — Phase 2 full design
> - `plans/ios-macos/IOS_MACOS_PHASE_3_DESIGN.md` — Phase 3 full design
> - `plans/ios-macos/IOS_MACOS_ROADMAP.md` — 8-phase arc
> - `plans/ios-macos/IOS_MACOS_PHASE_4_DESIGN.md` (this file)
>
> _Audience: the engineers who will build the iOS app. Assumes
> Phases 1.0, 1.5, 2, and 3 are complete; the iPhone + iPad + Mac
> apps are shipping with the 6 tabs + 7 write screens + the 74-
> action chokepoint._

## See also

- `plans/ios-macos/IOS_MACOS_INDEX.md` — the navigation index
- `plans/ios-macos/IOS_MACOS_WIRE_FORMAT.md` §2 — the 74-action Args catalogue
- `plans/ios-macos/IOS_MACOS_PHASE_2_DESIGN.md` — Phase 2 (chokepoint)
- `plans/ios-macos/IOS_MACOS_PHASE_5_DESIGN.md` — Phase 5 (iCloud + pack; runs after Phase 4)
- `plans/ios-macos/IOS_MACOS_PLAN.md` §2.1 — the chokepoint surface
- `plans/ios-macos/IOS_MACOS_ROADMAP.md` — Phase 4 sketch

## §0. Map — 8-section template

The 8-section template maps to this spec's existing sections:

| Template section | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | (covered across §2-§8, the 7 features; each has a wire shape and UI sketch) |
| §3. iOS UI surfaces | §2-§8 (per-feature UI sketches for the 7 power features) |
| §4. Cross-cutting concerns | §9 (Cross-cutting UI patterns) |
| §5. Wire contracts | §2-§8 (each feature has a wire shape — the chokepoint action) |
| §6. CI / test infrastructure | (not directly covered — stub to `IOS_MACOS_PLAN.md` §12) |
| §7. Out of scope (firm) | §11 |
| §8. Spec self-review + open questions | §12 + §10 |

## §1. Goal & non-goals

**Goal** — Add the **power features** the web app ships that
aren't covered by Phases 1.0-3:

1. **Reconcile** — clear-balance / statement-import / adjustment
   flow
2. **Rules engine** — condition/action model + builder + backfill
3. **Transfers CRUD** — create / edit / delete paired transfers
4. **Merchants / categories / tags admin** — rename / merge /
   archive / color
5. **Saved searches** — persist a search query + filters as a
   named shortcut
6. **Bulk recategorize** — multi-select entries + apply category
7. **FX / base tools** — per-account base-currency override,
   historical rate editor, currency rename

All 7 features have **actions already in the Phase 2
chokepoint**; Phase 4 ships the **iOS UI** for those actions
plus any supporting infrastructure (reconcile math, rules
engine, etc.).

**Phase 4 is a UI-heavy phase** — the chokepoint is unchanged
from Phase 2. Most of the work is in the iOS UI for the 7
features. The selectors from Phase 1.5 already cover most of
the read-side needs (the rules engine, the budget progress
selectors, etc.).

**Non-goals (firm)**:

- **No new chokepoint actions** — every action the iOS app
  needs already exists in Phase 2's chokepoint (the 74
  actions). Phase 4 wires UI to the existing actions.
- **No new tabs** — the 6 tabs (Accounts, Activity, Budgets,
  Insights, Scheduled, Settings) are unchanged. The new
  features surface within existing tabs (e.g., Reconcile is
  a section of the Account Detail screen; Rules is a
  section of the Settings tab; Saved Searches is a section
  of the Activity tab).
- **Auto-pack debounce + iCloud folder-watcher** — Phase 5.
- **App Intents / Siri / Share Extension / Spotlight /
  notifications / biometric lock** — Phase 6.
- **Widgets / Live Activities / Watch** — Phase 7.
- **Row-level sync** — Phase 8.
- **Bank/feed import** — out of scope per the plan's §7
  boundary. Reconcile uses **manual CSV import** for
  statements; no bank API integration.
- **Multi-user / shared ledgers** — single-user iCloud
  account = single finch install. Per the plan's §10
  resolved decision.
- **Android** — not in the plan.

**Estimated scope**: ~2,100-3,500 lines SwiftUI (7 features ×
~300-500 lines each) + ~500 lines glue (the rules engine port +
the reconcile CSV parser + the FX rate editor) + ~400 lines
parity tests (the rules engine parity suite + reconcile
parity + FX conversion parity). **2-3 months of full-time
work** for a small team.

## §2. Feature: Reconcile

Reconcile is the web's flow for matching a finch account
against a real bank statement. The user enters the
statement's balance + statement date; finch computes the
un-cleared entries in the account between the last reconcile
checkpoint and now; the user marks them as cleared; the gap
(cleared sum vs statement balance) becomes an adjustment
entry when its magnitude is non-trivial (the web posts when
`|delta| >= 0.005`, hardcoded — there is no configurable
tolerance).

### 2.1 — Web's reconcile flow

The web's `app/(main)/accounts/[id]/page.tsx` (the Account
Detail page) has a "Reconcile" section:

1. The user taps "Reconcile" → the reconcile modal opens
2. The user enters the statement balance + statement date
3. finch shows the un-cleared entries between the last
   checkpoint and the statement date
4. The user marks the entries they see on the statement
   (the ones they recognize)
5. finch computes the gap: `cleared_sum - statement_balance`
6. If the gap is effectively zero (`|gap| < 0.005`, the web's
   hardcoded threshold), the user taps "Mark reconciled" → the
   checkpoint is set with no adjustment
7. If the gap is non-trivial (`|gap| >= 0.005`), the user can
   either:
   (a) "Post adjustment" → finch posts a `kind='adjustment'`
       entry for the gap
   (b) "Cancel" → no checkpoint, the un-cleared entries
       remain un-cleared

There is **no configurable tolerance** in the web's
`reconcileAccount` action — the $0.005 threshold is hardcoded
(`lib/db/domain/transactions/mutations.ts:147`). A tolerance
picker would be a **native addition**, not a port of web
behavior.

### 2.2 — iOS Phase 4 surface

The iOS Account Detail screen (Phase 1.0's drill-down from
the Accounts tab) gets a **Reconcile** toolbar button. Tapping
opens a `NavigationStack` with a multi-step reconcile flow:

```
┌─────────────────────────────────────┐
│  ← Reconcile · Chase Checking        │
├─────────────────────────────────────┤
│  Step 1 of 3: Statement details     │
│                                      │
│  Statement balance                   │
│  ┌──────────┐                        │
│  │  1234.56 │  USD                   │
│  └──────────┘                        │
│                                      │
│  Statement date                      │
│  Jun 30, 2026                    ▾   │
│                                      │
│  Tolerance (native-only)             │
│  ± $0.01                         ▾   │
│                                      │
│  [Next]                              │
└─────────────────────────────────────┘
```

> The **Tolerance** row is a **native enhancement** — the web
> has no tolerance control; its `reconcileAccount` posts an
> adjustment whenever `|gap| >= 0.005` (hardcoded). If we ship
> the native picker, default it to that same $0.005 floor and
> treat anything the user sets as a native-only divergence.

```
┌─────────────────────────────────────┐
│  ← Reconcile · Step 2 of 3           │
├─────────────────────────────────────┤
│  5 un-cleared entries between        │
│  last checkpoint (Jun 1) and         │
│  statement date (Jun 30)             │
│                                      │
│  ✓ Jun 3  Coffee Bar        -$6.50  │
│  ✓ Jun 8  Whole Foods      -$87.23  │
│  ✓ Jun 12 Payroll          $2,100.00│
│  ✓ Jun 18 ATM              -$200.00 │
│  ✓ Jun 25 Amazon           -$45.67  │
│                                      │
│  Cleared: 4     Un-cleared: 1       │
│  Cleared sum:    $1,760.60          │
│  Statement:      $1,234.56          │
│  Gap:            -$526.04           │
│                                      │
│  [Back]    [Cancel]    [Next]       │
└─────────────────────────────────────┘
```

```
┌─────────────────────────────────────┐
│  ← Reconcile · Step 3 of 3           │
├─────────────────────────────────────┤
│  Gap: -$526.04 (exceeds tolerance)   │
│                                      │
│  [ ] Post adjustment for the gap     │
│      (will create an entry on Jun 30)│
│                                      │
│  [ ] Cancel and keep entries         │
│      un-cleared                      │
│                                      │
│  [Back]    [Done]                    │
└─────────────────────────────────────┘
```

### 2.3 — iOS implementation

The reconcile flow uses the Phase 2 actions:

- `Args.setCleared({id, cleared: true})` for each entry the
  user marks
- `Args.reconcileAccount({accountId, statementBalance,
  statementDate?, postAdjustment?})` for the final reconcile
  (the web's `reconcileAccount` action handles the
  checkpoint + the optional adjustment entry in one call;
  args per `lib/db/domain/_args.ts:47` — there is **no**
  `tolerance` param)

The reconcile UI's read-side math (cleared sum, gap, un-cleared
entries list) is a small inline computation over the in-memory
`Tx[]` cache, not a ported Phase 1.5 selector — there is no
`reconcileAccount` selector in `lib/select.ts` (the 32
selectors are listed in Phase 1.5 §2). The chokepoint
`Args.reconcileAccount({accountId, statementBalance,
statementDate?, postAdjustment?})` is a Phase 2 *write* action
that handles the checkpoint + the optional adjustment entry
in one call.

### 2.4 — Statement CSV import (optional, Phase 4.5)

A follow-up to the manual reconcile flow: the user can
import a CSV file (the bank statement exported from their
bank's website). The CSV parser matches CSV rows to
un-cleared entries by amount + date proximity; the user
confirms the matches; the un-matched rows are surfaced as
"new entries to add."

This is a follow-up because:
- The CSV format varies by bank (no standard); a generic
  parser requires column-mapping configuration
- The web has no statement CSV import (per the plan's
  §7 boundary)
- The Phase 4 reconcile flow (manual balance + date
  + un-cleared entry marking) covers 80% of the use case

Phase 4 ships the manual flow. The CSV import is a Phase
4.5 follow-up if the user research demands it.

## §3. Feature: Rules engine

The web's rules engine (`lib/rules/`) is a condition/action
model:

- A **rule** is a `(condition, action[])` pair
- A **condition** is a **recursive `all` / `any` / `not`
  tree** over leaf comparators (`lib/rules/types.ts:15-64`).
  The ~14 leaves are: `merchant` (`is` / `contains` /
  `startsWith`), `amount` (incl. `between`), `account_id`,
  `category_id`, `counterparty_id`, `currency`, `date_dow`,
  `date_dom`, `kind`, `tag_id`, `note`. There is **no regex
  comparator** — merchant matching is only `is` / `contains`
  / `startsWith`.
- An **action** is a mutation. There are **9 action types**:
  `set_category`, `set_counterparty`, `set_merchant`,
  `set_note`, `set_kind`, `add_tag`, `remove_tag`,
  `mark_reviewed`, `split`.
- **Backfill** applies a rule to historical entries (the
  rule's actions are run on every entry that matches the
  condition)
- **Live** rules are applied to new entries as they're
  posted (the chokepoint runs the rules engine after every
  `postEntry`)

The web's engine is already rich: the recursive condition
tree, the `amount between` comparator, and the
`set_counterparty` action **all already exist on the web**.
So Phase 4 is a **faithful port of the existing engine**, not
an extension of a "4 conditions + 4 actions" core (there is no
such thin core). The rule builder UI
(`components/rule-builder-dialog.tsx`) is ported as-is.

**If** native users want a **regex** merchant comparator, frame
it as a genuinely **new native addition** (the web has no regex
op today): a `merchant matches /…/` leaf alongside the existing
`is` / `contains` / `startsWith`. Anything else the native
builder surfaces (amount ranges, set-counterparty) is simply
the existing web engine — not a new capability. The web would
later port back only the regex leaf, if we ship it.

### 3.1 — iOS Phase 4 surface

The Settings tab gets a **Rules** section (below the
**Active ledger** section). Tapping opens the Rules list:

```
┌─────────────────────────────────────┐
│  ← Rules                             │
├─────────────────────────────────────┤
│  Enabled rules (3)                   │
│  ┌──────────────────────────────┐   │
│  │ ☑ Coffee merchant → Coffee   │   │
│  │   if merchant matches /Starb │   │
│  │   then set category = Coffee │   │
│  │   [Edit] [Disable]           │   │
│  ├──────────────────────────────┤   │
│  │ ☑ Recurring tag              │   │
│  │   if description contains    │   │
│  │   /monthly/ then add tag     │   │
│  │   recurring                  │   │
│  │   [Edit] [Disable]           │   │
│  ├──────────────────────────────┤   │
│  │ ☑ Large expense anomaly      │   │
│  │   if amount > 500            │   │
│  │   then add tag = review      │   │
│  │   [Edit] [Disable]           │   │
│  └──────────────────────────────┘   │
│                                      │
│  [+ New Rule]                        │
└─────────────────────────────────────┘
```

Tapping a rule (or the **+** button) opens the **Rule
Builder** form:

```
┌─────────────────────────────────────┐
│  ← New Rule                          │
├─────────────────────────────────────┤
│  When (condition)                    │
│  Field:    merchant               ▾  │
│  Operator: contains               ▾  │
│  Value:    Starbucks                │
│  [+ Add condition]   (all / any)     │
│                                      │
│  Then (action)                       │
│  Set:     category                 ▾ │
│  Value:   Coffee                 ▾  │
│  [+ Add action]                      │
│                                      │
│  [Cancel]              [Save]        │
└─────────────────────────────────────┘
```

The form is a faithful port of the web's
`rule-builder-dialog.tsx` (the web has a 161-line
`lib/db/domain/rules/mutations.ts`; the iOS form mirrors the
same field set — the recursive condition tree + the 9 action
types).

### 3.2 — Backfill UI

Tapping a rule in the Rules list shows a **Backfill**
button. Tapping opens:

```
┌─────────────────────────────────────┐
│  Backfill "Coffee merchant → Coffee" │
├─────────────────────────────────────┤
│  23 historical entries match         │
│                                      │
│  Preview:                            │
│  ┌──────────────────────────────┐   │
│  │ Jun 3   Coffee Bar   Food   │   │
│  │   → Coffee                    │   │
│  │ Jun 18  Starbucks     Food   │   │
│  │   → Coffee                    │   │
│  │ Jun 22  Coffee Bar   Food   │   │
│  │   → Coffee                    │   │
│  │ ...                          │   │
│  └──────────────────────────────┘   │
│                                      │
│  [Cancel]    [Apply 23 changes]     │
└─────────────────────────────────────┘
```

The backfill is a **batch mutation** — for each matching
entry, the rule's actions are applied. The web's
`backfillRule` action takes just `{ id }` (the rule id;
`lib/db/domain/_args.ts:148`) and applies that rule to all
matching entries in one call (the chokepoint loads the rule,
iterates the entries; the UI shows a progress bar).

### 3.3 — iOS implementation

The rules engine is ported from `lib/rules/{engine,types,describe}.ts`
to `ios/FinchCore/Sources/FinchCore/Rules/`. The engine is
pure compute (no IO); it takes a `Tx` and a list of `Rule`s
and returns a merged patch (the `RulePatch` shape — see
`lib/rules/engine.ts:186`). The chokepoint applies the patch
in a single transaction.

Phase 4 ships the **existing web engine verbatim**:
- **Conditions**: the recursive `all` / `any` / `not` tree
  over the ~14 leaf comparators — `merchant` (`is` /
  `contains` / `startsWith`), `amount` (incl. `between`),
  `account_id`, `category_id`, `counterparty_id`, `currency`,
  `date_dow`, `date_dom`, `kind`, `tag_id`, `note`.
- **Actions** (9): `set_category`, `set_counterparty`,
  `set_merchant`, `set_note`, `set_kind`, `add_tag`,
  `remove_tag`, `mark_reviewed`, `split`.

The iOS rule builder's field set is **identical** to the web's
(per `lib/rules/types.ts::Condition` and `::Action`). The only
candidate **native addition** is a **regex** merchant leaf
(the web has no regex comparator); if shipped, it slots in
beside `is` / `contains` / `startsWith` and is the one thing
the web would later port back.

## §4. Feature: Transfers CRUD

The web's transfers are **paired entries** with the same
`transferGroupId`: a `kind='transfer'` entry with one account
leg in account A and another in account B. The projection
already pairs them; the Activity tab shows them as two
rows with a "Transfer" badge. Phase 4 adds the **creation +
edit + delete UI** for transfers specifically.

### 4.1 — iOS Phase 4 surface

The Add Transaction form (Phase 2's `AddTransactionView`)
gets a **Transfer** kind option. Selecting Transfer shows a
two-account form:

```
┌─────────────────────────────────────┐
│  ← New Transaction         [Save]   │
├─────────────────────────────────────┤
│  [Expense] [Income] [Transfer]      │
│                                      │
│  From account                        │
│  Chase Checking                  ▾   │
│                                      │
│  To account                          │
│  Ally HYSA                        ▾   │
│                                      │
│  Amount                              │
│  ┌──────────┐  USD ▾               │
│  │  500.00  │                       │
│  └──────────┘                       │
│                                      │
│  Date                                │
│  Jun 12, 2026                    ▾   │
│                                      │
│  Note (optional)                     │
│  ┌──────────────────────────────┐   │
│  │ Transfer to savings          │   │
│  └──────────────────────────────┘   │
│                                      │
│  [Cancel]                            │
└─────────────────────────────────────┘
```

The form submits to `Args.createTransfer({fromAccountId,
toAccountId, fromAmount, toAmount?, date, time?, note,
sourceTemplateId?})` (Phase 2's action; args per
`lib/db/domain/_args.ts:180`). Note it's **`fromAmount`**
(required) plus an optional **`toAmount`** for cross-currency
transfers — **not** a single `amount`. The chokepoint posts
the paired entries atomically (the two legs are one entry; the
balance triggers fire for both accounts).

### 4.2 — Edit + delete

The Activity tab's transfer rows (rows with the "Transfer"
badge) get an "Edit transfer" action. Tapping opens an
edit form similar to the Add Transfer form. Saving
submits `Args.updateTransfer({id, patch: TransferPatch})`.

Deleting a transfer posts `Args.deleteTransfer({id})`
(with a confirm dialog: "Delete this transfer? The two
leg entries will be removed.").

## §5. Feature: Merchants / categories / tags admin

The web's reference data (merchants, categories, tags) has
CRUD UIs in the desktop sidebar's "Ledger" section
(`app/(main)/merchants/`, `app/(main)/categories/`,
`app/(main)/tags/`). The web supports rename, merge,
archive, and color.

### 5.1 — iOS Phase 4 surface

The Settings tab gets 3 sections: **Categories**,
**Merchants**, **Tags**. Each section is a list of the
reference data with edit affordances:

```
┌─────────────────────────────────────┐
│  ← Categories                        │
├─────────────────────────────────────┤
│  🛒 Groceries                       │
│  ☕ Food & Dining                    │
│  🚗 Transport                        │
│  🏠 Housing                          │
│  💼 Income                           │
│  ...                                 │
│                                      │
│  [+ New Category]                    │
└─────────────────────────────────────┘
```

Tapping a row opens an edit form:

```
┌─────────────────────────────────────┐
│  ← Edit Category · Groceries        │
├─────────────────────────────────────┤
│  Name                                │
│  ┌──────────────────────────────┐   │
│  │ Groceries                    │   │
│  └──────────────────────────────┘   │
│                                      │
│  Icon                                │
│  🛒                              ▾   │
│                                      │
│  Color                               │
│  ● ● ● ● ● ● ● ● ●              ▾   │
│                                      │
│  Parent (3-level taxonomy)           │
│  Food                              ▾ │
│                                      │
│  ── Danger zone ──                   │
│  [Merge into ▾]                      │
│  [Delete]                            │
│                                      │
│  [Cancel]              [Save]        │
└─────────────────────────────────────┘
```

The "Merge into" action opens a sub-picker; the user picks
a target category; the chokepoint updates every entry
referencing the source category to the target, then the
source is **deleted** (there is **no `archiveCategory`
action** — categories are create / update / delete only,
`lib/db/domain/_args.ts:119`; no archive flag exists). Merge
is therefore re-point-then-delete; once every entry has been
re-pointed to the target, deleting the now-unreferenced source
leaves all historic entries resolving against the target.

### 5.2 — Tags

Tags are simpler than categories: no parent (the web uses a
color from a fixed palette). The edit form is just name +
color + delete (tags, like categories, are create / update /
delete only — there is no archive).

### 5.3 — Merchants

Merchants are counterparties + canonical names. The edit
form is: name + verify/unverify (a counterparty that
matches incoming transactions is "verified" — the
counterparty resolver uses the verified list first per the
web's `lib/db/domain/counterparties/queries.ts`). The
verify/unverify action surfaces in the Merchant Detail
sheet.

## §6. Feature: Saved searches

**Saved searches are a separate Activity-page feature** —
*not* a command-palette capability. The web's ⌘K palette only
navigates pages, opens add-expense, and searches
transactions / merchants / accounts; it does **not** "save the
current search." Saved searches are pinned Activity filter
sets, created from the Activity page itself
(`lib/use-saved-searches.ts`). The iOS Phase 4 surface mirrors
that Activity-page feature in the filter bar.

### 6.1 — iOS Phase 4 surface

The Activity tab's filter bar (Phase 1.0) gets a **Save
search** button (after the user has applied filters):

```
┌─────────────────────────────────────┐
│  Activity                            │
├─────────────────────────────────────┤
│  🔍 [starbucks          ]  [Save]   │
│  Account: All  Date: Last 30 days   │
│  Category: All                       │
│  ...                                 │
└─────────────────────────────────────┘
```

Tapping **Save** opens a sheet:

```
┌─────────────────────────────────────┐
│  Save search                         │
├─────────────────────────────────────┤
│  Name                                │
│  ┌──────────────────────────────┐   │
│  │ Starbucks recents            │   │
│  └──────────────────────────────┘   │
│                                      │
│  [Cancel]              [Save]        │
└─────────────────────────────────────┘
```

Saved searches appear in the Activity tab's **Saved
searches** section (above the filter bar):

```
┌─────────────────────────────────────┐
│  Activity                            │
├─────────────────────────────────────┤
│  ⭐ Starbucks recents (3)            │
│  ⭐ Groceries this month (12)        │
│  ⭐ Un-cleared (8)                   │
│  ──────────                          │
│  [Search bar / filter bar]           │
│  ...                                 │
└─────────────────────────────────────┘
```

Tapping a saved search applies the filters and shows the
matching transactions.

### 6.2 — iOS implementation

On the **web**, saved searches are **localStorage-only** —
persisted under the key `finch.savedSearches`
(`lib/use-saved-searches.ts:5,30`), **client-only**, **not**
in the `app_state` table or the server DB. They never travel
with a DB export / backup, and there is **no `setAppState`
action** for them (they bypass the chokepoint entirely; the
shape is `{id, ledgerId, name, query, direction, tagId,
fromDate, toDate, minAmount, maxAmount}`).

The iOS port may store them in the **native local DB**
(e.g. an `app_state` row) for convenience — but frame that as
a **native divergence**, not "the same as web." Like the web,
they should **not** travel with the pack-based sync model
(Phase 5), matching the web's local-only behavior.

The iOS Phase 4 surface ships a **+ button** on the
saved-searches section for creating a new one, and a
**swipe-to-delete** on each saved search.

## §7. Feature: Bulk recategorize

The web's bulk recategorize is a **multi-select entries +
apply category** flow. The web's Activity tab has a
multi-select mode (tap to select, tap to deselect; a
bottom bar appears with "Select all" + "Apply category").

### 7.1 — iOS Phase 4 surface

The Activity tab's transaction list gets a multi-select
mode (entered by long-press on a row, or via a "Select"
button in the toolbar). In multi-select mode, the rows
show checkmarks; the bottom bar changes to:

```
┌─────────────────────────────────────┐
│  ← Activity · 3 selected       [✕] │
├─────────────────────────────────────┤
│  ✓ Jun 3   Coffee Bar        -$6.50│
│  ☑ Jun 8   Whole Foods      -$87.23│
│  ☑ Jun 18  Starbucks       -$4.75  │
│  ✓ Jun 22  Amazon           -$45.67│
│  ...                                 │
├─────────────────────────────────────┤
│  [Select all]   [Apply category ▾]  │
└─────────────────────────────────────┘
```

Tapping **Apply category** opens a sub-picker; the user
picks a category; the chokepoint posts
`Args.bulkRecategorize({ids, categoryId})` (one action call
for the whole batch).

## §8. Feature: FX / base tools

The web's FX / base tools are a Settings › Ledger section
that lets the user:

- Override the **base currency** of a ledger (a destructive
  action; re-rates every historic entry at the new base)
- Edit **historical rates** (the `exchange_rates` table; the
  user can fix a rate that was incorrectly converted)
- **Rename a currency** (e.g., `USD` → `US Dollar` in the
  display; the storage is unaffected)

### 8.1 — iOS Phase 4 surface

The Settings tab's active-ledger section gets a **Base
currency** row (showing the ledger's base + a "Change"
button). Tapping opens:

```
┌─────────────────────────────────────┐
│  ← Base currency · Personal         │
├─────────────────────────────────────┤
│  Current base: USD                   │
│  New base:                         ▾ │
│                                      │
│  ⚠️  Warning: changing the base      │
│  currency will re-rate 1,247         │
│  historic entries at the new base.   │
│  This is a destructive action; the  │
│  previous base is preserved in the  │
│  rate history.                       │
│                                      │
│  [Cancel]              [Change]      │
└─────────────────────────────────────┘
```

The **Edit historical rates** sub-section shows a list of
rates (the `exchange_rates` table, `lib/db/core/schema.ts:296`;
each row is a `{currency, date}` rate **into the ledger base**,
with an optional `source`). Tapping a rate opens an edit form.

The **Rename currency** sub-section lets the user edit
the display name (per ledger or globally; the web's
implementation is global).

### 8.2 — iOS implementation

The FX / base tools use the existing Phase 2 actions:

- `Args.changeLedgerBase({ledgerId, newBase})` — the
  destructive re-rate
- `Args.setExchangeRate({date, currency, rate, source?})` —
  the historical rate editor (a rate for `currency` on `date`,
  expressed against the ledger base; `_args.ts:210`). **Not**
  `{from, to, date, rate}` — there is no `from`/`to` pair.
- `Args.deleteExchangeRate({date, currency})` — remove a
  rate (`_args.ts:211`)
- `Args.setDisplayCurrency({ledgerId, currency})` — the
  per-ledger display-currency override (Phase 1.5's UI;
  Phase 4 may refine)

The "Rename currency" action doesn't have a dedicated
Phase 2 action; it's a UI-only change (the currency
display name is in the `app_state` table). Phase 4
adds the action via a follow-up if needed; for Phase 4
it's a UI affordance only.

## §9. Cross-cutting UI patterns

All 7 features share these patterns:

- **Form sheets** for the create / edit flows (the same
  pattern as Phase 2's 7 write screens)
- **Multi-step navigation** for the reconcile flow (Step 1,
  Step 2, Step 3 with a `NavigationStack` push)
- **Multi-select mode** for the bulk recategorize flow (the
  standard iOS multi-select pattern: long-press to enter;
  rows show checkmarks; bottom bar shows the action)
- **Confirmation dialogs** for destructive actions (delete
  category, change base currency, delete rule, etc.) —
  the iOS standard `.confirmationDialog` modifier
- **Error states**: typed `StoreError` alert (same pattern
  as Phase 2; the `I18nError` is mapped to a localized
  message)
- **Accessibility**: every form field has a VoiceOver
  label; the multi-select mode announces "3 items
  selected"; the destructive actions have an
  "Are you sure?" prompt that's read aloud

## §10. Open questions

The plan's §14.1 still-open questions mostly land in later
phases. For Phase 4 specifically:

**Not blocking Phase 4 (decide later)**:

- **CSV statement import** (the §2.4 follow-up): the manual
  reconcile flow covers 80% of the use case. The CSV
  import is a Phase 4.5 follow-up if the user research
  demands it.
- **Backfill progress UI**: the web's backfill is a single
  transaction (the chokepoint iterates the entries
  inside the transaction). On a 10,000-entry ledger, the
  backfill can take 5-10 seconds. The iOS UI shows a
  progress bar with a cancel button. The cancel rolls
  back the transaction (the partial backfill is
  discarded).
- **Rule engine condition/action set**: the web's engine is
  already rich — a recursive `all`/`any`/`not` tree over ~14
  leaf comparators + 9 action types (per §3). Phase 4 **ports
  it as-is**. The only candidate native addition is a **regex**
  merchant comparator (the web has none today); amount ranges
  (`between`) and set-counterparty already exist on the web,
  so they are not additions.
- **FX rate editor scope**: the web's `setExchangeRate`
  action is per `{currency, date}` (a rate into the ledger
  base), `_args.ts:210`. The iOS editor is a per-rate form.
  The "bulk edit rates" question (e.g., "re-rate all entries
  in a date range") is a future phase.
- **Anomaly threshold tuning UI**: the existing
  `anomalyScore` thresholds from the web are used as-is
  in Phase 1.0. A UI for tuning the thresholds is a
  Phase 4 follow-up (the `lib/insights.ts` constants
  become a `Settings › Insights` section).
- **Saved searches sync across devices**: the iOS app stores
  saved searches locally (a native divergence — the web keeps
  them in `localStorage` under `finch.savedSearches`, never in
  the DB). They don't sync across devices: the web's are
  per-browser and never travel with an export / backup, and
  the iOS port should keep them out of the pack-based sync
  model (Phase 5). Phase 5 may revisit.

**Specifically for the rules engine**:

- **Live rules on new entries**: the web's chokepoint
  applies the live rules on every `postEntry` (the
  rules engine runs after the entry is posted, applying
  any matching rules' actions). The iOS port mirrors
  this. If the user creates a rule with a condition that
  matches an existing entry, the rule doesn't apply
  retroactively (the user must explicitly backfill).
- **Rule ordering**: the web's rules engine is **not**
  first-match-wins. **All** matching active rules run, in
  **priority order** — lower `priority` first — and a later
  rule's `set_*` action **overrides** an earlier one's; the
  patches merge into a single `RulePatch`
  (`lib/rules/engine.ts:186-193`, `lib/rules/types.ts:73`).
  The `appliedRuleIds` trail records every rule that fired, in
  order, even when a later rule overrode its writes. The iOS
  port matches: run all matches in priority order, last write
  wins.

**Not blocking Phase 4 because they're Phase 5+ by design**:

- **Auto-pack debounce + iCloud folder-watcher** — Phase 5
- **App Intents / Siri / Share Extension / Spotlight /
  notifications / biometric lock** — Phase 6
- **Widgets / Live Activities / Watch** — Phase 7
- **Row-level sync** — Phase 8

## §11. Out of scope (firm)

These are explicitly NOT in Phase 4:

- **No new chokepoint actions** — the 74 Phase 2 actions
  are the full set (Phase 6.5's `setEntryAttachment` brings
  the running total to 75; Phase 4 doesn't add more).
  Phase 4 wires UI to them.
- **No new tabs** — the 6 tabs (Accounts, Activity,
  Budgets, Insights, Scheduled, Settings) are unchanged.
  New features surface within existing tabs.
- **Auto-pack debounce + iCloud folder-watcher** —
  Phase 5.
- **App Intents / Siri / Share Extension / Spotlight /
  notifications / biometric lock** — Phase 6.
- **Widgets / Live Activities / Watch** — Phase 7.
- **Row-level sync** — Phase 8.
- **Bank/feed import** — out of scope per the plan's §7
  boundary. Reconcile uses manual CSV import (Phase 4.5
  follow-up) or manual balance entry (Phase 4).
- **Anomaly threshold tuning UI** — Phase 4 ships the
  rules engine + bulk recategorize; the threshold tuning
  is a follow-up.
- **FX rate bulk editor** — Phase 4 ships the per-rate
  editor; the bulk editor is a follow-up.
- **Multi-user / shared ledgers** — single-user iCloud
  account = single finch install. Per the plan's §10
  resolved decision.
- **Android** — not in the plan.

## §12. Spec self-review

(Inline review at write time; not part of the published
spec.)

- **Placeholders**: none. Every section has concrete
  content. The 7 features each have a UI sketch + a wire
  shape.
- **Internal consistency**: §2's reconcile uses
  `Args.setCleared` + `Args.reconcileAccount` (both Phase
  2 actions). §3's rules engine uses `Args.backfillRule`
  + `Args.updateRule({id, patch: {isActive: true|false}})`
  (the rule's `isActive` field is patchable via the
  existing `updateRule` action — no separate
  `setRuleEnabled` action; the Phase 2 chokepoint
  inventory has no `setRuleEnabled`). §4's
  transfers use `Args.createTransfer` +
  `Args.updateTransfer` + `Args.deleteTransfer` (all
  Phase 2). §5's reference data uses
  `Args.createCategory` + `Args.updateCategory` +
  `Args.deleteCategory` (all Phase 2; categories have **no**
  `archiveCategory` action — they're create / update / delete
  only, `_args.ts:119`; merge is re-point-then-delete). §6's
  saved searches are **localStorage-only on the web**
  (`finch.savedSearches`), never in `app_state` / the server
  DB; the iOS port storing them in a native local row is a
  divergence, not a match. §7's bulk
  recategorize uses `Args.bulkRecategorize` (Phase 2). §8's
  FX uses `Args.changeLedgerBase` + `Args.setExchangeRate`
  (both Phase 2). All 7 features use existing Phase 2
  actions; no new chokepoint surface.
- **Scope**: focused on Phase 4. Phases 1.0, 1.5, 2, 3
  are referenced as completed. Phase 5+ are explicitly
  out of scope (§11). The estimated scope (2-3 months)
  reflects the UI-heavy nature of the phase.
- **Ambiguity**: §2's reconcile UI has concrete step-by-
  step sketches. §3's rule builder has concrete form
  fields. §4's transfer form has a concrete layout. §5's
  category edit has a concrete form. §6's saved-search
  flow has concrete UI. §7's bulk recategorize has a
  concrete multi-select UI. §8's FX editor has concrete
  form fields. §10 enumerates the open questions with
  proposed answers.
