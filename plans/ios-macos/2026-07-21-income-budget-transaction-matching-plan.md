# Income budgets: transaction-matched progress — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development (or executing-plans) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. **Design doc:** `2026-07-21-income-budget-transaction-matching-design.md` (Option A, decisions §9).

**Goal:** Make a one-shot income budget (savings goal) track progress from **real transactions** matched by **account + category + tags + merchants**, keep `saved` as a starting offset, and remove Contribute.

**Architecture:** Web (`frontend/lib/db/`, `frontend/lib/select.ts`, `frontend/components/`) is the source of truth; `FinchCore` mirrors it byte-for-byte and is parity-gated. Add two JSON-array columns (`tag_ids`, `counterparty_ids`) to `budgets`; extend the budget matcher with two AND-clauses + income transfer-leg inclusion; change the one-shot-income progress from `saved` to `saved + matched inflows`; add `saved` to the update allowlist; delete `contributeBudget` + its UI.

**Tech stack:** TypeScript + `bun:sqlite`/`better-sqlite3` (web); Swift + GRDB (`FinchCore`); SwiftUI (`FinchApp`). Parity via `frontend/scripts/export-fixtures.ts` → `FinchCore/Tests/ParityTests`.

## Global Constraints

- **`SCHEMA_VERSION` must be identical** on both sides: `frontend/lib/db/core/schema.ts` (`SCHEMA_VERSION`, currently `2026-07-20T00:00:00Z`) and `FinchCore/Storage/Schema.swift` (`Schema.version`). Bump both to the **same** new ISO value.
- **The web `budgets` DDL and the native `Schema.swift` budgets DDL must stay byte-for-byte identical.**
- **Matching semantics:** AND across dimensions, OR within, **empty set = unconstrained**. Income goals additionally **include incoming transfer legs**; expense budgets are unchanged (still exclude transfers).
- **`saved` is a starting offset**, not replaced: one-shot income progress = `saved + Σ matched inflows`.
- **Validation:** an income goal must have ≥1 of account/category/tag/merchant set.
- **No `contributeBudget`** after this change — action, query, client mirror, and both UIs removed.
- **Parity gates must be green** (`cd ios && swift test`) after regenerating fixtures; heed `ios/README.md` fixture gotchas (keep only `writeparity/sequence.json` on `WRITE_SEQUENCE` change; no wall-clock-dated actions).
- Each task ends green on its repo (web: `bun run typecheck && bun run build && bun test lib`; native: `swift build && swift test`, plus FinchApp/FinchMac Xcode builds for UI tasks).

---

## Phase 1 — Web schema + migration

### Task 1: Add `tag_ids` + `counterparty_ids` columns and bump `SCHEMA_VERSION`

**Files:**
- Modify: `frontend/lib/db/core/schema.ts` (budgets DDL `:183-210`; `SCHEMA_VERSION` `:436`; `MIGRATIONS` map `:442-623`)
- Test: `frontend/lib/db/migrate.test.ts`, `frontend/lib/db/probe.test.ts`

**Interfaces — Produces:** `budgets.tag_ids TEXT`, `budgets.counterparty_ids TEXT` (JSON string arrays, NULL = unconstrained); new `SCHEMA_VERSION`.

- [ ] **Step 1:** In the budgets `CREATE TABLE` (after `category_ids TEXT,` at `:~198`) add:
  ```sql
  tag_ids            TEXT,
  counterparty_ids   TEXT,
  ```
- [ ] **Step 2:** Bump `SCHEMA_VERSION` to a new ISO (e.g. `'2026-07-21T00:00:00Z'`). Keep the exact value; Task 9 sets Swift to the same string.
- [ ] **Step 3:** Add a `MIGRATIONS` entry keyed by the new version:
  ```ts
  '2026-07-21T00:00:00Z': [
    'ALTER TABLE budgets ADD COLUMN tag_ids TEXT',
    'ALTER TABLE budgets ADD COLUMN counterparty_ids TEXT',
  ],
  ```
- [ ] **Step 4:** Run `bun test lib/db/migrate.test.ts lib/db/probe.test.ts` — a fresh DB applies the full schema; an old DB migrates. Expected: PASS (update the version assertion `n` if the tests pin it).
- [ ] **Step 5:** Commit: `feat(web): budgets.tag_ids + counterparty_ids columns (schema vNEXT)`.

