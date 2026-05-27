# Full CRUD parity — design plan

Status: **complete** (Phases 0–7 shipped; see §7). Every user-facing entity now has
full Create / Update / Delete (or archive) wired end-to-end, all `app_state`
override shims are retired, and the balance-recompute gap is fixed. The sections
below are kept as the design record; the per-entity coverage matrix (§1) and the
phasing checklist (§7) reflect the delivered state.

## 0. Schema readiness (reviewed)

The DB schema (`lib/db/schema.ts`) was built from the design doc and is **robust
enough** — nearly every CRUD operation is already supported by existing columns,
FKs, and indexes. Specifically already in place: per-table `ledger_id`, sensible
`ON DELETE` rules (CASCADE for ledger children, `SET NULL` for txn→category/
counterparty/transfer, `RESTRICT` for txn→account), archive flags
(`accounts.is_active`, `recurring_templates.is_active/is_archived`), the full money
model (`amount`/`amount_base`/`exchange_rate`/`exchange_rate_date`), and the
`transaction_tags` M2M with cascade. The columns the override shims want mostly
exist already (`budgets.amount`, `counterparties.is_verified`/`aliases`), so
retiring those shims is a **logic** migration, not a schema change.

**Schema changes genuinely required / recommended:**
- **(required) `accounts` display columns** — add `color`, `last4`, `institution`,
  `routing` (today in MOCK + the `accountOverrides` shim). Needed for account
  Create and to retire `accountOverrides`. Seed from `data/accounts.json`.
- **(recommended) `categories` `color`/`hue` (+ optional `is_active`)** — created
  categories currently fall back to a default hue and can't be soft-deleted.
- **(optional) `UNIQUE(ledger_id, name)`** on `categories` / `tags` to prevent
  duplicate creates.
- Everything else (delete/archive, edits) is covered by existing columns. The
  `budgets` table and `counterparties.is_verified/aliases` are ready for shim
  retirement with **no** schema change.

**Operational prerequisite — schema versioning.** The schema is
`CREATE TABLE IF NOT EXISTS` with no `PRAGMA user_version`/migration, so *adding* a
column (e.g. the accounts ones above) does not reach an existing
`.data/finch.sqlite3` file — queries then fail until the file is deleted. Before
any column-adding phase, add a version-gated step in `lib/db/server.ts`: bump a
`SCHEMA_VERSION`, and on mismatch run the needed `ALTER TABLE`s (or rebuild from
seed for a dev DB). Low effort; removes a real footgun.

**Not a schema gap, but the key correctness item:** balance maintenance is
INSERT-only (see §4) — handled in app logic via `recomputeAccount`, not new
triggers.

## 1. Coverage — delivered

All ✅ below are live (mutation + store action + UI), verified by `bun test` +
per-phase browser smokes.

| Entity | C | U | D |
|---|---|---|---|
| Transactions | ✅ | ✅ (recomputes balance) | ✅ soft (`status='cancelled'`, recomputes) |
| Accounts | ✅ | ✅ (table) | ✅ archive (`is_active=0`) + hard-delete when empty |
| Categories | ✅ (icon+hue) | ✅ name/type/icon/hue | ✅ hard (txns → uncategorised) |
| Budgets (per-cat) | ✅ (table) | ✅ (table) | ✅ remove row |
| Goals | ✅ | ✅ name/target/eta + contribute | ✅ hard |
| Tags | ✅ | ✅ name/color | ✅ hard (assignments cascade) |
| Subscriptions | ✅ | ✅ name/amount/next | ✅ hard |
| Scheduled items | ✅ | ✅ | ✅ hard |
| Recurring templates | ✅ | ✅ fields + split % | ✅ hard (splits cascade) |
| Transfers | ✅ | ✅ (rewrites both legs, recomputes) | ✅ hard (both legs + group, recomputes) |
| Merchants / counterparties | ✅ | ✅ rename/category + verify/unverify + add/remove alias | ✅ hard (txns SET NULL) |

