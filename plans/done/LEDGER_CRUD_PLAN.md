# Ledger CRUD — plan

Status: **shipped** (2026-06-06). This doc is kept as the design record. The
implementation followed the §10 file touch list and the 3-commit split
(backend round-trip → provider + persistence → UI), plus a documented
postScheduled fix.
Scope: `frontend/` (server-backed SQLite app)

> Implements the web-app side of **`plans/ios-macos/IOS_MACOS_PLAN.md` §14.8** (resolved
> decision: "Ledger CRUD — *for both apps*"; capability matrix §3 row 39). The
> schema change here stays on the **shared `SCHEMA_VERSION` lineage** so `.finch`
> packs keep round-tripping between the web and native apps.
>
> **Closes the last cross-app implication from `IOS_MACOS_PLAN.md §8`** — the
> web now has the same ledger-CRUD surface the native plan calls for, so
> native-created ledgers will round-trip through packs cleanly.

Ledgers are the app's top-level books (Personal / Family / Side studio / …), yet
they are the **only core entity with no CRUD**: you cannot create, rename,
restyle, re-default, or delete one. The switcher's **"New ledger" menu item is a
dormant TODO** (`components/ledger-switcher.tsx`). This plan adds full ledger
CRUD on the same store → `/api/mutate` → SQLite round-trip every other entity
uses.

---

## 1. Current state

### Schema (`lib/db/schema.ts`)

```sql
CREATE TABLE ledgers (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  base_currency TEXT NOT NULL DEFAULT 'SGD',
  is_default    INTEGER NOT NULL DEFAULT 0,
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL
);
```

No `color` / `tagline` — those cosmetic fields live only in `data/ledgers.json`.
Every per-ledger table carries `ledger_id` with `ON DELETE CASCADE`
(accounts, account_groups, categories, tags, counterparties, transfer_groups,
transactions (+ splits/tags via their own FKs), budgets, budget_groups,
scheduled_templates (+ scheduled_splits), holdings, rules,
transaction_attachments).

### What already exists (keep, don't rebuild)

- **Read**: `lib/db/queries/ledgers.ts` → `LedgerRow { id, name, base, isDefault }`,
  `listLedgers()`; projected as `store.ledgers`; `ProjectedState.ledgers`.
- **Update (base currency only)**: `changeLedgerBase` store action →
  `recomputeAmountBases()` rewrites every locked `amount_base` (+ splits,
  opening_balance_base, balance recompute) under the new base, in a SAVEPOINT.
  Surfaced in Settings › Ledger with a confirm dialog. This *is* the "U" for
  `base_currency` — the rest of update (name/color/tagline/default) is missing.
- **Provider** (`components/ledger-provider.tsx`): merges projected rows with
  static JSON for `color` / `tagline` / `accounts` / `txns` counts; falls back to
  pure static pre-hydration. `activeId` is **in-memory `useState`** — resets to
  the default ledger on every reload.
- Seed inserts the four mock ledgers from `data/ledgers.json`.

### Gaps

