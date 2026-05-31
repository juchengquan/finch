# System → Settings consolidation + inline transfers

Status: **implemented & merged** on `feat/frontend`:
- `8176e0f` — refactor(settings): retire the `/system` page into Settings ›
  Devices + Ledger
- `29e286a` — feat(add): transfer type in the Add sheet (+ time on transfers)

Follow-on (also landed): surface transfer **time** through the transfers
read/edit path — see §4.

Scope: `frontend/` UI over the existing data layer. **No schema change.**
Builds on `ac7e731`, which merged the `(ledger)` route group into `(main)` and
dropped the dead bottom-nav links.

---

## 1. Goal

Finish retiring the legacy "Ledger admin / System" surface. Two threads:

1. **Retire `/system`.** Relocate its two real features — exchange-rate
   management and the device/sync list — into the consumer **Settings** area,
   and rewire navigation so nothing points at `/system`.
2. **Inline transfers.** Add a `transfer` type to the main Add sheet so a user
   can move money between accounts (including cross-currency) without a separate
   admin screen.

## 2. What shipped (inventory)

### 2.1 `/system` → Settings (`8176e0f`)
- **Deleted** `app/(main)/system/page.tsx` (191 lines).
- **Exchange rates** → new `components/exchange-rates.tsx`, embedded under
  **Settings › Ledger** (`settings/ledger/page.tsx`). Per-currency list with a
  trend sparkline + source badge (ECB / Yahoo / manual) and an add/delete dialog
  (`setExchangeRate` / `deleteExchangeRate`), SGD-pivoted. Editable only once the
  store is hydrated (`storeRates.length > 0`); static `LEDGER` data is the
  read-only SSR fallback. Links to `/fx` for a locked example.
- **Devices** → new `components/devices-list.tsx` on a new **Settings › Devices**
  tab (`settings/devices/page.tsx`; `settings-tabs.tsx` gains the tab). Read-only
  list sourced from `sync_log` (store `devices`).
- **Nav rewiring**: `command-palette.tsx` — "FX" → "Exchange rates"
  (`/settings/ledger`), "System" → "Devices" (`/settings/devices`);
  `fx/page.tsx` back-links + breadcrumb `/system` → `/settings/ledger`;
  `layout.tsx` / `PageShell.tsx` minor cleanups.

### 2.2 Inline transfers (`29e286a`)
- `add-expense-form.tsx`: a third tab `transfer` (expense / income / transfer).
  From / To account selects; the top amount ("SENT") is denominated in the
  source account's currency. When the two accounts hold different currencies, a
  **Received** field appears (amount in the destination currency) so the *actual*
  bank conversion is recorded rather than guessed from the mid-rate. Submits via
  `createTransfer({ fromAccountId, toAccountId, fromAmount, toAmount?, date,
  time?, note? })`.
- `add-expense-sheet.tsx` passthrough; `mutations.ts` + `store.ts` carry the
  transfer `time` through.

## 3. Data layer — already complete (UI-only change)

No new tables/columns. The new screens sit on store actions that predate this
batch:
- `createTransfer(TransferInput)` — `TransferInput.toAmount?` is optional; the
  `createTransfer` mutation records the rate as `toAmount / fromAmount` when
  given, else derives it from `exchange_rates` (same-currency → rate 1). Writes a
  `transfer_groups` row plus two linked `transactions` legs.
- `setExchangeRate` / `deleteExchangeRate`; the `exchangeRates` + `devices` store
  slices.

Because the data path already existed, the whole batch typechecks green with no
migration.

## 4. Follow-on — transfer time (landed)

`lib/db/queries/transfers.ts` adds `time` to the `Transfer` read shape
(`MAX(t.time)`) and to `TransferPatch` (`UPDATE … SET time`). Verified
consistent end-to-end: query write (`createTransfer` stamps `time` on **both**
legs) + read, the `updateTransfer` mutation/store patch, the client
`selectTransfers` mirror (`lib/select.ts`), and the **transfers list/create/edit
UI** (`app/(main)/transfers/page.tsx` shows the time, edits it via a
`type="time"` input, and passes it on create). Typecheck green.

