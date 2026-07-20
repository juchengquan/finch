# Phase 2 — Global merchants — Implementation Plan

> **For agentic workers:** this is a **cross-platform schema migration** with a strict order. Do NOT hand-edit iOS DDL/fixtures — they are regenerated from the web. Read the whole plan before starting; the tasks are tightly coupled.

**Goal:** Make merchants (counterparties) **global** — one catalog shared across ledgers — by dropping `counterparties.ledger_id`. Pre-launch, so **no data migration**: change the baseline schema + stamp a fresh version.

**Reference:** design `plans/ios-macos/2026-07-19-global-merchants-phase2-design.md`; roadmap `…-ledger-reference-model-roadmap.md`.

## Decisions (locked)
- **Names non-unique globally** — replace `idx_counterparty_ledger_name` with a plain `(name)` index (keep NOCASE); dedup is user-driven via Merge. `resolveCounterpartyIdByName` picks the first match.
- **Remove `Counterparty.ledgerId`** (model + init + the one projection construction + test helpers).
- **Deleting a ledger no longer deletes merchants** (drop the FK `ON DELETE CASCADE` and the manual `DELETE FROM counterparties` in `deleteLedger`, both platforms).
- **Counts/detail stay active-ledger-scoped** — the selectors already scope by the *transaction's* ledger; **no selector change**.
- **Fresh baseline version** — bump `SCHEMA_VERSION` on the web; iOS mirrors it (byte-copied) + the two test literals follow. (Value: a new timestamp, e.g. `2026-07-20T00:00:00Z`, or `0.1` — pick one, keep both platforms identical.)

## Global Constraints
- **Order is forced:** Web `lib/db` + `SCHEMA_VERSION` → regenerate fixtures (`bun scripts/export-fixtures.ts`) → iOS re-emit `Schema.ddl` + version + Swift logic → iOS UI → verify. iOS will NOT compile/parity-pass until its Swift logic matches the new schema, so Tasks 2a/2b land together.
- **Parity net stays intact:** the web DB layer MUST move in lockstep (fixtures generate from it); the web **UI can lag** (leave `app/`/`components/`/`lib/store` per-ledger reads for a follow-up, listed in §Web-UI-followup).
- Commits: conventional prefixes, **no `Co-Authored-By`**. iOS builds from `ios/` with `DEVELOPER_DIR`; don't stage `.xcodeproj`. Web tests: `cd frontend && bun test`.

---

### Task 1 — Web lockstep (`frontend/`): drop `ledger_id`, bump version, regen fixtures

**MUST-change files (parity oracle).** Exact sites from the footprint map:

- **`lib/db/core/schema.ts`**: drop `counterparties.ledger_id` (line ~172) + the FK; drop `idx_counterparty_ledger` (~376); change `idx_counterparty_ledger_name` (~380) → `CREATE INDEX idx_counterparty_name ON counterparties(name);`; **bump `SCHEMA_VERSION`** (~437) to the chosen fresh value.
- **`lib/db/domain/counterparties/{types,mutations}.ts`**: drop `ledgerId` from `Counterparty` + `NewCounterparty` (types:8,15); drop it from the `createCounterparty` insert payload (mutations:24). `_args.ts` inherits via `NewCounterparty`.
- **`lib/db/queries/counterparties.ts`** (all 5 fns): `rowToCp` drop `ledgerId` (:11); `listCounterparties` → global `ORDER BY name`, drop `ledgerId?` (:18-24); `searchCounterparties` drop ledger predicate/param (:29-36); `createCounterparty` drop `ledger_id` col/bind (:48-53); **`resolveCounterpartyIdByName`** drop `WHERE ledger_id = ?` + the `ledgerId` param (:79-94) — the hot resolver.
- **`lib/db/queries/transactions.ts`**: remove the cross-ledger counterparty guard (:311-319); drop `AND ledger_id = ?` in pending-resolve (:632); drop `ledger_id` col/bind in the auto-create insert (:644).
- **`lib/db/queries/ledgers.ts`**: remove `DELETE FROM counterparties WHERE ledger_id = ?` (:135) from `deleteLedger`.
- **`lib/db/core/seed.ts`**: drop `ledger_id` col/bind in the counterparty insert (:128-132); drop the `ledgerId` arg at the two `resolveCounterpartyIdByName` calls (:317,:373).
- **Resolver-signature callers** (drop the ledger arg): `core/entries.ts:276`, `domain/rules/mutations.ts:89`, `domain/scheduled/mutations.ts:178`.
- **`scripts/export-fixtures.ts`**: drop `ledgerId` from the `WRITE_SEQUENCE` `createCounterparty` arg (:427); drop the `ledger_id` key from the projection extractor (:389).
- **Web tests** (update — remove `ledger_id`/`ledgerId`): `mutate.test.ts:320`, `entries.test.ts:413`, `domain/ledgers/mutations.test.ts:252`, `domain/transactions/mutations.test.ts:189`, `domain/counterparties/mutations.test.ts:22,29`.

- [ ] **Step 1** — make all the web edits above.
- [ ] **Step 2** — `cd frontend && bun test lib` → web unit tests pass (adjust any missed `ledger_id` reference).
- [ ] **Step 3** — `cd frontend && bun scripts/export-fixtures.ts` → regenerates `ios/FinchCore/Tests/ParityTests/Fixtures/**` (`writeparity/sequence.json`, `projection/projection.sqlite3`, `audit/*.sqlite3`). Per `ios/README.md`, **keep only the semantically-changed fixtures**; revert any that changed solely by `datetime('now')` noise. The counterparty-shape change is real, so `sequence.json` + the `.sqlite3` files legitimately change.
- [ ] **Step 4** — commit: web changes + regenerated fixtures together. `feat: global merchants — drop counterparties.ledger_id (schema v<new>) + regen fixtures`.