### Task 2: Accept the new columns in create/update mutations (+ `saved` patchable)

**Files:**
- Modify: `frontend/lib/db/domain/_args.ts` (`:88-117` budget arg map), `frontend/lib/db/queries/budgets.ts` (create insert `:64-90`; `BUDGET_PATCH_COLUMNS` `:92-106`; `contributeBudget` `:175-180` — deletion in Task 4), `frontend/lib/db/domain/budgets/mutations.ts` (`createBudget` `:30-56`)
- Test: `frontend/lib/db/mutate.test.ts`

**Interfaces — Consumes:** columns from Task 1. **Produces:** `createBudget`/`updateBudget` accept `tagIds`, `counterpartyIds`, and `saved` (patchable).

- [ ] **Step 1:** Add `tagIds?: string[]`, `counterpartyIds?: string[]` to the budget arg types in `_args.ts`; thread into the create insert in `queries/budgets.ts` (serialize via the same JSON idiom as `account_ids`, i.e. `JSON.stringify(ids)` or the existing helper).
- [ ] **Step 2:** In `BUDGET_PATCH_COLUMNS` add: `tagIds:'tag_ids', counterpartyIds:'counterparty_ids', saved:'saved',`.
- [ ] **Step 3:** Write a `mutate.test.ts` case: `createBudget` with `type:'income', tagIds:['t1'], counterpartyIds:['c1'], saved:100` round-trips; `updateBudget` patches `saved` and `tagIds`.
- [ ] **Step 4:** Run `bun test lib/db/mutate.test.ts` → PASS.
- [ ] **Step 5:** Commit: `feat(web): budgets accept tagIds/counterpartyIds; saved patchable`.

---

## Phase 2 — Web matching + progress

### Task 3: Extend `budgetProgress` matching (tags, merchants, income offset+inflows, transfer legs)

**Files:**
- Modify: `frontend/lib/select.ts` (`matchedAmount` `:1396-1404`, `budgetProgress` `:1417-1457`)
- Test: `frontend/lib/select.test.ts`

**Interfaces — Consumes:** the new columns. **Produces:** income-goal `used = saved + Σ matched inflows`; matching adds tag + counterparty AND-clauses; income budgets include incoming transfer legs.

- [ ] **Step 1: Write failing tests** in `select.test.ts`:
  - A `type:'income', isRecurring:0, saved:50, categoryIds:['salary']` budget with two matching income txns (30, 20) → `used === 100` (50 + 30 + 20).
  - `tagIds:['t1']` matches only txns whose `tags` include `t1` (OR within, AND with other dims).
  - `counterpartyIds:['c1']` matches only txns with that counterparty; empty = unconstrained.
  - An **incoming transfer leg** into a matched account counts for an income goal (positive amount) but a transfer is still excluded for an expense budget.
  - `≥1 dimension` guard is enforced at the mutation layer (Task 2), so `budgetProgress` may assume dimensions; a fully-empty income goal counting all income is acceptable at the selector level.
- [ ] **Step 2:** Run the new tests → FAIL.
- [ ] **Step 3: Implement.** In the transaction loop:
  - Replace the blanket `kindOf(t) === 'transfer'` skip with: skip transfers **only for expense budgets** (`budget.type === 'expense'`). Keep excluding `adjustment` and `pending` for both.
  - After the account filter, add:
    ```ts
    if (tagSet && !(t.tags ?? []).some(x => tagSet.has(x))) continue;
    if (cpSet && (t.counterpartyId == null || !cpSet.has(t.counterpartyId))) continue;
    ```
    where `tagSet`/`cpSet` are `budget.tagIds?.length ? new Set(budget.tagIds) : null` etc. (mirror the existing `accountSet` pattern).
  - Change the `oneShotIncome` branch from `used = budget.saved` to `used = budget.saved`, then **fall through into the same matched-inflow loop** so `used` accumulates on top (i.e. seed `used = saved` for one-shot income, then add matched inflows; recurring income still starts `used = 0`).