Shims retired: `accountOverrides`, `budgetOverrides`, `verifiedExtra`/`aliasExtra`
— `app_state` is no longer read or written. Schema reached **v4** (opening_balance,
account display cols, categories.hue) via the `migrate()` runner in §0.

## 2. Principles

- **One pattern per operation.** Server handler in `applyMutation` (validated at
  the boundary) + a store action that updates optimistically then `syncMutation`s
  and adopts the server's re-projection. Client-generated ids when the entity is
  used immediately after create (as `createTag`/`createCategory` already do).
- **Everything is ledger-scoped.**
- **Delete semantics chosen per entity** from its FK story (§3): *archive* (keep
  history) vs *hard delete* vs *soft cancel*.
- **Retire the override shims.** `accountOverrides` and `budgetOverrides` are
  transitional `app_state` JSON. Full Update means moving these edits onto the
  real `accounts` / `budgets` tables (and deleting the shims) — this both
  completes CRUD and removes the last non-table mutable state.
- **A delete/edit confirm UX**, shared (`<ConfirmDialog>` + a row "⋯" menu with
  Edit / Delete), reused across detail screens.

## 3. FK & delete-semantics reference (from `schema.ts`)

| Table | Referenced by (ON DELETE) | Delete strategy |
|---|---|---|
| `accounts` | `transactions.account_id` **RESTRICT** | **Archive** (`is_active=0`; the list query already filters it). Hard-delete only when the account has no transactions. |
| `categories` | `transactions.category_id` **SET NULL**; recurring `*.category_id` RESTRICT (but we store NULL ids) | **Hard delete** safe → txns become uncategorized. Offer optional "reassign to…" first. |
| `counterparties` | `transactions.counterparty_id` **SET NULL** (we store NULL) | Hard delete safe. |
| `tags` | `transaction_tags.tag_id` **CASCADE** | Hard delete → assignments vanish automatically. |
| `transfer_groups` | `transactions.transfer_group_id` **SET NULL** | Delete = remove both legs + the group (see §4 Transfers). |
| `recurring_templates` | `recurring_splits.template_id` **CASCADE** | **Archive** (`is_active=0`) or hard delete (splits cascade). |
| `goals`, `subscriptions`, `scheduled_items` | none | Hard delete, trivially. |

## 4. Cross-cutting: balance recompute (must land first)

The `tr_update_account_balance` trigger fires **only AFTER INSERT**. So today,
cancelling (`deleteTransaction`) or editing a transaction's amount does **not**
recompute `accounts.current_balance` or the stored `balance_after` — the figure
goes stale. Full U/D requires a server helper:

```
recomputeAccount(exec, accountId):
  opening = current_balance − Σ(amount_base of that account's non-cancelled txns)   // or keep a stored opening
  walk the account's non-cancelled txns in date order, rewriting balance_after,
  set accounts.current_balance to the final value (+ refresh balance snapshots)
```

Call it after any mutation that cancels/deletes/edits an amount, or moves a
transaction between accounts. This is a prerequisite for transaction Update and
all Delete work that touches money. (Add unit tests asserting balance after an
edit/cancel.)

## 5. Per-entity plan

### Accounts — the flagship (also retires `accountOverrides`)
- **Schema**: add display columns the mock keeps elsewhere — `color`, `last4`,
  `institution`, `routing` — to `accounts`; seed them from `data/accounts.json`.
- **Create** `createAccount({ name, type, currency, groupId, openingBalance, color, last4 })`:
  insert with `current_balance = openingBalance`, `is_active=1`. New screen dialog
  (replaces the decorative "Add account" affordance).
- **Update** `updateAccount(id, patch)`: real `UPDATE accounts …` (the dead
  `queries/accounts.setAccountDetails` already does this — wire it). **Delete the
  `accountOverrides` slice** from the store, projection, seed, and the
  `setAccountDetails` mutation; the account detail page reads/writes the table.
- **Delete** `archiveAccount(id)` → `is_active=0` (RESTRICT-safe); offer hard
  delete only when it has no transactions.