| Operation | Status |
|---|---|
| Create ledger | ❌ (dormant "New ledger" menu item) |
| Rename / color / tagline | ❌ (cosmetics aren't even in the DB) |
| Set default ledger | ❌ (`is_default` is seed-only) |
| Delete ledger | ❌ |
| Live account/txn counts in the switcher | ❌ (static JSON numbers) |
| Active-ledger persistence across reloads | ❌ |
| `postScheduled` hardcodes `ledgerId = 'personal'` | 🐛 (`lib/db/mutations.ts:205`) |

---

## 2. Schema change

Add the cosmetic columns to the canonical `CREATE TABLE ledgers`:

```sql
color   TEXT,     -- accent dot in the switcher; nullable → fallback hue
tagline TEXT,     -- one-line description shown in the switcher dropdown
```

Per the clean-baseline convention in `lib/db/schema.ts`: edit the canonical
`SCHEMA`, bump `SCHEMA_VERSION` to a new datetime, and add a `MIGRATIONS` entry
(`ALTER TABLE ledgers ADD COLUMN color TEXT` + `… tagline TEXT`) so existing dev
DBs carry forward. Seed maps `color`/`tagline` from `data/ledgers.json` into the
INSERT.

---

## 3. Queries — `lib/db/queries/ledgers.ts`

- **`LedgerRow`** grows: `color: string | null`, `tagline: string | null`,
  `accounts: number`, `txns: number` — counts come from the DB, replacing the
  stale static numbers:

  ```sql
  SELECT l.*, 
         (SELECT COUNT(*) FROM accounts a WHERE a.ledger_id = l.id AND a.is_active = 1) AS accounts,
         (SELECT COUNT(*) FROM transactions t WHERE t.ledger_id = l.id) AS txns
    FROM ledgers l ORDER BY l.is_default DESC, l.name
  ```

- **`createLedger(exec, { id, name, base, color, tagline })`** — plain INSERT,
  `is_default = 0`. Id generated app-side (`ledger-<ts36>` like other entities).
- **`updateLedger(exec, id, patch { name?, color?, tagline? })`** — dynamic-SET
  pattern (mirror `updateCategory`). Base currency stays on the dedicated
  `changeLedgerBase` path (it has reconversion semantics).
- **`setDefaultLedger(exec, id)`** — one statement pair in a SAVEPOINT:
  `UPDATE ledgers SET is_default = 0` then `… SET is_default = 1 WHERE id = ?`.
- **`deleteLedger(exec, id)`** — see §5; explicit ordered deletes in a SAVEPOINT,
  **not** bare FK-cascade.

## 4. Mutations + store

- `lib/db/mutations.ts`: new cases `createLedger`, `updateLedger`,
  `setDefaultLedger`, `deleteLedger` (validation: non-empty name; known currency;
  guards in §5). Fix the `postScheduled` hardcode to use the template's
  `ledger_id` while in here.
- `lib/store.ts`: matching actions with optimistic updates →
  `syncMutation(...)`, mirroring the account-group actions:
  `createLedger(input): string`, `updateLedger(id, patch)`,
  `setDefaultLedger(id)`, `deleteLedger(id)`.

## 5. Delete semantics (the risky one)

- **Guard: cannot delete the last ledger** (mutation throws; UI disables).
- **Explicit ordered deletes**, not raw FK cascade: `transactions.account_id`
  is `ON DELETE RESTRICT`, and SQLite's cascade ordering across multiple
  referencing tables isn't something to bet balances on. Inside a SAVEPOINT:

  ```
  transaction_attachments (rows; collect rel_paths first)
  → transactions (splits/tags follow via their own FK CASCADE)
  → scheduled_splits → scheduled_templates → rules → holdings
  → budgets → budget_groups → transfer_groups
  → accounts → account_groups → categories → tags → counterparties
  → ledgers row
  ```

- **Attachment files on disk**: after the SAVEPOINT commits, sweep the deleted
  transactions' `attachments/<transaction_id>/` directories from the server-side
  attachments dir (collect the paths *before* deleting the rows). Same pattern
  the pack-builder/vacuum sweep uses for orphans.

- **Default reassignment**: deleting the default ledger promotes another row
  (first by `name`) to `is_default = 1` in the same SAVEPOINT.
- **Preference cleanup**: remove the ledger's key from the
  `displayCurrencyByLedger` JSON map in `app_state`.
- **Active-ledger handoff**: if the deleted ledger is active, the provider
  switches `activeId` to the (possibly new) default after the projection lands.
- UI confirm is a **typed-name dialog** (like GitHub repo delete) showing the
  blast radius from the live counts: "Deletes N accounts, M transactions, K
  budgets…".

## 6. Provider + persistence

`components/ledger-provider.tsx`:

- Drop the static cosmetic merge — `color`/`tagline`/counts now arrive on the
  projected `LedgerRow`. Keep `data/ledgers.json` purely as the pre-hydration
  fallback list.
- **Persist `activeId` per device in `localStorage`** (`finch.activeLedger`),
  hydrating after mount so SSR and first client render match (no hydration
  mismatch).
  Rationale: which book you're *looking at* is a device/session choice — your
  phone on Family shouldn't flip the desktop off Personal. (The synced
  alternative — an `app_state` key — is a one-line swap if we change our mind.)
- Guard: if the persisted id no longer exists (deleted on another device),
  fall back to the default ledger.

## 7. UI