- [ ] **Step 4:** Run `bun test lib/select.test.ts` → PASS.
- [ ] **Step 5:** Update the budget-detail matched-transaction list (`frontend/app/(main)/budgets/[id]/page.tsx:70-76`) to use the same expanded filter (tags + counterparty + income transfer legs) so the displayed list matches the computed progress.
- [ ] **Step 6:** Commit: `feat(web): budget matching by tags/merchants; income goals sum real inflows + offset`.

---

## Phase 3 — Web: remove Contribute

### Task 4: Delete `contributeBudget` (action, query, client mirror) and its UI

**Files:**
- Modify/Delete: `frontend/lib/db/domain/budgets/mutations.ts` (`:85-89`), `frontend/lib/db/queries/budgets.ts` (`:175-180`), `frontend/lib/store/budgets/actions.ts` (`:134-139`), `frontend/app/(main)/budgets/[id]/page.tsx` (`oneShot` `:56`, contribute button `:163-167`, dialog `:220-236`, `submitContribution` `:84-93`), `frontend/lib/db/domain/_args.ts` (contribute arg `:112`)
- Test: `frontend/lib/db/mutate.test.ts` (remove contribute cases)

- [ ] **Step 1:** Remove the `contributeBudget` handler, query, client action, and any action-name registration. Grep `contributeBudget` repo-wide → zero non-test references.
- [ ] **Step 2:** Remove the Contribute button + dialog + `submitContribution` from the budget detail page; the "saved" is now shown from progress, edited via the form's "Saved so far" (Task 5).
- [ ] **Step 3:** Run `bun run typecheck && bun test lib` → PASS (no dangling references).
- [ ] **Step 4:** Commit: `feat(web): remove Contribute; goal progress is transaction-derived`.

### Task 5: Web budget form — Tags + Merchants pickers for income; "Saved so far"

**Files:**
- Modify: `frontend/components/budget-form-dialog.tsx` (income branch: type toggle `:262-279`, fields `:288-365`, submit `:231-243`)

