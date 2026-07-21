# Income budgets: transaction-matched progress — design (DRAFT)

**Date:** 2026-07-21
**Status:** APPROVED — Option A (four JSON-array columns + chip pickers); Q2–Q6 decided per §9. Implementation plan: `2026-07-21-income-budget-transaction-matching-plan.md`.
**Scope:** Cross-repo — **web** (`frontend/lib/db/`, `frontend/lib/select.ts`, `frontend/components/`) **and native** (`FinchCore`, `FinchApp`). Schema-migrating. This is the "Deliverable 2" follow-on to the native-only income-budget form redesign (PR #557); it changes the *data model*, so it cannot be native-only.

---

## 1. Problem

In this app an **income budget is a savings goal**. Today its progress is a **manual `saved` counter** moved only by a **Contribute** action (`saved = MAX(0, saved + amount)`) — it has **no transaction behind it**, which is inconsistent with a double-entry ledger where every dollar is a real posting. The user's progress can silently drift from reality.

We want a goal's progress to be **derived from real transactions**, matched by **account + category + tags + merchants**, and to **remove Contribute**.

### Current state (verified)

**Web** — `budgets` DDL `frontend/lib/db/core/schema.ts:183-210`; matching `frontend/lib/select.ts:1417-1457`. **Native** — mirror in `FinchCore/Storage/Schema.swift` + `FinchCore/Selectors/Selectors.swift`. Both at `SCHEMA_VERSION = 2026-07-20T00:00:00Z`.

- Budget matching filters transactions on **`account_ids` + `category_ids` only** (recursive categories, splits-aware). **Transfers, adjustments, pending are excluded.** No tag/merchant matching.
- **One-shot income goal** (`kind=income`, `is_recurring=0`): `used = budget.saved` — bypasses transactions entirely. **Recurring** income (`is_recurring=1`) already sums matching positive inflows over the cycle.
- `saved` is **not** in the `updateBudget` patch allowlist on either side; it moves only via `contributeBudget` (no sign check → negative deltas subtract, floored at 0).
- **`budgets.tag_ids` was declared then dropped** (migration `2026-06-06`) because "never read by any selector." Precedent: only add match columns the selector actually reads.
- A **Rules engine already matches every dimension we want** — `frontend/lib/rules/` (`Leaf` union in `types.ts:15-33`, `evaluateLeaf` in `engine.ts:52-120`) supports `tag_id` (has/has_any/has_all), `counterparty_id`, `merchant`, `category_id`, `account_id`, amount, kind, … Native parallel in `FinchCore/Rules/`. **This is the reuse precedent.**

---

## 2. Decision (direction)

Turn a one-shot income goal's progress into **`saved` (a starting offset) + the sum of real matched inflows** over the goal window, where "matched" spans **account · category · tags · merchants**. Remove the Contribute UI; fund goals with real transactions. Keep `saved` as an explicit **pre-tracking starting amount** (the "Saved so far" field shipped in #557), so **no existing goal loses progress**.

---

## 3. Matching model

**Dimensions:** `account_ids`, `category_ids` (existing) **+ new** `tag_ids`, `counterparty_ids`.

**Semantics** (consistent with today's account∧category rule):
- **AND across dimensions**, **OR within a dimension**, **empty set = unconstrained.**
  A transaction matches iff: `(account_ids empty ∨ t.account ∈ account_ids)` ∧ `(category_ids empty ∨ t.category ∈ category_ids, recursive/splits-aware)` ∧ `(tag_ids empty ∨ t.tags ∩ tag_ids ≠ ∅)` ∧ `(counterparty_ids empty ∨ t.counterpartyId ∈ counterparty_ids)`.
- A goal with **all four empty** matches nothing meaningful → require **at least one dimension set** for an income goal (validation), otherwise it silently counts *all* income.

**Inflow definition (income goals):** count **positive inflows** in the window — income postings **and incoming transfer legs** (the credit side landing in a matched account). This means **dropping the transfer-exclusion for income-type budgets** so an account-linked goal funded by a transfer actually registers. (Expense budgets keep excluding transfers, unchanged.) Adjustments and pending stay excluded.

**Window:** one-shot goal → single window `[start_date, end_date ?? today]`. `is_recurring` stays `0`.

**Progress:** `used = saved + Σ matched_inflows(window)`. `saved` = money saved **before** ledger tracking began (the offset). Existing goals: `saved` preserved, matched inflows begin accumulating on top. Target = `amount`; `pct = used / amount`.

> **Double-count caution (UX):** if a user sets `saved` *and* the same money also appears as matched transactions, it counts twice. `saved` is documented/labelled as "already saved before tracking" (pre-tracking baseline). See §9-Q3.

---

## 4. Architecture — two options for storage + matching

### Option A (recommended): four JSON-array columns + extend the budget matcher
- Add `tag_ids TEXT`, `counterparty_ids TEXT` to `budgets` (JSON string arrays, exactly like `account_ids`/`category_ids`).
- Extend the budget matcher (`select.ts:budgetProgress`/`matchedAmount` and `FinchCore/Selectors.usedInWindow`) with the two new AND-clauses, borrowing the **predicate logic** from the Rules engine (`tag_id has_any`, `counterparty_id is`) so we don't reinvent it.
- **UI:** the budget form gets two more chip-multiselects (Tags, Merchants) beside the existing Categories/Accounts — no new interaction paradigm.
- **Pros:** consistent with the existing column idiom + simple chip UX; smallest conceptual change; the selector clearly "reads" the columns (avoids the reason `tag_ids` was dropped before). **Cons:** four parallel columns; fixed dimension set.

### Option B (alternative): store a Rules `Condition`, evaluate via the Rules engine
- Add one `match_condition TEXT` (JSON `Condition` tree) column; budget matching calls `evaluateLeaf`/`evaluate` from `lib/rules` (web) + `FinchCore/Rules` (native).
- **UI:** either compile the four chip-pickers into a `Condition` on save (simple UX, powerful storage) or expose a full condition builder (heavy).
- **Pros:** reuses the tested engine wholesale; future-proof to any predicate (amount, note, day-of-week…). **Cons:** bigger conceptual shift; `account_ids`/`category_ids` columns become redundant/awkward alongside a condition; heavier if a full builder is exposed.

**Recommendation:** **Option A** for scope and consistency (chip UX unchanged, minimal new surface), reusing the Rules engine's *predicate helpers* rather than its storage. Option B is the better long-term architecture if we later want rich per-budget rules — flagged for your call (§9-Q1).

---

## 5. Schema & migration (both repos, lockstep)

1. **DDL:** add `tag_ids TEXT`, `counterparty_ids TEXT` to `budgets` in `frontend/lib/db/core/schema.ts` **and** byte-for-byte in `FinchCore/Storage/Schema.swift`.
2. **`SCHEMA_VERSION`** bump (e.g. `2026-07-2x…`) in `schema.ts` and `Schema.version` in Swift (they must stay equal).
3. **Migration** entry in the web `MIGRATIONS` map (`ALTER TABLE budgets ADD COLUMN tag_ids TEXT; ADD COLUMN counterparty_ids TEXT;`) and the native `Migrations.swift` equivalent. Existing rows get `NULL` (= unconstrained) — safe.
4. **Regenerate parity fixtures** (`cd frontend && bun scripts/export-fixtures.ts`) and re-run the four `ParityTests` gates. (Heed the `ios/README.md` gotchas: keep only `writeparity/sequence.json` when changing `WRITE_SEQUENCE`; no wall-clock-dated actions.)

_(Option B: one `match_condition TEXT` column instead of two.)_

---

## 6. Mutations & selectors

**Web (`frontend/lib/db/queries/budgets.ts`, `domain/budgets/mutations.ts`, `_args.ts`; `frontend/lib/select.ts`) + Native (`FinchCore/Store/Domain/Budgets.swift`, `Selectors.swift`) — mirrored:**

- `createBudget`/`updateBudget`: accept + patch `tagIds`, `counterpartyIds` (add to `BUDGET_PATCH_COLUMNS` and the create insert). Also **add `saved` to the patch allowlist** so the form can set the starting offset directly (see §9-Q4).
- `budgetProgress`: change the `oneShotIncome` branch from `used = saved` to `used = saved + usedInWindow(...)`, and extend `usedInWindow`/`matchedAmount` with the tag + counterparty AND-clauses and the income-type transfer inclusion.
- **Remove `contributeBudget`** (action, query, client store mirror) — or keep it deprecated (§9-Q4).
- The budget-detail "matched transactions" list (web `budgets/[id]/page.tsx`, native `BudgetDetailView`) now shows the real matched inflows for a goal (no longer "Tracked via contributions").

---

## 7. UI changes

**Native (`FinchApp`):** the #557 income form gains **Tags** + **Merchants** chip-multiselects (reuse `MultiSelectPickerRow`; a merchants picker over `store.counterparties`) alongside a re-introduced **Account/Category** scope for goals. "Saved so far" stays as the offset. **Remove** `ContributeSheet`, the detail "Contribute…" button, and the row Contribute swipe. Detail page shows matched inflows + Target date.

**Web (`frontend/components/budget-form-dialog.tsx`, `budgets/[id]/page.tsx`):** same — add Tags/Merchants multiselects for income; remove the Contribute button + dialog.

**Copy:** income goals keep the "Income" label (per #557); progress reads "$X of $Y" from real transactions.

---

## 8. Testing & parity

- **Parity gates** (`FinchCore/Tests/ParityTests`) must stay green after fixture regen: selectors, audit, projection, write round-trip.
- **New unit tests** (both `lib/select.test.ts` and `FinchCoreTests`): AND-across/OR-within matching; empty-dimension = unconstrained; income transfer-leg inclusion; `saved`-offset + inflows sum; migration read-path (NULL columns).
- **Build gate:** web `bun run build`/`typecheck`/`test`; native FinchApp (iOS) + FinchMac + `swift test`.
- **Migration test:** an existing goal (`saved=650`, no match columns) reads back as `650 + 0` and doesn't reset.

---

## 9. Decisions (resolved)

- **Q1 — Storage architecture: ✅ DECIDED → Option A** (four columns + chip pickers). Option B (one `match_condition`, reuse Rules engine end-to-end) recorded as the future path if per-budget rules are wanted later.
- **Q2 — Transfer inflows: ✅ YES.** Income goals **count incoming transfer legs** — drop the transfer-exclusion for income-type budgets only (expense budgets unchanged).
- **Q3 — `saved` as offset: ✅ KEEP AS OFFSET.** `saved` is an explicit "already saved before tracking" starting amount added on top of matched inflows; existing goals keep their progress. #557's "Saved so far" field sets it.
- **Q4 — `saved` write path + Contribute: ✅ ADD `saved` TO ALLOWLIST, REMOVE `contributeBudget`.** The form sets the offset directly; the Contribute action + UI are removed entirely.
- **Q5 — Require ≥1 dimension: ✅ YES.** An income goal must set at least one of account/category/tag/merchant, else it would count *all* income.
- **Q6 — Recurring income budgets: ✅ OUT OF SCOPE.** The latent `is_recurring=1` income path stays as-is (already transaction-tracked).

## 10. Phasing (for the eventual plan)

1. **Web schema + migration + selector + mutations** (source of truth), with unit tests.
2. **Regenerate parity fixtures**; mirror schema/selector/mutations in `FinchCore`; green parity gates.
3. **Web UI** (form pickers, remove Contribute).
4. **Native UI** (`BudgetSheet` pickers, remove `ContributeSheet`/button/swipe, detail matched list).
5. **Migration verification** on a DB with existing goals.

Each phase ends green (build + tests) on its repo before the next.
