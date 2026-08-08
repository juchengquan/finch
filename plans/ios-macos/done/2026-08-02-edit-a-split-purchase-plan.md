# Splitting a Purchase: Two-Step Entry, Grids, and Groups (iOS)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adding or editing a transaction becomes two steps — first *what* is involved, then *how much* each gets. A purchase split across accounts becomes correctable, which it is not today.

**Scope: iOS/Swift.** The web mirror is deliberately out of scope for now, **except** where a shared artefact would silently diverge — the parity oracle's snapshot and the projection field it compares (see Task 2). Those are called out explicitly.

**Architecture:** Two shapes, one rule — **entered together, deleted together**.

- **Several accounts, one category** — one transaction with several payment legs. Shipped (#704, #715). This plan makes it *editable*.
- **Several accounts, several categories** — a grid. Each **row** becomes an ordinary transaction (that account, its categories split), a legal shape today. Rows are tied by a new nullable `entries.group_id`.

The grid deliberately stores no account×category pairing. `CHECK (account_id IS NULL OR category_id IS NULL)` means a posting is an account leg or a category leg, never both — so a single transaction has nowhere to put one. Decomposing by row sidesteps it: a row has one account.

## This plan was audited before execution. Read this section.

An audit against the codebase found the previous draft wrong in ten places and silent on fifteen more. The corrections are folded in below. Two are worth stating up front because they are the shape of mistake this codebase punishes:

- The draft named `Pack.swift` and `DownSync.swift` as needing the new column. **Neither needs anything** — `Pack` ships the database as opaque bytes, `DownSync` derives its column list from `db.columns(in:)`. Meanwhile the four places that actually gate the column reaching anything were named nowhere.
- The draft called `SplitAllocation`'s duplicate-tick guard "untested" and gave a task the job of pinning it. **It is already tested** (`SplitAllocationTests.swift:47`). That task would have passed green having changed nothing — the exact defect the draft's own preamble warns about.

**The lesson to carry into every task: a test that passes before you write the code is not evidence.** Revert your change, watch it fail, record the output.

## Execution order

**The prerequisite below must merge first.** After that, the tasks run in order: Phase 1 adds the column, Phase 2 the engine, Phase 3 the UI, Phase 4 the proof and the PR.

**Every task now carries files and `- [ ]` steps, and every decision has an implementing task.** An earlier revision had neither — six tasks were prose, and Decisions 6, 18, 19, 24 and 26 were stated and never built. If you find a decision with no task, that is a defect in this plan, not a judgement call for the implementer.

## Prerequisite

**`plans/ios-macos/2026-08-02-count-a-split-once-plan.md` must merge first.** It gives `Tx` an entry-level id and repairs 26 counting/statistics sites that are wrong today. This plan's grid adds a second grouping level on top of that one, and Task 10 depends on it directly.

## Global Constraints

- **No released product.** Schema migrations and breaking action changes are cheap. There is no user data to strand and no running service to break.
- **Base branch `feat/frontend`;** isolated worktree off `origin/feat/frontend`.
- **Build with** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and `xcodegen generate`.
- **Gate before every push:** `ios/scripts/ci-local.sh` must print `all checks passed`. It churns `Localizable.xcstrings` — discard unless a genuinely new string was generated.
- **`I18nError` codes go in `ErrorL10n.swift`.** UI text goes `String(localized:)` → `ios/scripts/zh-manual.json` → `bun run ios/scripts/build-xcstrings.ts`. An error code in `zh-manual.json` is a silent no-op.
- **No `Co-Authored-By` trailer.**
- **Poll for gates** (`pgrep -f ci-local.sh`). Waiting for a harness notification about a process you started never resolves — it stalled the predecessor plan five times.
- **`ArgsTests.swift:17` asserts `ActionName.allCases.count == 86`** and must be updated deliberately, not reflexively. Nothing is deleted (Decision 7) and there is one new action (Decision 15), so the count rises to **87**. `ApplyTests.swift:26-29` asserts every case has a registry handler — it should keep passing.

## Design decisions (do not relitigate)

### The write model

1. **A command should match a user's intent, not a table.** Saving a transaction is one intent, but it currently sends three to five commands — `EditTransactionSheet.save()` fires four on the ordinary path and **five** when collapsing a split (`:477`, `:479`, `:493`, `:496`, `:501`); the Add sheet fires three. **The transfer path is extra and Task 4 must replace it too:** `saveTransfer()` fires up to three (`EditTransactionSheet.swift:531`, `:537`, `:540`) and the transfer add path one (`AddTransactionSheet.swift:646`). The screen therefore owns the sequence, the ordering and the dependencies, and each new screen must re-learn them. A part-way failure leaves the ledger half-updated — already shipped once as a bug.

   **Add one `saveTransaction` command** carrying the whole intent: header, account legs, category legs, tags. Create and update are the same command. The screen states what the user wants; the engine decides the mechanics, in one write.

2. **Where the line falls: if a half-applied result would be nonsense, it is one command. If the pieces stand alone, leave them separate.**
   - **Coarse:** saving a transaction, saving a grid.
   - **Unchanged and deliberately fine-grained:** `setReviewed`, `confirmTransaction`, standalone tag edits, `bulkRecategorize`.

   The reason not to coarsen everything: **sync replays operations, so finer commands merge better.** One device renaming a merchant and another re-tagging the same transaction both survive today; a coarse whole-transaction command from each would make the later one overwrite the earlier wholesale. Atomicity and merge granularity pull in opposite directions, and the split above puts each where it matters.

3. **This is also a speed win, independent of correctness.** Every `apply` fires the full side-effect train — *"16 projections + full Spotlight re-index + widget/notification replans"* (`FinchStore.swift:245-247`), which the FX refresh proved can jam the UI for seconds when repeated. A save goes from 3–5 database commits and 3–5 side-effect passes to **one of each**. (The heaviest work is already deferred off the critical path by `scheduleAmbientSideEffects`, but it still runs 3–5 times.)

4. **What this decision deletes from the plan.** The earlier draft proposed an `applyAll(ops)` batch wrapper. With one intent-shaped command it is **not needed for the save path**, and three problems evaporate with it:
   - **No id threading.** The draft's central hole was that `setTransactionSplits` needs the id `addTransaction` just minted, which a flat op list cannot express. One command mints and uses it internally.
   - **No opaque sync record.** A batch would have had to reach the outbox as a composite mutation peers could only run-or-not. `saveTransaction` replays as one meaningful, inspectable operation — which also fixes the divergence risk: `applyRemote` catches a replay failure, records `status.lastError` and moves on with no retry or rollback (`CloudKitSyncCoordinator.swift:144-146`), so N ops replayed individually can half-apply on a peer **permanently**.
   - **No `Apply` special-cases to route around.** `applyReturningId` special-cases `.addTransaction` (`:56-58`) and `applyReturningCount` the copy actions (`:77-79`); a naive batch dispatching `registry[name]` would silently drop the new entry id and the copy counts.

   **If a batch wrapper is still wanted for bulk operations, it is a separate piece of work** — and it must not reuse `applyBatch` (`FinchStore.swift:252`), whose documented behaviour is to *skip* failures and continue.

5. **Attachments are outside atomicity and the plan says so.** Both writes are `Task { try? await … }` — detached, async, error-swallowing (`AddTransactionSheet.swift:696-701`). They cannot join a synchronous write, and rolling back the database would not unwrite a file. **The promise is: the ledger is atomic; files are best-effort.** Today a failed receipt is discarded silently — the transaction saves looking complete, without it. Surfacing that is desirable but is not what makes the save atomic; treat it as a separate small fix.

6. **The other transaction-creating callers stay on `addTransaction`** — 10 call sites across 7 files — `ImportStatementView:88`, `ReconcileSheet:215`, `FinchIntents:48` (Siri), `PhoneWatchLink:90` (Watch), `PendingAttachmentImporter:34` (share extension), and the seeds. Each writes exactly one transaction and nothing else, so none has half-applied state to suffer. **Two creation paths therefore coexist: comment both**, saying `saveTransaction` is for a screen where one confirm spans several things and `addTransaction` is for a single programmatic write, or someone will pick the wrong one.

   (Note the statement import loops per row, so a mid-loop failure imports some and not others. Moving it to `saveTransaction` would *not* fix that — each row is still its own write — and a resumable partial import may well be preferable to all-or-nothing. Out of scope either way.)

7. **`setTransactionSplits` stays.** An earlier draft deleted it, reasoning that its only callers are the two sheets (`AddTransactionSheet:694`, `EditTransactionSheet:488`, `:493`) so `saveTransaction` would leave it with none. **That is wrong: the cross-stack `WRITE_SEQUENCE` replays it** (`frontend/scripts/export-fixtures.ts:447`). It is a shared artefact with a web implementation and web callers, so deleting it is a two-stack change — and this plan is iOS-only by your scope decision. Same for `createTransfer` (`:432`, `:549`).

   **The cost of keeping it, stated so it is not forgotten:** deleting it would have removed **one of the three rebuild-from-one-`LIMIT 1`-leg paths guarded in #704**, along with its guard, its `sumMismatch`/`minTwo` checks and its tests. That cleanup is **deferred to whenever the web catches up**, not abandoned. Until then the iOS sheets simply stop calling it, and the guard stays earning its keep.

   **Its multi-account refusal must be REPLICATED in `saveTransaction`** (not moved — `setTransactionSplits` keeps its own, and Decision 13 keeps the engine guard too), which still needs it: a *single* transaction cannot be split by both axes at once. (The grid is not that shape — it is N transactions of one account each.)

   **`ArgsTests.swift:17` asserts `ActionName.allCases.count == 86` and must be updated deliberately.** Nothing is removed and there is only **one** new action (Decision 15), so the count goes 86 → **87**. Update it once. `ApplyTests.swift:26-29` asserts every case has a registry handler and should keep passing — if it fails, the new action was not registered.

8. **`saveTransaction` is one command; the id decides.** No `id` creates; an `id` replaces that transaction's contents wholesale. Add and Edit send the same shape, which is what stops them drifting — they already have, with Edit firing five writes where Add fires three and handling splits differently.

   **"Replace wholesale" must preserve posting identity** — see Decisions 29-30. Matched legs keep their posting `id`, `memo` and FX fields; a reconcile mark survives an amount change and drops when the account changes. Getting this wrong silently un-reconciles an edited transaction, which balances and passes the audit.

### Entry flow

9. **Two pages.** Page 1: amount, merchant, date, and *which* accounts and *which* categories. Page 2: divide the money.

    **Which kinds this applies to — expense, income and refund; NOT transfer.** The current split UI has no kind restriction at all (`categorySplitBlocked`/`accountSplitBlocked` gate only each other, `AddTransactionSheet.swift:213-214`), and the grid needs none either: a transfer excludes itself, because `validateShape` requires exactly two account legs and **no** category leg (`Entries.swift:288-291`), so a grid row can never be one. Income is a real case — a paycheck landing in two accounts, split across two categories — and the scheduler already produces its single-axis form.

    **Scheduling a grid is out of scope, and the asymmetry must be stated in the UI, not discovered.** `scheduled_splits` is **income-only** (`Scheduled.swift:81`) and stores account splits alone; a scheduled grid would need new schema and a new posting path. So a purchase you can build by hand cannot be set to repeat. Do not silently offer a split option on `ScheduledSheet` that behaves differently from the one on `AddTransactionSheet`.
10. **✓ becomes Next** at 2+ on either axis.
11. **Page 2 is a list** when one axis is split, **a grid** when both are.

    **The cells are typed; the totals are derived.** You never enter a card split *and* a category split separately — **the grid is both**. Row totals and column totals are shown live and update as you type; the only constraint is that everything adds up to the purchase amount.

    **This is not a design preference, it is forced by arithmetic.** Two card amounts and two category amounts do **not** determine the four cells — many grids share the same margins ($60/$0/$10/$30 and $42/$18/$28/$12 both give 60/40 and 70/30). So the app must either guess or ask. Guessing is wrong precisely when the pairing was deliberate ("the electronics went on the credit card"), and there would be no way to correct it.

    **An empty cell is not a zero leg** — it is simply absent. Card A spending nothing on household means that entry has no household category leg.

    **The purchase amount is the target, and saving is blocked until the cells reach it.** The receipt total is the one number you are certain of; if the parts do not reach it you have mistyped a part, and being told beats saving a purchase that is quietly $5 light. This also matches how the existing category split already behaves.

    **Implementation shape: ONE `SplitAllocation` over all the cells, keyed `"<accountId>|<categoryId>"`.** Not a 2D widget, and not N stacked instances — a single flat allocation whose `total` is the purchase amount.

    `SplitAllocation` already does everything this needs, unchanged:
    - **pinned vs floating** (`:14-16`) — a cell you type is held, untyped cells divide what is left. That is the "spread the rest for me" behaviour for free.
    - **exact sums** — `redistribute` gives the last floating cell the remainder, so cells always total exactly (`:60-70`).
    - **the blocked state** — when every cell is pinned, `redistribute` returns early (`guard !free.isEmpty else { return }`), so `allocated` can legitimately differ from `total`. **That is the "$5 unaccounted" condition**, and it is already expressible: `abs(allocated - total) >= 0.005`.
    - **`Row.id` is a plain `String`** (`:18`), so a composite key needs no change to the type.

    **Card and category totals are derived by grouping the cell ids** — prefix for the card row, suffix for the category column. Nothing stores them.

    **Every combination starts ticked and floating**, so arriving at a 2×2 grid on $100 shows four cells of $25 that redistribute as you type — the same behaviour as ticking a category on the existing split. **A combination that did not happen is crossed out (`untick`), not zeroed**, which is what makes "an empty cell is not a zero leg" fall out rather than needing a rule.

    **Two edge cases resolve themselves through the component, and no new rule is needed:**
    - **Going back to page 1 and changing the selection.** Adding a card ticks M new floating cells; `redistribute` divides only what the pinned cells have not claimed, so **everything you typed survives**. Removing a card unticks its cells and frees their amount back to the floating ones.
    - **Crossing out every cell in a card's row** leaves that card paying nothing, which is the same as never selecting it — drop it from the purchase. Likewise a category with no cells left.
12. **The multi-select rows already exist** — `MultiSelectPickerRow` and `CategoryMultiPickerRow`, used six times in `BudgetSheet`. **Add to `SearchablePickerRow`, do not restructure it**: it is shared by `ScheduledSheet` (×3: `:106`, `:108`, `:111`), `EditTransactionSheet` (×2), `AddTransactionSheet` (×4: `:349`, `:407`, `:437`, `:439`) and the transfer pickers. **Not `CategoriesView`** — that uses `CategoryPickerRow`, a different file with its own sheet (`CategoriesView.swift:551`, `CategoryPickerRow.swift:77`). The existing `splitting:` / `splitLocked:` parameters are the additive pattern to follow.
13. **The grid is currently unreachable by construction and the guards must be lifted.** `categorySplitBlocked` / `accountSplitBlocked` (`AddTransactionSheet.swift:205-214`) make the two splits mutually exclusive *deliberately*, threaded into both pickers as `splitLocked` with user-visible copy. Lifting them means routing the both-axes case to the grid, and retiring two localized strings. **Keep the engine guard** `error.split.multiAccount` (`Transactions.swift:50-53`) — it protects the single-entry shape and is still correct.

### What gets saved

14. **Several accounts, one category → one transaction** with a payment leg per account. Unchanged — **no task, because nothing is built for it.** It ships already (#704/#715), and the prerequisite plan now *enforces* it by forbidding the both-axes shape, so it is the only single-entry split there is.
15. **The payload is the CELLS, and the engine decides the shape.**

    `saveTransaction` receives the grid — `{accountId, categoryId, amount}` per cell — plus the header, tags and merchant. It then decides:
    - **all cells share one category** → **one** transaction with a payment leg per card (Decision 14's shape)
    - **more than one category** → **one transaction per card**, linked by `group_id`

    **An earlier draft this session said "N rows = N transactions". That was wrong and is withdrawn** — it cannot express split tender, where two cards against one category must be a *single* transaction. **The shape depends on the category count, not the card count.** Letting the engine derive it is exactly Decision 1: the screen states what the user wants, the engine decides the mechanics.

    **The UI already holds this shape.** Decision 11's flat `SplitAllocation` is keyed `"<accountId>|<categoryId>"` — one row per cell. The screen's state and the payload are the same structure, so there is nothing to translate.

    It writes everything in one transaction, so it is atomic locally *and* replays as one op on peers (Decision 4). **Action count 87, not 88.**

16. **Amounts are in the PURCHASE's currency, not each card's.** You may pick a dollar card and a euro card for one purchase; you type every cell in one currency, so the grid's columns genuinely add up. Each card's leg is then *recorded* in that card's own currency, converted at the transaction's date — which is what will appear on that statement.

    **This is the opposite of `addTransaction` today**, which reads a split's amounts as already being in each card's own currency (`Transactions.swift:287-290`). The two only disagree when currencies are mixed — precisely the case in question — so the difference cannot be left implicit.

17. **`addTransaction` keeps its own arg-to-leg resolution. WITHDRAWN — an earlier draft made it a thin adapter over `saveTransaction`'s core, and the premise was wrong.**

    That draft argued two implementations would have to agree about "balancing, rounding, rules and reconcile marks" independently. **They already do.** `addTransactionReturningId` calls `Entries.postEntry` on all three of its paths, and `postEntry` owns balancing, the FX residue, rule application and shape validation. Reconcile marks do not exist on a create path.

    **What genuinely differs is the one thing that must:** turning args into legs. `addTransaction`'s amounts are in each card's own currency (`Transactions.swift:287-290`); `saveTransaction`'s are in the purchase's (Decision 16). Routing one through the other means converting **card → base → card**, and this file already documents that such round trips can miss exact cent equality across N+1 roundings. `addTransaction` is replayed by the cross-stack oracle, so a one-cent drift reddens the gate — a real cost for a benefit `postEntry` already provides.

    **The two commands still coexist and must each say which is which** (Decision 6): `saveTransaction` for a screen where one confirm spans several things, `addTransaction` for a single programmatic write.

18. **Rows are linked** by nullable `entries.group_id`. Without it the grid is a one-way door: buildable, never revisable, and the information to reconstruct a group is never written, so adding the link later cannot recover it.

### Group semantics

19. **Deleting removes what you pointed at. The two shapes therefore differ, because they genuinely are different.**

    - **Split tender** (one transaction, several payment legs): deleting any leg deletes the whole transaction. **This is forced, not chosen** — $60 of payments against a $100 category leg is not a state the ledger can hold. **Warn first.**
    - **A grid** (several transactions): deleting a row deletes **only that row**. The others are independently valid and survive.

    **An earlier draft cascaded the grid too, for consistency.** Withdrawn: a destructive action taking something you did not point at is worse than the extra tap to remove a second row — and edit already removes a row without touching the rest, so cascading would have made two paths to the same intent behave differently.

    **This costs nothing to build and removes work.** The eight warned delete sites already key on `accountLegCount > 1`, which is true for split tender and false for a grid row — so the warning already fires exactly where it should. The earlier decision would have required group-cascade logic at eleven sites.

    **One thing delete DOES gain:** after removing a group member, if a single member remains its `group_id` must be cleared (Decision 20). That path is now reachable by delete, not only by edit.
20. **A group reduced to one member clears its `group_id`**, so a lone transaction stops claiming to be a group. **Do not add an audit code for this** — `Audit.Code` is documented as the web's exact 10-code union, so an 11th is a wire-format change. Enforce it at write time instead.
21. **Editing reopens the same two-page flow used for adding**, and rewrites the whole purchase — for any shape, not only a group.

    **So editing can change the shape.** Add a second category to a two-card purchase and it becomes a linked pair; remove one and it collapses back. Anything you can build when adding, you can change when editing — otherwise the answer to "I got the categories wrong" is "delete it and start again", which is the thing this plan exists to remove.

    **Identity rules, because conversion creates and destroys entries:**
    - **Rows are matched to existing entries by account**, the same rule legs use (Decision 29). A row whose card is unchanged **keeps its entry id**, so its receipt, its `Tx.id` and its reconcile marks survive.
    - **A row that disappears has its attachments unlinked** — see Task 6. This is the ordinary-edit case of the orphaning problem, not just the delete case.
    - **Never mint a new entry id for a row that could have kept one.** Preserving ids is what makes conversion safe rather than destructive.
22. **A neutral row glyph** marks split purchases, joining the existing pending-clock / anomaly-warning family. **One symbol, one meaning: "this is part of one purchase."** It covers both shapes — and note the meaning changed with Decision 19: it can no longer promise "deleting this takes others with it", because for a grid it does not. Render it in `TxRow` — `TxRowCell` hosts that same SwiftUI view via `UIHostingConfiguration` (`:62-67`) and renders nothing itself, so it is **one** place to change, not two.

### Editing the single-transaction shape

23. **The account legs are part of `saveTransaction`'s payload** — not a `patch` key on `updateTransaction`. Two earlier drafts argued this the other way (first for symmetry, then for atomicity); Decision 1 settles it. Consequences worth noting because they are all improvements:
    - **`updateTransaction`'s multi-leg refusal stays absolute**, not conditional on which patch keys are present. An earlier draft accepted a conditional guard as a cost; it is no longer needed.
    - **There is no "`accounts` and `amount` in one patch" contradiction to reject** — the payload carries legs, and the total is derived from them.
    - `updateTransaction` keeps its existing meaning for the programmatic callers that use it.
24. **No sum validation on the `accounts` path** — the shares *are* the total.
25. **The caller computes the balancing category leg.** `EntryPatch` has **no** auto-balance field; that is a `NewEntry`/`postEntry` concept. `rebuildEntry` with `.legs = .set(...)` writes exactly what it is handed. Compute `-sum(acctBase)` **and pass the existing category leg's `id:` and `memo:`** — as the existing money path does at `Transactions.swift:492-493` — or the category posting id churns on every account edit, and `TxSplit.id` addresses postings by id. (An earlier draft also cited `bulkRecategorize` here — **wrong**: it takes *account*-posting ids and its own rebuild discards the category posting id entirely, `Transactions.swift:556-557`, `:579`. A shipped path already churns it, which weakens but does not remove the argument.)
26. **Accepts 1..N accounts.** One collapses a split. Zero refused.
27. **One entry is split on at most ONE axis.** Several accounts + one category, or one account + several categories — never both on the same entry. Both-axes is the grid, which is N entries of one account each (Decision 15), so the rule holds there too.

    **This replaces an earlier draft rule that said "2+ category legs → refuse."** That was scoped to the abandoned `patch.accounts` path and, read against `saveTransaction`, it refuses ordinary category splits — the feature that already ships. The refusal is about *combining* axes, not about category legs existing. (For context on what it was mirroring — and the earlier draft described this wrongly: `updateTransaction` is a silent header-only no-op on such an entry **only when the patch carries `category`** (`Transactions.swift:450`, `:484`). With `amount` alone, control reaches `:488-494` and **collapses ≥2 category legs down to one**. That is a live data-loss path, not a no-op, and it is a fourth sibling of the three guarded in #704.)
28. **Amounts signed by the caller;** signs disagreeing with `kind` are rejected, never coerced. **Scope this rule to `accounts[].amount` only.** Applied to the top-level `amount` it breaks the CSV import (raw signed amounts, no `kind`) and App Intents — see Decision 31.
29. **Legs match existing postings by `accountId`.** A matched leg keeps its posting `id`, `memo` and FX fields.
30. **A reconcile mark drops when the leg's contribution to the cleared balance changes — so on an AMOUNT change as well as an account change.**

    A tick means *"I checked this against my statement."* `clearedBalance` is simply the sum of ticked legs (`ReconcileState.swift:18-24`), so editing a ticked $60 payment to $70 silently moves a finished reconciliation by $10 while the screen still reports you square. **Change the amount and the tick is no longer something you checked — it is something you asserted.** It drops; the reconcile screen shows the difference; you look again and re-tick.

    **This reverses an earlier draft**, which kept the mark through an amount change on the grounds that `Transfers.update` does so deliberately (`Transfers.swift:12-15`). That reasoning does not survive reading what the mark feeds. **So this also changes transfer behaviour** — editing a cleared transfer's amount now unticks both legs. State it in `Transfers.swift`'s doc comment rather than leaving the old sentence contradicting the new rule.

    **What still survives:** date, time, note, merchant, category, tags — none of them changes what the account's balance owes that leg.

    **The account change needs no rule of its own.** A leg whose account changed is a new posting (Decision 29), so the mark goes with the old one. `Schema.swift:382-383` states clearing is per account leg — *"clearing a transfer from account A's statement must not clear account B's leg"* — and the existing single-account path violates it by passing `cleared_at` through unconditionally (`Transactions.swift:491`). **That is a pre-existing bug and this plan fixes it.**

    **`Tx.id` is the posting id** (`Projection.swift:14`), so moving a leg's account changes the identity of the row the user was looking at. The sheet dismisses on save and the list rebuilds, so that is safe there; anything holding a `Tx.id` across the save must tolerate it going missing, which is already true of delete.

31. **Degenerate share sets rejected** — same account twice, zero share — in the edit path and retrofitted into `addTransaction`, which accepts both today. Ten non-test call sites exist across seven files (`ImportStatementView:88`, `ReconcileSheet:215`, `FinchIntents:48`, `PhoneWatchLink:90`, `PendingAttachmentImporter:34`, `SimulatorDemoSeed:264,364,423,455`, `StressSeed:36`); **none passes `accounts`, so the retrofit is safe provided Decision 28's scoping holds.**

### Counting

32. **Count groups, then entries, then rows** — a group counts as one, an entry counts as one, a row is not a unit.

    **The entry level is a PREREQUISITE, not part of this plan.** A census found **26 sites** across `Selectors.swift`, `Insights.swift`, the Categories/Tags/Merchants admin surface (SwiftUI and UIKit), `NotificationPlanner` and `QuickAddCatalog` that count `Tx` rows as transactions — a live inaccuracy shipped in #704/#715, independent of this feature. It is fixed by its own plan, landing **before** this one: `2026-08-02-count-a-split-once-plan.md`.

    **Why it must land first:** that plan gives `Tx` the entry-level id it does not have today (`Tx.id` is a *posting* id and `accountLegCount` is a flag, not a join key — so a purchase currently cannot be reconstructed from a `[Tx]` array at all). This plan's grid then adds a **second** grouping level on top. Building the second level on a broken first means debugging both at once.

    **What remains in scope here:** the group level only — a grid's N rows count as one purchase, using `entries.group_id` (Task 1).

    **Concretely, and this is easy to miss:** the prerequisite introduces `Tx.purchaseKey` (`entryId ?? id`) and `Selectors.byPurchase`, both keyed on the **entry**. A grid is N entries, so **under both plans as written a grid group would count as N purchases** — reintroducing the very bug the prerequisite exists to fix. Task 10 must widen `purchaseKey` to `groupId ?? entryId ?? id` and confirm every `byPurchase` consumer follows.

### Consequences, stated so they are not discovered

- **A split's `kind` cannot be changed** — `touchesMoney` includes `kind` (`Transactions.swift:419`).
- **Editing does not re-run rules** — `applyRules` is called only from `postEntry` and the backfill; `onEditOnly` exists but no call site passes it.
- **`dedup_hash` collides on a grid rewrite.** It is re-stamped from `date|time|description|acctLegs` under `UNIQUE(ledger_id, dedup_hash)`, and a grid's rows share all but the account. A rewrite must **delete before re-posting**, or it collides with itself and surfaces as "This looks like a duplicate."
- **`Budgets.invalidateForEntry` must be called per grid row** (`Transactions.swift:316,345,358,393,413` all do). Skipping it leaves the rollover cache stale: wrong budget numbers, no error, no audit problem. (It already only inspects the *first* account leg, so split tender under-invalidates today.)

## Rules: frozen here, and flagged for its own design review

**This plan changes nothing about rules. It freezes today's behaviour and states it, because folding the sheets' commands into one would otherwise change it silently.**

Today's behaviour, which is accidental rather than designed:
- `addTransaction` runs rules inside `postEntry`, which may **replace the category legs** (`Entries.swift:429-446`); `setTransactionSplits` then overwrites them with the user's. **The user wins because they go last.** One command would invert that unless it is explicit.
- `applyRules` is called only from `postEntry` and the backfill, so **create runs rules and edit does not**. The same payload with and without an `id` therefore behaves differently.

**`saveTransaction` must preserve both:** an explicit split in the payload stands (a rule's other actions — merchant, tags, kind — still apply), and a payload carrying an `id` does not run rules.

**The whole rules design needs revisiting separately.** Things found while planning this that belong in that review, none of which should be fixed here:
- `run_on_edit` is **plumbed but not wired**: `RulesEngine.applyRules` takes `onEditOnly` (`:124`, checked at `:129`) and **no call site passes it**. The column, the UI toggle and the projection field all exist; the behaviour does not.
- **Precedence between a rule and explicit user input is undefined** — it is currently settled by which command runs last.
- A rule only ever applies at create, so a rule written later never touches existing transactions except through `backfillRule` — which is one of the three paths that needed a data-loss guard in #704.
- **A rule cannot do what the grid lets a person do.** The prerequisite plan makes a rule's `split` action skip a multi-card purchase, because the app's rule is one category per multi-card purchase. This plan's grid then lets a *person* split by both, as linked transactions. So a rule is permanently less capable than the screen. Deliberate for now — a rule turning one purchase into several linked transactions unasked needs its own design — but it is the rules review's to settle.
- The synthetic `Tx` handed to the engine for a multi-account entry is lossy by design (summed amount, largest leg names the account, shared-or-base currency — #704). Fine for matching; worth re-examining once rules have a considered design.

## Transfers fold in too

**The transfer UI saves through `saveTransaction`. Both sheets, every kind, one command, one write.**

**This does not mean deleting the transfer actions.** `createTransfer` appears twice in the cross-stack `WRITE_SEQUENCE` (`frontend/scripts/export-fixtures.ts:432`, `:549`) and `setTransactionSplits` once (`:447`). Those are shared artefacts the web replays, and this plan is iOS-only. **The actions stay, keep their web callers, and keep their parity coverage.** `saveTransaction` is added alongside; the iOS sheets move onto it. This also closes the earlier open question about `setTransactionSplits` — nothing shared gets changed.

### Why this is cheaper than it looks

- **`updateTransfer` is already a whole-entry leg replace** — `ep.legs = .set([both legs])` then `rebuildEntry` (`Transfers.swift:58-66`), already passing `id:` and `clearedAt:` per leg. `saveTransaction` reproduces that body. It is not new behaviour to re-prove.
- **The bug `updateTransfer` exists to prevent cannot occur under whole-entry replace.** Its doc says the old single-leg patch path "could diverge them"; a transfer is ONE entry, so replacing its leg set moves both legs or neither.
- **Per-leg reconcile marks** are exactly the match-by-account rule already decided — nothing extra.

### What actually moves

**Three guards live in `postTransfer`, not `validateShape`** (`Entries.swift:560-573`). `saveTransaction` reaches `validateShape` but not `postTransfer`, so as written it would accept:
- **a transfer whose two legs are the same account** — `validateShape` only checks `acct.count == 2` and that no plain category leg exists, so it passes
- a zero amount
- a same-currency transfer whose two amounts disagree

**There is a fourth:** `error.transfer.receivedGt0` (`Entries.swift:571`), which rejects a non-positive received amount.

**Move all four into `validateShape`'s `.transfer` case**, where every path runs them — including the scheduler, which also calls `postTransfer` (`Scheduled.swift:74`, `:160`).

**Moving them changes two error codes, and that must be deliberate.** `postTransfer` checks the zero amount (`:560`) and the same-account case (`:561`) **before** looking the accounts up (`:564`). Run from `validateShape`, the lookup happens first, so a zero-amount transfer naming a bad account now reports `error.notFound.account` instead of `error.transfer.amountGt0`. Assert the new ordering in a test rather than discovering it as a regression.

**`postTransfer` stays.** The scheduler posts transfers with `toAmount` nil (`Scheduled.swift:74`, `:160`) and relies on the engine deriving it via `convertToBase` (`Entries.swift:576`). Sheets have no rate lookup, so that derivation cannot move UI-side. The add-transfer UI never needed it: it already **requires** the received amount when cross-currency (`AddTransactionSheet.swift:637-641`) and omits it only when same-currency, where the conversion is the identity.

**Ratio-scaling moves to the caller, but the FX pin does NOT.** `updateTransfer` scales the other side when only one amount is given (`Transfers.swift:40-56`). `saveTransaction` takes complete legs, so the sheet supplies both native amounts — `TransferEditPatch.build` already owns the form's parsing and validation and grows the scaling. Same-currency mirrors; cross-currency the form already collects both.

**A contradiction to resolve before implementing.** Decision 29 says a matched leg keeps its "`id`, `memo` and FX fields", while this section hands the engine a *new* native amount. Both cannot hold literally: keeping the stored `amount_base` alongside a new native yields an inconsistent leg, and omitting the FX fields makes `resolveLegs` re-lock the rate via `convertToBase` (`Entries.swift:229-231`), **silently discarding a pinned rate**.

**The rule is: preserve the RATE, recompute the base from it.** For a leg matched by account, `amount_base = newNative × storedRate`. That is exactly what `updateTransfer` achieves by scaling base proportionally to native (`Transfers.swift:51-56`), and it keeps a pinned rate pinned across an amount edit. A leg whose account *changed* is a new posting and re-locks normally.

**Derived memo and description stay engine-side.** `postTransfer` writes description `"Transfer"` and memos `"Transfer to <name>"` / `"Transfer from <name>"` (`Entries.swift:578-583`). Those are engine-authored today and must not become the sheet's job. `saveTransaction` fills them for `kind == .transfer` when absent. This composes with match-by-account: an unchanged leg keeps its stored memo, and changing a leg's account creates a new posting, which gets a freshly derived memo naming the new account.

## What `saveTransaction` must carry, and what it cannot reuse

The command replaces every write the two sheets fire today (3 on add, 4-5 on edit). Working out what it has to own:

**The entry header rides on `EntryPatch`, which is sufficient.** It reaches `date`, `time`, `description`, `kind`, `notes`, `counterpartyId`, `refundedEntryId`, `status`, `legs` (`Entries.swift:641-652`) — every field either sheet edits. The `entries` columns it does *not* reach are not gaps: `confirmed_at` and `dedup_hash` are maintained by `rebuildEntry` itself (`:681`, `:733`), `reviewed_at` and `applied_rule_ids` belong to other actions, and `source_template_id`/`occurrence_date` are set at post time and never edited.

**Tags do not ride on it.** `entry_tags` is written only by `postEntry` (`:471`) and `postTransfer` (`:587`); `rebuildEntry` never touches it, which is why `setTransactionTags` is a separate write in both sheets today. `saveTransaction` must write `entry_tags` itself, as a set-replace within the same transaction.

**The merchant must be resolve-or-create, and this fixes a real leak.** `resolveCounterpartyIdByName` **only looks up — it never creates** (`Entries.swift:206-212`). That is precisely why both sheets call `createCounterparty` *before* the update (`EditTransactionSheet.swift:477`, `AddTransactionSheet.swift:673`): write 1 must create the name so write 2 can find it. That ordering dependency cannot survive one command, so `saveTransaction` takes the merchant **name** and does resolve-or-create inside the transaction. Today, if the update fails after the create succeeds, the ledger keeps an orphan counterparty for a transaction that was never saved; one write removes that by construction.

**Amounts are in the PURCHASE's currency (Decision 16).** Two earlier drafts of this section got this wrong in turn. The first claimed conflicting per-leg defaults at `Transactions.swift:295` and `:326` and demanded an explicit per-leg currency — a misreading, since `AccountShare` is `{accountId, amount}` (`:253-256`) with no per-leg currency at all. The second concluded a leg simply inherits its account's currency, which is what `addTransaction` does today (each share converts from its own account's currency, `:287-290`).

**Neither is what this command takes.** You may pick a dollar card and a euro card for one purchase and type every cell in ONE currency, so the grid's columns add up; each leg is then *recorded* in its own card's currency, converted at the transaction's date, because that is what reaches that statement. `addTransaction` keeps its own meaning and the conversion lives in its adapter (Decision 17) — one documented place rather than two commands disagreeing about what a number means.

**`EntryPatch` covers the EDIT path only — the create path needs six more things.** An earlier draft said it was "sufficient"; that is true for editing and false for creating. `EntryPatch` reaches none of these, and the Add sheet sends the first three today:

| Field | Why | Proof |
|---|---|---|
| `ledgerId` | Required to post at all | `AddTransactionSheet.swift:645` |
| `sourceTemplateId`, `occurrenceDate` | The scheduled-occurrence link — and they **suppress `dedup_hash`** | `:679`; `Entries.swift:467` |
| `allowDuplicate` | Sent after the duplicate prompt; without it "Add anyway" is refused — a bug already fixed once | `AddTransactionSheet.swift:661`, comment at `:656-660` |
| `skipRules` | Must be forced `true` for `kind == .transfer`, or transfers begin matching rules | `Entries.swift:585` |
| A caller-supplied `id` | See the sync note below | `NewEntry.id` exists |
| `tagIds` | Task 3 already covers this | — |

**`applyReturningId` must special-case `saveTransaction`.** It special-cases `.addTransaction` only (`Apply.swift:56-58`), returning nil for anything else — and the Add sheet needs the new id to attach a receipt (`AddTransactionSheet.swift:688`, `:696-701`). Add it to that switch **and** to `FinchStore.applyReturningId:214`. The plan cites this exact special case as a reason a *batch* would silently fail; it applies no less to a new action.

**A refund link needs id translation.** `refundedTransactionId` arrives as a **posting** id and is resolved to an entry id on the way in (`Transactions.swift:269`, `:446`), then mapped back on the way out (`Projection.swift:160-162`). `EntryPatch.refundedEntryId` takes an entry id, so `saveTransaction` must do the same translation rather than storing what it was handed.

**Sync replay of a create diverges ids unless the payload carries one.** `applyRemote` replays the raw action once, with no retry (`CloudKitSyncCoordinator.swift:137-146`). A `saveTransaction` create with no `id` makes each peer mint a *different* entry id; a later `saveTransaction` carrying the origin's id then resolves to nil on that peer and **silently no-ops**. So the create path must accept a caller-supplied `id` — otherwise the permanent divergence Decision 4 claims to fix reappears one level up.

**Leg identity is by account** (see the identity decision above): a leg whose account is unchanged keeps its posting id and its `cleared_at`; changing the account creates a new posting, so the reconcile mark drops without a special rule. Nothing in the schema references a posting id — there is no `posting_id` column and no `REFERENCES postings` — so re-keying carries no risk beyond the mark itself.

## The one genuinely delicate requirement

**A rebuild replaces postings. Identity must survive it.** If a rebuild mints fresh postings, editing a split silently un-reconciles it — balanced, audit-clean, invisible. The codebase solves this twice; copy it: `rebuildEntry`'s date path carries `id`, `memo`, `orig_*` **and `cleared_at`** (`Entries.swift:715-722`), and `setTransactionSplits` does the same (`Transactions.swift:54-59`).

---

## Phase 1 — the column, and everything that must see it

### Task 1: `entries.group_id`

**Files — this list was wrong in the draft and is the plan's highest-risk correction:**
- Modify: `Schema.swift`, `Migrations.swift` (a new dated migration registering **after** `2026-08-01-budget-cycle-time`; `2026-07-22-entry-occurrence-date` is the shape to copy)
- Modify: `Entries.swift` — `postEntry`'s **explicit 19-column `entries` INSERT** (`:462-467`) and `NewEntry`
- Modify: `Projection.swift` — `selectSQL` names `entries` columns explicitly (`:14-22`)
- Modify: `Models.swift` — `Tx` gains `groupId`, as `String?` for the same reason the prerequisite makes `entryId` optional (the parity fixtures decode `[Tx]` from JSON written before the field existed)
- **Do NOT modify `WriteParityTests.swift`.** An earlier draft listed it here; Task 2 deliberately keeps `group_id` out of the parity snapshot, and `canonicalState` builds an **explicit** entry object (`:74-84`) so it ignores a new column on its own.
- **Do NOT touch `Pack.swift` or `DownSync.swift`** — both are column-agnostic and need nothing.

- [ ] **Step 1: Write tests that can fail.** A migration test, and — critically — a test asserting `group_id` **survives into `Tx`**, since that is what every later task reads. **Do not write an export/import round-trip test as the primary evidence: it passes without any change**, because Pack and DownSync are already generic. The draft named that as "the one that matters"; it was the one that proved nothing.
- [ ] **Step 2: Run to verify they fail.** Record the output.
- [ ] **Step 3: Implement** across the five files above.
- [ ] **Step 4:** `swift test`, then the full gate. Update `ArgsTests`' action count only if you added an action.
- [ ] **Step 5: Commit.**

### Task 2: Keep `group_id` OUT of the parity snapshot, deliberately

An earlier draft said to widen `canonicalState` "**and** its web twin" so the oracle could see `group_id`. **Withdrawn.** The web `entries` table has no `group_id` (`frontend/lib/db/core/entries-schema.ts:8-28`), so that needs a web schema migration and a web `postEntry` change — out of scope, and Task 11 establishes that `saveTransaction` and the grid stay iOS-only.

**The risk that draft feared cannot occur.** It worried that "iOS writes group ids, the web writes none, and the oracle prints green". The web has no action able to write one, so there is nothing to diverge — an iOS-only column the snapshot ignores is correct, not blind.

- [ ] **Step 1:** Confirm `canonicalState` builds an **explicit** entry object (`WriteParityTests.swift:56-130`) and so ignores a new column automatically. If it ever becomes `SELECT *` this decision breaks — leave a comment saying so.
- [ ] **Step 2:** Comment the `group_id` column in `Schema.swift` recording that it is iOS-only and deliberately outside parity.
- [ ] **Step 3: Commit.**

---

## Phase 2 — engine

### Task 3: `saveTransaction` — the one command

**This is the plan's centre**, and it is what Decisions 1, 2, 3 and 8 exist to justify. One action carrying the whole intent: header, account legs, category legs, tags, merchant. No `id` creates; an `id` replaces that transaction's contents wholesale. It replaces the 3 writes the Add sheet fires and the 4–5 the Edit sheet fires.

**Files:**
- Create/modify: a `saveTransaction` handler beside `Transactions.swift`; register in `Registry.swift`
- Modify: `Entries.swift` — `validateShape` gains the transfer guards (Task 4)
- Modify: `ArgsTests.swift:17` (action count `86` → `87`) and confirm `ApplyTests.swift:26-29` passes

**What it must own** (see "What `saveTransaction` must carry"):
- Header via `EntryPatch` — sufficient; `confirmed_at`/`dedup_hash` are `rebuildEntry`'s own
- **Tags**, as a set-replace — `rebuildEntry` never writes `entry_tags`
- **Merchant resolve-or-create** — `resolveCounterpartyIdByName` only looks up (`Entries.swift:206-212`)
- **Amounts in the PURCHASE's currency** (Decision 16), converted per leg to each card's own currency — NOT `addTransaction`'s meaning, which is why that becomes an adapter in Step 6
- **Legs matched to postings by account** — matched keeps `id`/`memo`/FX; changed account is a new posting
- **The balancing category leg computed by the caller**, passing the existing category leg's `id:`/`memo:` (Decision 25)
- **Wrapped in `Dedup.wrap`** on the create path, or a double-tap surfaces raw SQLite `UNIQUE constraint failed` text instead of the duplicate message
- **One-axis refusal** (Decision 27) and degenerate-share refusal (Decision 31)

- [ ] **Step 1: Write the reconcile tests first — three of them.** (a) Clear a leg, change its **account**, assert the mark is gone; this must fail against today's code on the *single-account* path too, since `Transactions.swift:491` passes `cleared_at` through unconditionally. (b) Clear a leg, change its **amount**, assert the mark is gone (Decision 30 — this reverses today's behaviour, so the failure is the point). (c) Clear a leg, change only the **note**, assert the mark **survives**. Without (c) the obvious wrong fix — drop the mark on every edit — passes.
- [ ] **Step 2: Write the atomicity test.** Save a valid merchant change *and* an invalid leg set in one payload; assert **the merchant did not change**. Against the current multi-write sheets this is the bug being fixed, so write it as a `saveTransaction` test from the start.
- [ ] **Step 3: Write the tags test.** Change tags and legs in one payload; assert both landed. This one fails for a non-obvious reason — `rebuildEntry` silently ignores tags — so record the failure output.
- [ ] **Step 4: Run all three, record the failures.**
- [ ] **Step 5: Implement.**
- [ ] **Step 6: Do NOT make `addTransaction` an adapter** (Decision 17, withdrawn). Verify the premise yourself before believing either version: `addTransactionReturningId` already calls `Entries.postEntry` on every path, so balancing, rounding, rules and validation are shared. Only the arg-to-leg resolution differs, and it must — the currencies mean different things.
- [ ] **Step 7: Write the attachment promise into the code** (Decision 5). `saveTransaction` is *the* atomic command, so the next reader will assume receipts ride along with it. They do not — both writes are `Task { try? await … }`, detached and error-swallowing (`AddTransactionSheet.swift:696-701`), and rolling back the database would not unwrite a file. **Comment it on `saveTransaction` itself: the ledger is atomic; files are best-effort.** Surfacing a failed receipt to the user is a separate small fix and stays out of scope.
- [ ] **Step 8: Comment both creation paths** (Decision 6). `saveTransaction` and `addTransaction` now coexist. Say on each which is which — `saveTransaction` for a screen where one confirm spans several things, `addTransaction` for a single programmatic write — or the next person picks the wrong one. The ten `addTransaction` call sites across seven files all stay put.
- [ ] **Step 9:** `swift test`, then the full gate.
- [ ] **Step 10: Commit.**

### Task 4: Transfers move onto `saveTransaction`

Per "Transfers fold in too". **`createTransfer`/`updateTransfer` are NOT deleted** — they appear in the cross-stack `WRITE_SEQUENCE` (`export-fixtures.ts:432`, `:549`) and this plan is iOS-only. The sheets stop calling them; the actions keep their web callers and parity coverage. Likewise `setTransactionSplits` stays (`:447`).

- [ ] **Step 1: Move three guards from `postTransfer` into `validateShape`'s `.transfer` case** — same-account, zero amount, same-currency mismatch (`Entries.swift:560-573`). **Write the same-account test first**: `validateShape` today counts only `acct.count == 2` and finds no plain category leg, so it passes a transfer whose two legs are the same account. That test must fail before the move.
- [ ] **Step 2: `postTransfer` stays.** The scheduler posts with `toAmount` nil (`Scheduled.swift:74`, `:160`) and needs the engine's `convertToBase`; sheets have no rate lookup.
- [ ] **Step 3: Ratio-scaling moves into `TransferEditPatch`**, which already owns the form's parsing and validation. `saveTransaction` takes complete legs.
- [ ] **Step 4: Derived memo/description stay engine-side** — `saveTransaction` fills `"Transfer"` and `"Transfer to <name>"` for `kind == .transfer` when absent.
- [ ] **Step 5: Assert the reversed reconcile rule** (Decision 30): editing a cleared transfer's **amount unticks both legs**, and changing one side's **account** drops only that side's. Update `Transfers.swift:12-15`, whose doc comment still promises the old behaviour.
- [ ] **Step 6:** `swift test`, gate, commit.

### Task 5: `saveTransaction` with a full cell set — shape derivation, groups, rewrites and conversion

Implements Decisions 15, 19 and 20.

**Files:**
- Modify: `saveTransaction`'s handler (Task 3) — accept the full cell set and derive the shape
- Modify: `Registry.swift` — nothing new to register; this task **extends** `saveTransaction` (Task 3) to a full cell set. **No second action, so the count stays 87.**
- Test: `ios/FinchCore/Tests/FinchCoreTests/GridsTests.swift`

**Interfaces produced:** `saveTransaction`'s `cells` parameter — `[{accountId, categoryId, amount}]`, amounts in the **purchase's** currency (Decision 16).

**The engine derives the shape from the CATEGORY count** (Decision 15):
- cells spanning **one** category → **one** entry, a payment leg per card, **no `group_id`**
- cells spanning **several** categories → **one entry per card**, linked by `group_id`

**This is the same command as Task 3, extended.** Task 3 proves the single-category shapes; this task proves the multi-category one, and moving between them.

**Each derived entry is ordinary:** either one entry with N payment legs against one category, or one entry per card with its own category legs. **Never both axes on one entry** — forbidden by the prerequisite's Task 3, and `validateShape` would reject it.

**Amounts convert per card.** A cell is in the purchase's currency; the leg is stored in that card's currency, converted at the transaction's date, with `amount_base` from the ledger base. **Assert a mixed-currency grid**: a dollar card and a euro card in one purchase, cells all in dollars, and the euro leg stored in euros.

- [ ] **Step 1: Write the shape-derivation tests first — they are the heart of this task.** (a) Cells on two cards, **one** category → **one** entry with two payment legs and **no** `group_id`. (b) The same two cards across **two** categories → **two** entries sharing a `group_id`. **Without (a) the obvious implementation — one entry per card — silently turns every split-tender purchase into a group**, breaking Decision 14's shipped shape.
- [ ] **Step 2: Write the atomicity test.** Cells where the last is invalid; assert **no entries exist afterwards**. This is the property the whole design rests on.
- [ ] **Step 3: Write the rewrite test.** Save a grid, then save it again with changed amounts. Assert the group still has the same number of entries and no duplicate-hash error. **It fails without delete-before-repost:** `dedup_hash` is stamped from `date|time|description|acctLegs` under `UNIQUE(ledger_id, dedup_hash)` (`Entries.swift:752`), and a grid's rows share everything but the account, so a rewrite collides with itself and surfaces as "This looks like a duplicate."
- [ ] **Step 4: Write the two conversion tests** (Decision 21). (a) Save a one-row purchase, then save it again with two rows; assert the **original entry kept its id** and only the second is new. (b) The reverse: assert the surviving entry is the original and the removed row's attachments are unlinked. **Without (a) the obvious implementation — delete all, rewrite all — passes every other test in this task while silently destroying receipts and reconcile marks on an ordinary edit.**
- [ ] **Step 5: Write the group-of-one test** (Decision 20). Rewrite a 2-row grid down to 1 row; assert the surviving entry's `group_id` is **NULL**, so a lone transaction stops claiming to be a group. Enforce at write time — **do not add an audit code**, which would be an 11th and a wire-format change.
- [ ] **Step 6: Write the budget test.** Assert `Budgets.invalidateForEntry` runs for **every** row. Every existing money path does (`Transactions.swift:316,345,358,393,413`); skipping it leaves the rollover cache stale with no error and no audit finding.
- [ ] **Step 7: Run all seven, record the failures.**
- [ ] **Step 8: Implement.** **Preserve entry ids across a rewrite** rather than minting new ones — see Task 6 on attachments, and it keeps `Tx.id` stable for anything holding it.
- [ ] **Step 9:** `swift test`, gate. **Step 10: Commit.**

### Task 6: The delete tail

**Files:**
- Modify: `FinchStore+ViewHelpers.swift:110-115` (attachment unlink), `:136-141` (bulk delete)
- Modify: `ActivityTab.swift:409`, `ActivityFeedVC.swift:633` (the two bulk paths), `TxListDetailVC.swift:265` (the unwarned site)

- [ ] **Step 1: Write the attachment test for the EDIT path.** A two-row group with a receipt on each; edit it down to one row. Assert the removed row's files are unlinked and **the surviving row's are not**. Deleting a row directly is already correct, since it no longer cascades.
- [ ] **Step 2: Write the group-of-one test for delete.** Delete one member of a two-row group; assert the survivor's `group_id` is cleared (Decision 20) and that **it is still there at all** — the earlier cascading design would have removed it.
- [ ] **Step 3: Write the bulk-delete test.** Select a group member plus an unrelated row and delete. Assert the count reported matches what actually went. Today `applyBatch` (`:136-141`) reports "2 deleted" while 4 entries vanish — and `applyBatch` is the thing Decision 4 bans, because it **skips failures and continues**.
- [ ] **Step 4: Run all three, record. Step 5: Implement.**
- [ ] **Step 6: Add the missing warning** at `TxListDetailVC.swift:265` — eight sites warn via the `accountLegCount > 1` branch, this one does not.
- [ ] **Step 7:** `swift test`, build both UI targets, gate. **Step 8: Commit.**

---

## Phase 3 — UI

### Task 7: Page 1, selection

Implements Decisions 9-13.

**Files:**
- Modify: `AddTransactionSheet.swift` — two-page flow; lift `categorySplitBlocked` / `accountSplitBlocked` (`:213-214`)
- Modify: `SearchablePickerRow.swift` — **add to it, do not restructure it.** It is shared by `ScheduledSheet` (×3: `:106`, `:108`, `:111`), `EditTransactionSheet` (×2) and `AddTransactionSheet` (×4: `:349`, `:407`, `:437`, `:439`). Follow the existing additive `splitting:` / `splitLocked:` pattern.
- Reuse: `MultiSelectPickerRow`, `CategoryMultiPickerRow` — already used six times in `BudgetSheet`
- Retire: the two localized strings behind `splitLocked`

- [ ] **Step 1: Write the flow test.** Selecting 2+ accounts **or** 2+ categories turns ✓ into Next; one of each leaves it as ✓ (nothing to divide).
- [ ] **Step 2: Write the unblocking test.** Selecting 2+ on **both** axes is now permitted and routes to the grid. It fails today because the two are deliberately mutually exclusive.
- [ ] **Step 3: Run both, record. Step 4: Implement. Step 5:** `swift test`, gate, commit.

**Do not write a test pinning `SplitAllocation.tick`'s duplicate guard — one already exists** (`SplitAllocationTests.swift:47`). A task that re-pins it would pass having changed nothing.

### Task 8: Page 2, list and grid

Implements Decision 11.

**Files:**
- Create: a grid view beside `SplitAllocation.swift`
- Modify: `AddTransactionSheet.swift` — route to list or grid
- Reuse: **`SplitAllocation` unchanged**, as ONE flat allocation over the cells keyed `"<accountId>|<categoryId>"` (Decision 11). Do not fork it, do not add a 2D variant, and do not instantiate one per row.

**A list when one axis is split; a grid when both.** Rows are cards, columns categories; **each row becomes one entry** (Decision 15). **Cells are typed and the totals derive from them** (Decision 11) — the row total is what that card paid, the column total is what that category cost, and the grand total must equal the purchase.

- [ ] **Step 1: Write the args test — not the allocation-model test.** Assert the exact payload `saveTransaction` receives for a 2×2 grid — **four cells, sent as four cells**, with the shape derivation left to the engine (Decision 15), **including the signs**. The predecessor plan shipped a version where every expense split was rejected because shares were unsigned, and **407 green tests missed it** — all of them exercised the model, which was already correct.
- [ ] **Step 2: Write the rounding test.** A total that does not divide evenly (e.g. $100 across 3) must still sum exactly; the last cell absorbs the remainder.
- [ ] **Step 3: Write the back-navigation test.** Fill some cells, go back to page 1, add a third card, return. Assert **the typed cells still hold their values** and only the new cells float. This falls out of `redistribute` respecting `pinned`, so it should pass immediately — write it anyway, because it is the behaviour a later refactor is most likely to break silently.
- [ ] **Step 4: Write the empty-cell test.** A card with nothing in a category produces **no category leg** for it — not a zero-amount one. A zero leg would show as a $0 category on that transaction and pollute category counts.
- [ ] **Step 5: Write the margins test.** Assert the derived card and category totals, and that saving is refused when the cells do not reach the purchase amount. **This is the test that proves the cells drive the totals** rather than the other way round. The blocked condition is `abs(allocated - total) >= 0.005`, reachable only when every cell is pinned — assert that too, or a floating cell silently absorbs the error and the block never fires.
- [ ] **Step 6: Run all five, record. Step 7: Implement. Step 8:** `swift test`, gate, commit.

### Task 9: The Edit sheet's account editor

**The plan's stated goal.** Implements Decisions 21, 26 and 28.

**Files:** `EditTransactionSheet.swift` (`isSplit` at `:62`; the save path at `:472-507`)

**Why nothing works today:** `isSplit` means *category*-split only, so a multi-account purchase renders in the plain branch with a single-select picker bound to the one posting tapped; saving sends `patch["account"]` / `patch["amount"]` and is refused. **Without this task the engine accepts multi-account edits and nothing sends them.**

- [ ] **Step 1: Write the collapse test** (Decision 26). Edit a 2-account purchase down to 1; assert one account leg remains, the other posting is gone, and **zero accounts is refused**.
- [ ] **Step 2: Write the sign test** (Decision 28). A share whose sign disagrees with `kind` is **rejected, never coerced** — and scope this to `accounts[].amount` only. Applied to the top-level `amount` it breaks the CSV import (raw signed amounts, no `kind`) and App Intents.
- [ ] **Step 3: Write the grid-reopen test** (Decision 21). Editing **any** row of a group reopens the whole grid and rewrites the set. **Piecemeal editing is what this prevents** — nothing enforces that group members share a date or merchant, so editing one row alone could leave a "group" whose members disagree about what purchase they are.
- [ ] **Step 4: Run all three, record. Step 5: Implement. Step 6:** `swift test`, build both UI targets, gate, commit.

### Task 10: The row glyph, the delete warning, and the message that stops being true

Implements Decisions 22 and 32.

**Files:**
- Modify: `ActivityTab.swift` — `TxRow`'s badge row (the pending clock lives at `:649`); this is **one** place, since `TxRowCell.swift:62-67` hosts the same SwiftUI view via `UIHostingConfiguration` and renders nothing itself
- Modify: `Transactions.swift:50-53` + `ErrorL10n.swift` — the message
- Modify: wherever the prerequisite put `purchaseKey`

- [ ] **Step 1: Add the glyph.** A neutral symbol joining the pending-clock / anomaly-warning family. **One symbol, one meaning: "deleting this takes others with it."** It covers both split shapes — a multi-account purchase and a grid group. It must not read as the reconcile tick.
- [ ] **Step 2: Rewrite `error.split.multiAccount`.** It reads *"A purchase paid from several accounts takes a single category"* — **false once the grid ships**, and it appears on the very screen where someone is trying to do what it claims is impossible. Point at the grid instead. **The guard itself stays** (Decision 13); only the wording is wrong. `I18nError` codes localize in `ErrorL10n.swift`, **not** `zh-manual.json`, where they are a silent no-op.
- [ ] **Step 3: Widen `purchaseKey` to `groupId ?? entryId ?? id`** (Decision 32). Without this a grid group counts as N purchases, reintroducing the exact bug the prerequisite exists to fix.
- [ ] **Step 4: Write the counting test.** A 2-row grid group counts as **one** purchase in merchant insights. **Then check every `byPurchase` consumer**: it sums each row's *account-leg* amount, which for a grid group is the whole purchase — but a category screen wants only that category's share. Collapsing by entry was safe in the prerequisite only because split tender has a single category; a grid's rows do not.
- [ ] **Step 5:** `swift test`, build both UI targets, gate. **Step 6: Commit.**

---

## Phase 4 — ship

### Task 11: Equivalence proof, gate, PR

**The new actions do NOT go into `WRITE_SEQUENCE`.** An earlier draft said to add "write a grid, edit a grid, delete a group, edit a multi-account transaction's accounts". **Not possible within this plan's scope:** `writeWriteParityFixture` replays `WRITE_SEQUENCE` through the **web** engine to produce `expected` (`export-fixtures.ts:585-596`), and `applyMutation` throws `error.unknownAction` for any action without a web handler (`frontend/lib/db/mutate.ts:48-51`). Adding `saveTransaction` would require a full web implementation — the very argument Decision 7 uses to justify *keeping* `setTransactionSplits`. Worse, it would break fixture regeneration for **all** work, not just this.

**Instead, prove equivalence on iOS.** The oracle already covers the old multi-write sequence cross-stack; showing the new command produces byte-identical state transfers that guarantee.

- [ ] **Step 1: Write the equivalence test.** In one database run `addTransaction` + `setTransactionSplits` + `setTransactionTags`; in another run one `saveTransaction` with the same intent. Assert **identical canonical state** — reuse `WriteParityTests.canonicalState`'s table dump so it is the comparison the oracle makes.
- [ ] **Step 2: Run it, record the failure**, then implement until it passes.
- [ ] **Step 3: The same for transfers** — `createTransfer` vs `saveTransaction` with `kind: .transfer`, and `updateTransfer` vs a `saveTransaction` edit.
- [ ] **Step 4: Assert `addTransaction` and `saveTransaction` agree** on the same purchase, including a **mixed-currency split** — they are two doors into one core (Decision 17), so disagreement means the adapter is lying about currency.
- [ ] **Step 5: State the honest limit** in the test's doc comment: this proves equivalence only for shapes the old actions can express. **A grid has no old-action equivalent** and is covered by iOS tests alone until the web catches up.
- [ ] **Step 6:** `ci-local.sh` until `all checks passed`. **Step 7:** Open the PR against `feat/frontend`.

## Out of scope

- **The web UI**, per this plan's scope note. Its *engine* is complete for the shipped shapes; the parity artefacts in Tasks 2 and 11 are the exception and are mandatory.
- **Storing an account×category pairing.**
- **Mixed-currency splits in the editor** — the engine accepts them; the picker renders one currency symbol per sheet. Parked.
- **Changing a split's `kind`.**

## Status at PR time

Shipped in this branch (on top of the merged #717, #719, #722):

- Task 4 — transfers moved onto `saveTransaction`. Both sheets. A transfer's
  cells are the documented exception to Decision 16: each is already in its own
  card's currency, because a transfer has no single purchase currency and the
  user types both numbers. Without the exception a typed 100 EUR was stored as
  90.91 EUR — a different transfer that still balances, so nothing downstream
  would have flagged it.
- Task 9 Steps 1, 2, 5 — the Edit sheet's account editor.
- Task 10 — the glyph, `purchaseKey`, and the message rewrite.
- Task 11 Steps 1-5 — the equivalence proof, including the mixed-currency split.
  The two actions take **different units on purpose** (`addTransaction`: each
  account's own currency; `saveTransaction`: the purchase's), so the test feeds
  each its own contract and asserts one ledger.

Found while executing, not predicted by the plan:

- **A category screen counted the whole purchase under every category it
  touched.** A 100 shop split 70/30 reported 100 on both screens. Predates the
  grid — it fails the same way for an ordinary one-card category split — and the
  grid widened it from one entry to a whole group. Fixed by `categoryShares`,
  which narrows before collapsing. Rows now show the share and resolve back to
  the store before any edit, duplicate or delete.
- **Editing one card of a grid dropped it out of the purchase.** A single-row
  rewrite is indistinguishable from a Decision 20 collapse, so `group_id` was
  cleared and one purchase silently became two — reintroducing the very bug the
  column exists to prevent. The collapse now only applies to a rewrite covering
  the whole purchase.
- **The git-hash build phase had no ordering edge**, so it ran before the plist
  it writes into and silently no-opped. Nondeterministic: back-to-back clean
  builds of the same tree ordered it both ways.

**Not in this branch, and why:**

- **Decision 21's grid reopen (Task 9 Step 3).** Editing any row of a group
  should reopen the whole grid. This is a routing change across every screen that
  opens the Edit sheet — the grid UI lives in the Add flow — not a change to the
  sheet, and it is too large to fold in here. The engine fix above is the floor
  that keeps the ledger honest until it lands: a partial edit is now harmless
  rather than silently destructive.
- **Unlinking receipts when an edit removes a grid row.** Attachments hang off
  the *entry*, so only a grid edit that drops a card can orphan a file — which is
  reachable only through the reopen flow above. It belongs with that work: the
  app layer must read the paths before the write and unlink what no longer
  resolves, as `deleteTransaction` already does.
- **The two-page entry flow.** `PurchaseFlow.page2` decides list/grid/neither and
  is tested; splitting page 1 from page 2 is presentation and is not required for
  correctness.
- **Rules.** Frozen and flagged for its own design review, as agreed.

---

## Verification checklist

- [ ] `ci-local.sh` prints `all checks passed`; catalog churn discarded
- [ ] `group_id` reaches `Tx` — proven by a test that fails without it
- [ ] The parity snapshot does **not** carry `group_id`, deliberately, and `canonicalState` still builds an explicit entry object
- [ ] Reconcile marks drop on an **amount** change and on an **account** change, on both paths — and survive a date, note, merchant or category change
- [ ] Editing a cleared transfer's amount unticks both legs, and `Transfers.swift`'s doc comment says so
- [ ] Saving a merchant change plus an invalid leg set changes **nothing** — proven by a test
- [ ] Tags and legs change in one payload; both land
- [ ] `validateShape` rejects a transfer whose two legs are the same account
- [ ] A grid write is all-or-none, and replays on a peer as one operation
- [ ] Deleting one grid row removes **only that row**; the survivor stays and its `group_id` is cleared
- [ ] Deleting one payment leg of a split-tender purchase removes the whole transaction, **warned first**
- [ ] A row removed by an **edit** has its attachments unlinked; the surviving rows' are untouched
- [ ] A grid rewrite does not collide with its own `dedup_hash`, and preserves entry ids so receipts survive an ordinary edit
- [ ] The grid's payload is asserted **with signs** — the model tests are not evidence
- [ ] `error.split.multiAccount` no longer claims a multi-card purchase takes one category
- [ ] A **grid group** counts as one purchase (the entry level is the prerequisite plan's checklist, not this one's)
- [ ] Every new test verified to fail with its change reverted, output recorded