---

### Task 2 — iOS lockstep (`FinchCore`): schema mirror + Swift logic + tests

The iOS package won't compile against the regenerated fixtures until schema + logic match. Do it as one task; `swift test` is the gate.

- **DDL (re-emit, don't invent):** update `Storage/Schema.swift` `counterparties` CREATE TABLE (drop `ledger_id`, :135) + indexes (:509-513 → the new `(name)` index), matching the web `schema.ts` **byte-for-byte**; bump `Schema.version` (:12) to the same fresh value. Update the two version literals: `SchemaTests.swift:10`, `GroupColorTests.swift:63-64`.
- **Model:** `Project/Counterparty.swift` — remove `ledgerId` (field :8 + init :12-13). Fix the one construction `Projections+State.swift:161` and any test helper (`CounterpartyTxCountsTests.swift:6`, and grep for other `Counterparty(…ledgerId:` constructions).
- **Projection:** `Projections+State.swift:154-165` `counterparties(dbQueue:ledgerId:)` → drop `WHERE ledger_id = ?` (global fetch), drop `ledger_id AS ledgerId`, drop the `ledgerId` param; update the FinchApp caller (`FinchStore` projection wiring) accordingly.
- **Domain:** `Store/Domain/Counterparties.swift` — `createCounterparty` drop `ledger_id` col/arg (:16-22); `validateMerge` remove the same-ledger guard (:81-87), reduce to not-self + both-exist (the `error.counterparty.mergeLedger` key becomes unreachable — remove its use).
- **Resolver + writers:** `Store/Entries.swift:196-200` `resolveCounterpartyIdByName` drop `ledger_id = ? AND` + the `ledgerId` param; fix callers `Entries.swift:333`, `Transactions.swift:337`, `Rules.swift:79`. `Transactions.swift`: confirm-pending drop `AND ledger_id = ?` (:175) + drop `ledger_id` in the auto-insert (:181-182); **remove the addTransaction cross-ledger guard** (:224-229).
- **Ledger delete:** `Store/Domain/Ledgers.swift:127` — remove `DELETE FROM counterparties WHERE ledger_id = ?`.
- **Tests:** update any `WriteParityTests` snapshot column list (`:107-108` drops `ledger_id`) — but note the fixtures themselves are regenerated in Task 1; adjust the Swift snapshot extractor to match. Add/adjust a Swift unit test: merging two merchants that were "in different ledgers" (now just two global rows) succeeds; a merchant survives `deleteLedger`.

- [ ] **Step 1** — schema + version + literals.
- [ ] **Step 2** — model + projection + domain + resolver + writers + ledger-delete edits.
- [ ] **Step 3** — `cd ios && swift test` → **all pass**, including regenerated `ParityTests` (Projection/Audit/Write) and `CounterpartyMergeTests`/`CounterpartyTxCountsTests` (update the latter's `ledgerId:` helper). This is the real gate: parity green proves the iOS schema/logic matches the web oracle.
- [ ] **Step 4** — commit.

---

### Task 3 — iOS UI

- `MerchantsView` / `CounterpartyDetailView`: now fed the **global** `store.merchants` (no longer re-projected on ledger switch). Confirm nothing assumes per-ledger; the count pill + detail stay active-ledger (selectors unchanged). Merge picker spans the global list.
- **Settings placement:** Merchants no longer belongs under the "Ledger" group (it's global now). Move the `MerchantsView()` row out of `SettingsRootList`'s "Ledger" section — recommend into "General" or its own row. (Small; can be its own commit.)
- [ ] Build gate (iOS) → **BUILD SUCCEEDED**; commit.

---

### Task 4 — Verification + i18n
- [ ] `cd ios && swift test` full green; **iOS + macOS** both **BUILD SUCCEEDED**; `cd frontend && bun test lib` green.
- [ ] i18n: minimal — only if the Settings move / any new string appears (surgical zh-Hans as before).
- [ ] Manual sim: merchants list is identical across ledger switches; merge spans all; deleting a ledger keeps merchants.

## Risks
- **`resolveCounterpartyIdByName` runs on every write** — global scoping means a name now resolves to one global row; with two pre-existing same-named rows it picks the first (non-unique by decision). Pre-launch, no live dup data. 
- **Fixtures must regenerate from the web** — never hand-edit the iOS `.sqlite3`/`sequence.json`; a hand-edit will drift from canonical and fail parity subtly.
- **Pack/DownSync tolerance** — a web-exported pack carrying the old `ledger_id` column vs the new columnset: verify import tolerates the missing/extra column (the group-color migration is the established tolerant-reader precedent). Add a note/test if needed.

## Web-UI follow-up (can lag; out of this PR's critical path)
`app/(main)/merchants/page.tsx:100` · `components/rule-builder-dialog.tsx:200` · `lib/store/ledgers/actions.ts:77` (the `c.ledgerId ===` filters) and the `createCounterparty({ ledgerId })` call sites (`add-expense-form.tsx:392`, `edit-transaction-form.tsx:189`, `lib/store/counterparties/actions.ts`). Track as a web-side cleanup.