- [ ] **Step 1:** For `type === 'income'`: drop Frequency/Start/Rollover from the form (they're inert), keep **Categories + Accounts**, add **Tags** + **Merchants** chip-multiselects (reuse the existing chip-multiselect components; merchants source = counterparties). Add a **"Saved so far"** number field bound to `saved`.
- [ ] **Step 2:** Enforce the **≥1 dimension** guard on submit for income (disable Save / show a hint if all four are empty).
- [ ] **Step 3:** Submit maps `tagIds`, `counterpartyIds`, `saved` into the create/update input; income still sends `isRecurring:0`.
- [ ] **Step 4:** `bun run build` → PASS. Manual: create an income goal with a tag + merchant, confirm progress reflects matching txns.
- [ ] **Step 5:** Commit: `feat(web): income budget form — tags/merchants scope + saved-so-far`.

---

## Phase 4 — Parity: regenerate fixtures, mirror in FinchCore

### Task 6: Regenerate parity fixtures

**Files:** run `cd frontend && bun scripts/export-fixtures.ts`; outputs under `ios/FinchCore/Tests/ParityTests/Fixtures/…`

- [ ] **Step 1:** Regenerate. **Revert** any fixture that changed only by `datetime('now')` noise; keep only `writeparity/sequence.json` if `WRITE_SEQUENCE` changed (per `ios/README.md`). Do **not** add wall-clock-dated actions.
- [ ] **Step 2:** Commit: `chore(ios): regenerate parity fixtures for budgets vNEXT`.

### Task 7: Mirror schema + migration in `FinchCore`

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Storage/Schema.swift` (budgets DDL + `Schema.version`), `ios/FinchCore/Sources/FinchCore/Storage/Migrations.swift`
- Test: `ios/FinchCore/Tests/FinchCoreTests` (schema/migration)

- [ ] **Step 1:** Add the two columns to the budgets DDL **byte-for-byte** matching the web string; set `Schema.version` to the **same** new ISO as `SCHEMA_VERSION`.
- [ ] **Step 2:** Add the `ALTER TABLE budgets ADD COLUMN …` migration mirroring the web entry.
- [ ] **Step 3:** `cd ios && swift build && swift test` → the schema/migration + projection parity gates pass.
- [ ] **Step 4:** Commit: `feat(ios): mirror budgets tag_ids/counterparty_ids schema + migration`.

### Task 8: Mirror mutations + matching in `FinchCore`

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Domain/Budgets.swift` (create `~:60-90`; `cols` map `:92-96` — add `tagIds`/`counterpartyIds`/`saved`; delete `contribute` `:159-164`), `ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift` (`usedInWindow` `:338-350`, `budgetProgress` `:355-371`), `ios/FinchCore/Sources/FinchCore/Store/ActionName.swift` (remove `.contributeBudget`)
- Test: `ios/FinchCore/Tests/FinchCoreTests`

**Interfaces — Consumes:** Task 3's semantics (must match exactly for parity).

- [ ] **Step 1:** Add `tagIds`/`counterpartyIds`/`saved` to the `cols` patch map and the create insert. Remove the `contribute` handler + `.contributeBudget` action.
- [ ] **Step 2:** In `usedInWindow`: skip transfers only for expense; add the tag (`t.tags`) and counterparty (`t.counterpartyId`) AND-clauses mirroring the web.
- [ ] **Step 3:** In `budgetProgress`: for one-shot income, seed `used = budget.saved` then add `usedInWindow(...)` (don't early-return `saved`).
- [ ] **Step 4:** Port the Task-3 unit tests into `FinchCoreTests`. `swift test` → all gates + new tests PASS (the write round-trip + selector parity confirm byte-for-byte agreement with the regenerated fixtures).
- [ ] **Step 5:** Commit: `feat(ios): FinchCore budget matching by tags/merchants; income offset+inflows; drop contribute`.

---

## Phase 5 — Native UI

### Task 9: `BudgetSheet` income path — Tags/Merchants pickers; remove Contribute UI

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetSheet.swift` (income `incomeFields` + `saveIncome` from #557), `ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetDetailView.swift` (remove `ContributeSheet` + "Contribute…" button; income section shows matched inflows + Target date), `ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift` (remove the Contribute leading-swipe `:371-375` + `contributeFor` state)

- [ ] **Step 1:** In `incomeFields`, add **Categories** (`CategoryMultiPickerRow`), **Accounts**, **Tags**, **Merchants** (`MultiSelectPickerRow` over `store.counterparties`) chip pickers; keep Name/Target/Saved so far/Target date/Group. `saveIncome` sends `categoryIds`/`accountIds`/`tagIds`/`counterpartyIds`/`saved` (now `saved` is patchable → no contribute delta), and enforces ≥1 dimension.
- [ ] **Step 2:** Delete `ContributeSheet` (in `BudgetDetailView.swift`), the detail "Contribute…" button, and the `BudgetsTab` Contribute swipe + `contributeFor`. Grep `contributeBudget`/`ContributeSheet` in `FinchApp` → zero references.
- [ ] **Step 3:** `xcodegen generate` (if files added), build **FinchApp (iOS)** + **FinchMac** → both `BUILD SUCCEEDED`.
- [ ] **Step 4:** Sim-verify: create an income goal scoped to a tag + merchant; add a matching transaction; the goal's progress increases from real transactions; no Contribute affordance remains.
- [ ] **Step 5:** Commit: `feat(ios): income budget form scopes by category/account/tag/merchant; remove Contribute UI`.

### Task 10: Migration verification (existing goals)

- [ ] **Step 1:** On a DB with a pre-existing goal (`saved=650`, NULL match columns), confirm after migration the goal reads `used = 650 + matched inflows` (matched = 0 until scoped) — **progress preserved, no reset**.
- [ ] **Step 2:** Confirm setting a scope + adding matching transactions increases progress above 650.
- [ ] **Step 3:** No commit (verification), or a test fixture if one is added.

---

## Notes / risks

- **`Tx` field names:** confirm the projected transaction exposes `tags: [String]` and a counterparty id (`counterpartyId`) on both sides before writing the match clauses (Task 3/8) — adjust names to the actual model.
- **Double-count (design §3):** "Saved so far" is a pre-tracking offset; the form copy must say so to avoid users entering `saved` *and* also having matching transactions for the same money.
- **`≥1 dimension` guard** lives in the UI + mutation layer, not the selector, so old data / imports without a scope degrade gracefully (count all income) rather than erroring.
- **i18n:** new strings (Tags, Merchants, Saved so far) go through the generated `Localizable.xcstrings` pipeline (English fallback until regenerated).