> **Resolved during this verification:** the transfers **detail** page
> `app/(main)/transfers/[id]/page.tsx` previously read `LEDGER.transferGroups`
> mock data. It's now **DB-wired** via `selectTransfers` (matching the list
> page) — real amounts, derived locked rate, account names, notes, and the real
> `time` (shown in the chip and a `time` row). Verified at desktop + mobile with
> live transfers (same- and cross-currency).
>
> **Bug found + fixed during verification:** `createTransfer` 500'd on **every**
> transfer — its `transfer_groups` INSERT had dropped the `amount_base` column
> (a `NOT NULL`) during a `created_at/updated_at` refactor, so
> `SQLITE_CONSTRAINT_NOTNULL` fired before any leg was written. Restored the
> column (`mutations.ts` ~240). A production build can't catch this — it's a
> runtime SQL constraint, only surfaced by actually creating a transfer.

## 5. Open questions / things to verify

- **Desktop rendering.** The new Settings sub-screens use `ScreenHeader`, which
  is `md:hidden`; the body (`SettingsTabs` + the list) lives in page content, so
  it renders on desktop via `PageShell`. Confirm the desktop chrome looks right —
  this is the same `md:hidden` gotcha that hid the Budgets add button.
- **Half-migrated admin surface.** `/fx`, `/transfers`, `/categories`,
  `/merchants`, `/tags` still exist as standalone `(main)` routes inherited from
  the old `(ledger)` admin. This batch only retired `/system`. Decide whether the
  rest stay as deep links or also fold into Settings.
- **`/goals`** route still exists although goals were merged into budgets (see
  `budgets_redesign.md`) — unrelated cleanup, but lives next door.
- **Exchange rates editable only when hydrated** — intended? The SSR fallback
  shows rates read-only (no add/delete) until the store hydrates.
- **Devices is read-only** — no rename / "forget device". Confirm that's the
  intended scope for now.
- **Transfer validation lives server-side.** A same-currency Received amount that
  disagrees with Sent is rejected in the `createTransfer` mutation, not the form.
  Fine, but worth knowing where the guard is.

## 6. Downstream plan-doc updates (the reconciliation this enables)

- `MASTER_PLAN.md` — screen-status table: mark `/system` **retired**; Settings
  now hosts **Exchange rates** (Ledger tab) + a **Devices** tab; **transfer
  creation** is available from the Add sheet.
- `FX_CONVERSION_PLAN.md` / `MULTI_CURRENCY_ACCOUNTS_PLAN.md` — record the
  exchange-rate management UI's new home (Settings › Ledger) and the
  cross-currency transfer entry point (Received amount → locked rate).
- `CRUD_PARITY_PLAN.md` — transfer **create** and exchange-rate **add/delete**
  are now reachable from the consumer surface, not just admin.
- `database_design_en.md` — **no change** (no schema delta).

## 7. Acceptance

Checked = confirmed in committed code / typecheck; unchecked = still to verify.

- [x] `/system` route deleted; nothing links to it (command-palette, `/fx`).
- [x] Exchange rates add/delete wired under Settings › Ledger.
- [x] Devices list renders under Settings › Devices.
- [x] Add sheet has the transfer tab; same- and cross-currency paths call
  `createTransfer`.
- [x] `bun run typecheck` green on the working tree.
- [x] Transfer `time` round-trips through `/transfers` edit (follow-on §4) —
  create + list display + edit dialog all wired; typecheck green.
- [x] Desktop render of the new Settings sub-screens verified (§5) — Playwright
  screenshots at 1440px: Settings › Ledger (Exchange Rates) and Settings ›
  Devices both render with full PageShell chrome; the `md:hidden` `ScreenHeader`
  is correctly compensated by the desktop top bar. No layout breakage.
- [x] Lint + build green on the batch (`bun run lint`, `bun run build`).
- [x] `transfers/[id]` detail DB-wired (`selectTransfers`); verified desktop +
  mobile with live same- and cross-currency transfers.
- [x] Fixed `createTransfer` `amount_base` `NOT NULL` regression (`mutations.ts`);
  transfer creation now returns 200.
- [x] Downstream plan docs updated (§6) — `MASTER_PLAN.md`, `FX_CONVERSION_PLAN.md`,
  `MULTI_CURRENCY_ACCOUNTS_PLAN.md`, `CRUD_PARITY_PLAN.md`.