### Categories
- **Update** `updateCategory(id, { name, type, icon })` (extend `renameCategory`).
- **Delete** `deleteCategory(id)` → hard delete (txns SET NULL → uncategorized),
  with an optional "move transactions to …" reassign step in the confirm dialog.

### Budgets (retire `budgetOverrides`)
- Move budget edits onto the `budgets` table (seeded already). `setBudget` →
  `UPDATE budgets`/insert; add **delete** (remove the budget row). Drop the
  `budgetOverrides` app_state slice from store/projection/seed.

### Goals
- **Update** `updateGoal(id, { name, target, eta })`; allow `contributeGoal` with
  negative (withdraw) already clamps at 0.
- **Delete** `deleteGoal(id)` (no FK).

### Tags
- **Update** `updateTag(id, { name, color })`.
- **Delete** `deleteTag(id)` (assignments cascade).

### Subscriptions
- **Update** `updateSubscription(id, patch)`; **Delete** `deleteSubscription(id)`.

### Scheduled items
- **Create / Update / Delete** `createScheduledItem` / `updateScheduledItem` /
  `deleteScheduledItem` (no FK). Add an editor dialog to `/scheduled`.

### Recurring templates
- **Create** `createRecurring(template + splits)`; **Update**
  `updateRecurring(id, patch)` (name/amount/frequency/dayOfMonth/account) beyond
  the split %; **Delete/archive** `deleteRecurring(id)` (splits cascade).

### Transfers
- **Update** `updateTransfer(groupId, patch)` (amount/date/note → rewrite both
  legs + recompute both accounts).
- **Delete** `deleteTransfer(groupId)` → delete both legs + the group, then
  `recomputeAccount` for both. (Soft or hard — likely hard, since a transfer is a
  unit.)