- **Switcher (`components/ledger-switcher.tsx`)**
  - Wire the dormant **"New ledger"** item → create dialog: name (required),
    base currency (`CURRENCIES` select), color (color input, like scheduled),
    tagline (optional). On create: toast + `setActiveId(newId)` so the user
    lands in the empty new book.
  - Dropdown rows show **live** `accounts · txns` counts + color dot from the
    projected rows.
- **Settings › Ledger (`app/(main)/settings/ledger/page.tsx`)** — "This ledger"
  section gains:
  - **Rename / color / tagline** (one edit dialog, mirroring the account edit).
  - **Default ledger** row: "Make default" button (hidden when already default).
  - **Danger zone**: "Delete ledger" → typed-name confirm (§5). Disabled with
    an explanatory hint when it's the only ledger.
- **Empty new ledger**: existing empty states already cover Accounts ("No
  accounts yet") and Budgets; verify /add gracefully prompts to create an
  account first rather than silently failing.

## 8. Edge cases

- **Create with a base currency that has no FX rows**: allowed (constrained to
  the `CURRENCIES` list, which the seeded `exchange_rates` cover); conversion
  falls back exactly as `useMoney` does today.
- **Duplicate names**: allowed (ids are the identity); no unique constraint.
- **Deleting mid-flight work**: scheduled auto-generation (`generateDueScheduled`)
  iterates `scheduled_templates` rows — they're deleted with the ledger, so no
  orphan generation.
- **`'personal'` fallbacks** (`t.ledgerId ?? 'personal'` in selectors,
  `args.ledgerId || 'personal'` in mutations): these are pre-hydration/seed
  conveniences keyed to the seeded id. They're harmless while `personal` exists,
  but deleting it makes the fallbacks dangle → fallbacks should resolve to **the
  default ledger's id**, not a literal. Sweep as part of this work.
- **Reset** (`resetDb`) reseeds the four mock ledgers — user-created ledgers are
  wiped like all other data. Expected.

## 9. Tests (mirror the in-memory patterns in `lib/db/mutations.test.ts`)

- `createLedger` → appears in `listLedgers` with counts 0/0; create an account +
  transaction under it → counts reflect.
- `updateLedger` renames / recolors; `changeLedgerBase` still works after.
- `setDefaultLedger` flips exactly one `is_default`.
- `deleteLedger`:
  - removes every ledger-scoped row (assert counts across the §5 table list),
  - leaves other ledgers' rows untouched,
  - reassigns default when deleting the default,
  - cleans the `displayCurrencyByLedger` key,
  - throws on the last ledger.
- Provider: persisted `activeId` referencing a deleted ledger falls back to
  default (unit-test the resolver).

---

## 10. File touch list

| Path | Change |
|---|---|
| `lib/db/schema.ts` | `ledgers.color` + `ledgers.tagline` (canonical + MIGRATIONS entry + version bump). |
| `lib/db/seed.ts` | Seed color/tagline into the ledgers INSERT. |
| `lib/db/queries/ledgers.ts` | `LedgerRow` + counts; `createLedger` / `updateLedger` / `setDefaultLedger` / `deleteLedger`. |
| `lib/db/mutations.ts` | Four new cases + `postScheduled` ledger-id fix + default-ledger fallback sweep. |
| `lib/store.ts` | Four new actions (optimistic + `syncMutation`). |
| `components/ledger-provider.tsx` | Drop static merge; persist `activeId`; deleted-active handoff. |
| `components/ledger-switcher.tsx` | Wire "New ledger" dialog; live counts. |
| `app/(main)/settings/ledger/page.tsx` | Rename/color/tagline dialog; Make-default; Danger-zone delete. |
| `lib/db/mutations.test.ts` (or new `ledgers.test.ts`) | §9 coverage. |
| `plans/MASTER_PLAN.md` | Strike "ledger CRUD" once shipped. |

**Suggested commit split**

1. Schema + queries + mutations + store (full backend round-trip, tested).
2. Provider: projected cosmetics/counts + persisted active ledger.
3. UI: create dialog + settings edit/default/delete.

---

## Out of scope

- ❌ **Archiving** ledgers (soft-hide like accounts) — delete is hard, matching
  the app's hard-delete philosophy; archive can come later if wanted.
- ❌ Moving/merging data **between** ledgers.
- ❌ Per-ledger starter category packs on create (new ledgers start empty; a
  "copy categories from…" option is a nice v2).
- ❌ Multi-user / sharing semantics.