### Merchants / counterparties
- **Create** `createCounterparty({ name, category })` (wire the decorative "New
  merchant" button).
- **Update** `renameCounterparty` / `setCounterpartyCategory` / `removeAlias` /
  `unverify` (today only verify + add-alias exist — note these are
  `app_state` extras; consider folding into the table for symmetry).
- **Delete** `deleteCounterparty(id)` (txns SET NULL).

### Transactions (mostly done)
- Ensure `updateTransaction` and `deleteTransaction` call `recomputeAccount`
  (§4). Optionally add **hard delete** (vs soft cancel) and account reassignment.

## 6. Cross-cutting tasks

- **`RESET_TABLES`** already covers the tables; ensure new columns/tables seed on
  reset.
- **Shared UI**: a `ConfirmDialog` + an entity "⋯" menu (Edit / Delete) used by
  Accounts, Categories, Goals, Tags, Subscriptions, Recurring, Transfers, Merchants.
- **Tests**: one mutation test per new handler (create round-trips, update
  persists, delete removes + balances recompute, FK edge cases) — mirrors the
  existing `mutations.test.ts` style.
- **Backup caveat**: `buildState` reseeds reference data from JSON, so
  user-created accounts/categories/etc. aren't captured in a downloaded snapshot.
  Either accept (documented) or extend `buildState` to project created rows.

## 7. Phasing (each its own PR)

0. ✅ **Schema versioning** (§0) — `SCHEMA_VERSION` + `migrate()` in `schema.ts`,
   called from `server.ts` (stamp on fresh, ordered ALTER migrations on existing
   files). `MIGRATIONS[2]` adds `accounts.opening_balance` + backfills it.
1. ✅ **Balance recompute helper** (§4) — `recomputeAccount` /
   `recomputeForTransaction` in `queries/accounts.ts`, wired into
   `updateTransaction` / `deleteTransaction`; `opening_balance` is now stored at
   seed time. Fixes the stale-balance-after-edit/cancel bug.
2. ✅ **Accounts**: added display columns (`color`/`last4`/`institution`/`routing`,
   migration `MIGRATIONS[3]`) + `createAccount` + table-backed `updateAccount` +
   `archiveAccount`/`deleteAccount`; retired the `accountOverrides` shim (store,
   projection, seed, persist, breadcrumb). The accounts list + detail screens now
   read/write the real table; create dialog + archive-confirm UX added.
3. ✅ **Delete/archive everywhere else** + the shared confirm UX. Added a reusable
   `<RowActions>` (⋯ menu + built-in confirm dialog) and delete mutations/store
   actions for all of categories, goals, tags, subscriptions, recurring,
   transfers, merchants. UI wired on categories/goals/subscriptions/recurring/
   transfers; `deleteTransfer` recomputes both account balances, `deleteRecurring`
   cascades splits, `deleteCategory` SET-NULLs its txns. **Tags** and **merchants**
   have the full data path + tests but no UI yet — tags have no management screen,
   and the merchants list is still static-reference-driven (needs the same
   projection switch accounts got in Phase 2); both will get the ⋯ menu then.
4. ✅ **Full edit** for subscriptions / goals / recurring / categories (+ data path
   for tags / merchants). Added `updateCategory` (name/type/icon/**hue** — schema
   v4 adds `categories.hue`, seeded from JSON), `updateGoal`, `updateSubscription`,
   `updateRecurring` (name/amount/frequency/dayOfMonth/autoPost), `updateTag`,
   `updateCounterparty`. Edit dialogs wired via the shared `<RowActions onEdit>` on
   categories/goals/subscriptions and an Edit dialog on the recurring detail page
   (with an icon + hue picker for categories). Tags/merchants edit mutations are
   ready but unwired pending their UI surfaces (same as Phase 3).
5. ✅ **Budgets onto the table** (retired `budgetOverrides`): `setBudget` upserts a
   per-category `bud-<id>` row, `deleteBudget` removes it, and the budget amount is
   now projected as a `budgetByCategory` map (read by the budgets list/detail +
   insights). **Scheduled** CRUD (`createScheduledItem`/`updateScheduledItem`/
   `deleteScheduledItem` + an editor dialog and per-row `<RowActions>`).
   **Transfers** edit (`updateTransfer` scales both legs proportionally + recomputes
   both accounts; edit dialog on the list).

6. ✅ **Tags & merchants surfaces** (+ last shim retired). New **Tags** admin screen
   (`(ledger)/tags`) with create/edit/delete + a hue picker. The **Merchants** list
   now reads the projected `counterparties` (mock only supplies decorative
   hue/txCount by id), with create (`createCounterparty`), edit (rename/category),
   delete, verify/**unverify**, and add/**remove** alias. Routing `verifyCounterparty`/
   `addAlias` to the table (and adding unverify/removeAlias) let me **retire the last
   `app_state` shim** — `verifiedExtra`/`aliasExtra` are gone from the store, repo,
   seed and backup, and `app_state` is no longer read or written.

7. ✅ **createRecurring** — new recurring templates from a dialog on the recurring
   list (name/type/amount/frequency/dayOfMonth/account[+from for transfers]/auto-post;
   accounts referenced by name like the seed). Splits aren't created here (the
   detail screen edits split %s on existing templates).

**CRUD parity is complete** for every entity with a management surface, and all
`app_state` override shims are retired.

8. ✅ **Follow-ups.** Recurring **split management** — add/remove splits from the
   detail screen (`addRecurringSplit`/`removeRecurringSplit`, toggling
   `splits_enabled`), on top of the existing % editing. **Download backup fidelity** —
   the Settings download now streams the authoritative server DB via `GET /api/export`
   (`exportDbBytes`), so table-only edits (renamed accounts/merchants, budgets, etc.)
   are included rather than rebuilt from the store cache.

## 8. Risks

- **Balance correctness** (§4) is the subtle one — every amount-affecting U/D must
  recompute, and account moves touch two accounts.
- **FK RESTRICT** on accounts/categories — prefer archive/SET-NULL over hard
  delete; surface clear errors when a hard delete is blocked.
- **Shim retirement** (`accountOverrides`/`budgetOverrides`) ripples through
  projection + seed + screens — do each as its own verified step.
- **Backup/`buildState`** reseeds reference from JSON (§6).
