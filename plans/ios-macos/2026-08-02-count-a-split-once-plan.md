# Count a Split Purchase Once

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A purchase paid from several accounts counts — and sums — as **one** purchase everywhere, instead of once per payment leg.

**Status:** A **bug fix for shipped behaviour** (#704, #715), not a new feature. Prerequisite for `2026-08-02-edit-a-split-purchase-plan.md`, whose grid adds a second grouping level and must not be built over a broken first level.

**This plan was audited against the codebase and its central premise was found FALSE.** An earlier draft asserted "sums are all correct; do not touch any summing selector." That would have made an implementer revert the correct fix. The audit's findings are folded in below. **Read "Two bugs" before anything else.**

## Two bugs, not one

**Bug A — one purchase becomes N rows.** `Projection` emits **one `Tx` per account-leg posting** (`Projection.swift:14` selects `p.id AS pid`), so a $200 purchase paid $120 + $80 becomes two `Tx` rows, and ~30 places count rows as transactions.

**Bug B — automatic rules break a rule the rest of the app enforces.** The app's stated rule is *"A purchase paid from several accounts takes a single category"* — `setTransactionSplits` refuses to do otherwise in those words (`Transactions.swift:50-53`), and the Add sheet makes the two mutually exclusive by design (`AddTransactionSheet.swift:213-214`).

**A rule's `split` action ignores that** (`Entries.swift:410-427`). It runs at `:401`, *before* `validateShape` at `:436`, which never checks the pairing. So a rule saying "Market is 70% groceries, 30% household" applied to a Market purchase paid on two cards produces a purchase split **both** ways — the shape the app told the user it does not do.

**And then the totals double,** because the projection copies the entry's whole `splits` array onto **every** payment-leg row (`Projection.swift:145-147`). Measured on a $100 purchase (−60 from a2, −40 from a1) with a 70/30 rule: `categorySpend` reports `c1:140, c2:60` for a truth of `70/30`, and `budgetProgress.used` reports `140` for `70`. **A budget alert fires at twice the real spend.**

**The fix is to close the hole, not to make six selectors handle the shape** (Task 3). An earlier draft of this plan proposed the latter; it would have taught the engine to support a shape no screen can produce and one action refuses in writing, and left the inconsistency in place. Once a rule's split is skipped on a multi-card purchase, the shape cannot be written and every selector below is correct as it stands.

**What IS genuinely split-invariant** — verified by reading each: `topMerchants`, `monthlySpending`, `dailySpending`, `monthlyCashflow`, `netWorthByMonth`, `netWorthSeries`, `ledgerNetWorth`, `monthForecast`. They sum `t.amount` by a key and the legs add back to the true total. **These must not change.**

**User-visible damage from Bug A:**

- **Anomaly detection is wrong twice over** — count inflated *and* each leg's magnitude a fraction of the purchase, so mean and standard deviation are distorted rather than rescaled. Drives the **"Unusual transaction" push notification**.
- **Destructive-action confirmations understate.** "N transactions will be combined" dedups by `Set<Tx.id>` — a *posting* id.
- **Subscription detection can miss real subscriptions.** Legs double `occurrences` and mix partial amounts into one mean, which can fail the `std/mean < 0.35` cadence gate.
- **"Largest amount" sort never ranks a split purchase at its true size.**
- **The Watch offers two quick-add shortcuts for one purchase, each writing a partial amount** — `recentExpenses` → `payload.recents` → `PhoneWatchLink.quickAddArgs`, which posts `-abs(item.amount)`. A wrong **write**, not a display choice.

## The root cause, and why nothing can be fixed before Task 1

**`Tx` has no entry-level id.** `Tx.id` is the posting id; `accountLegCount` is a flag, not a join key. `transferGroupId` *is* the entry id but is set only when `kind == "transfer"` (`Projection.swift:154`).

So **a purchase cannot be reconstructed from a `[Tx]` array at all.** Everything below depends on Task 1.

The projection already has it: `e.id AS eid` is selected (`Projection.swift:16`) and `let eid = entryIds[i]` is in scope at `:137`, in the same loop that stamps `accountLegCount` at `:153`.

## Global Constraints

- **No released product.** Breaking changes are cheap; there is no user data to strand.
- **Base branch `feat/frontend`;** isolated worktree off `origin/feat/frontend`.
- **Build with** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and `xcodegen generate`.
- **Gate before every push:** `ios/scripts/ci-local.sh` must print `all checks passed`. It churns `Localizable.xcstrings` — discard unless a genuinely new string was generated. The frontend job is opt-in (`RUN_ALL=1`, `ci-local.sh:229`) — **run it, this plan changes web code.**
- **No `Co-Authored-By` trailer.**
- **Poll for gates** (`pgrep -f ci-local.sh`). Waiting for a harness notification about a process you started never resolves — it stalled a predecessor plan five times.
- **No summing selector changes in this plan.** `topMerchants`, `categorySpend`, `monthlySpending`, `dailySpending`, `monthlyCashflow`, `netWorthByMonth`, `netWorthSeries`, `ledgerNetWorth`, `monthForecast`, `budgetProgress`, `whatIfBaseline` and `incomeCategoryFlow` are all correct **once Task 3 closes the hole**. If one of them changes, something is wrong.
- **An earlier draft had this backwards in both directions** — first claiming every sum was already fine (false: Bug B), then making six of them targets (unnecessary: Task 3 removes the shape). Neither. Fix the cause; leave the sums alone.

## Design decisions (do not relitigate)

1. **`Tx` gains `entryId`, set unconditionally** — every row, not only multi-leg ones. A conditional field forces ~30 call sites to remember a fallback, and the one that forgets is silently wrong rather than broken.

2. **It is `String?`.** An earlier draft justified this by claiming `Tx` crosses to the Watch and widgets — **that is false and is withdrawn**: `WidgetSnapshot` and `WatchSnapshotPayload` carry figures and quick-add items, never `Tx`. Nothing persists `Tx`, so **there is no migration to write and nobody should go looking for one.** The real reason is narrower: the parity fixtures decode `[Tx]` from JSON that lacks the field until regenerated (`ProjectionParityTests.swift:12-19`), and `Store/Domain/Rules.swift:50` decodes `Tx` too.

3. **Two primitives, so no site hand-rolls the fallback.**
   - `Tx.purchaseKey` → `entryId ?? id`. For **counting** distinct purchases. The fallback reproduces today's behaviour rather than crashing.
   - `Selectors.byPurchase(_:)` → one `Tx` per purchase, amounts summed, **splits deduplicated**. For **statistics, ranking and category sums** — everything needing the purchase's true magnitude. This is the single fix for both Bug A and Bug B.

4. **`byPurchase` drops `nativeAmount`.** Split tender is explicitly multi-currency (`MultiAccountAddTests.test_addTransaction_mixedEURandUSDAccounts_validSplit_isAccepted`), and summing raw native amounts across currencies is meaningless — the engine refuses to do it for the same reason (`Entries.swift:385-390`). Consumers read `abs(nativeAmount ?? amount)`, so dropping it makes them fall back to the ledger-base `amount`, which is correct and comparable. **Setting it to a cross-currency sum would make them worse than doing nothing.**

5. **`anomalyScore` is NOT changed.** It takes a single `Tx` (`Selectors.swift:169`) and cannot see sibling legs, so it *cannot* score a purchase. Changing its signature would also change the shared selector-fixture shape on both stacks. **The fix belongs at its two callers** (Task 6).

6. **`transferGroupId` is left alone** — a different question with existing consumers. `entryId` is set for every row including transfers.

7. **The web mirror is worth doing, but NOT because a gate goes red.** An earlier draft claimed fixing iOS alone turns the oracle red. **False.** Selector fixtures are hand-authored static cases (`frontend/lib/select.fixtures.ts:74 CASES`); `merchantStats`'s only case is four single-leg transactions, so the fix produces byte-identical output. The `export-fixtures.ts:505` split feeds **write**-parity, and `WriteParityTests.canonicalState` compares database tables and never runs a selector.

   **The real consequences, both of which this plan must handle:**
   - **Nothing currently gates this fix.** Task 8 adds a split-tender case to `select.fixtures.ts` — without it, net new regression coverage is **zero**.
   - **`ProjectionParityTests` DOES go red at Task 1**, because it compares `[Tx]` against a web-generated `projection.json` that has no `entryId` (`ProjectionParityTests.swift:12-19`). So the web projection change and fixture regeneration must land **in the same commit as Task 1** — see Task 1.

8. **`recentExpenses` EXCLUDES split purchases** — it does not collapse them. An earlier draft left it alone as "arguably a display choice"; a later one collapsed it. Both were wrong.

   It has exactly one consumer: the Watch quick-add templates (`WidgetSnapshot.swift:33`, limit **3**). A shortcut can only write a **single-card** transaction — `quickAddArgs` sends one `accountId` and one `amount` (`PhoneWatchLink.swift:40-51`) — so a two-card purchase cannot be repeated by it at all.

   - **Leaving it** gives two shortcuts, "Market $60" and "Market $40", eating **two of three slots** for one shop and reading like two visits.
   - **Collapsing it** would offer "Market $100" and silently book the whole amount to whichever card came first, quietly corrupting that card's balance — on a watch, where nobody would notice.
   - **So: filter out any row with `accountLegCount > 1`.** The three slots go to things that genuinely repeat in one tap. A split purchase gets added on the phone.

---

## Phase 1 — the join key

### Task 1: `Tx.entryId`, iOS **and** web, in one commit

**This task is atomic across both stacks.** Stamping `entryId` on iOS alone reddens `ProjectionParityTests` and it stays red for the rest of the plan. Do not split this commit.

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Project/Models.swift` — `Tx` gains `entryId` **after `date`** (keeps the memberwise `init` call sites in Task 2 valid), plus the `init` parameter
- Modify: `ios/FinchCore/Sources/FinchCore/Project/Projection.swift:153` — stamp beside `accountLegCount`
- Modify: `frontend/lib/store/transactions/state.ts:18-72` — the `Tx` **interface** gains the field
- Modify: `frontend/lib/db/queries/transactions.ts:100+` — where `accountLegCount`/`transferGroupId` are stamped per entry
- Regenerate: `ios/FinchCore/Tests/ParityTests/Fixtures/projection/projection.json`
- Test: `ios/FinchCore/Tests/FinchCoreTests/`

**Interfaces produced:** `Tx.entryId: String?`, populated on every projected row, both stacks.

- [ ] **Step 1: Write the failing test.**

```swift
func testSplitTenderRowsShareAnEntryId() throws {
    let txs = try Projection.run(dbQueue: q, ledgerId: "personal")
        .filter { $0.merchant == "Furniture" }
    XCTAssertEqual(txs.count, 2, "projection still emits one row per account leg")
    XCTAssertEqual(Set(txs.compactMap(\.entryId)).count, 1, "both legs name the same entry")
    XCTAssertNotNil(txs[0].entryId)
    XCTAssertNotEqual(txs[0].entryId, txs[0].id, "entryId is the entry; id is the posting")
}
```

- [ ] **Step 2: Run it, record the failure.** It first fails to compile; after adding the field but before stamping it, re-run so you also see it fail on the assertion.
- [ ] **Step 3: Add the field**, after `date` in both the stored properties and the `init`:

```swift
    /// The `entries.id` this posting belongs to. Set for EVERY row, so grouping
    /// by it always reconstructs the purchase. `Tx.id` is the POSTING id — a split
    /// purchase has one row per payment leg, and counting rows counts it twice.
    /// Optional because the parity fixtures decode `[Tx]` from JSON written before
    /// this field existed. NOTHING persists `Tx`, so there is no migration.
    /// Prefer `purchaseKey` over reading this directly.
    public var entryId: String?
```

- [ ] **Step 4: Stamp it** in `enrichLegTxs`, immediately above the `accountLegCount` line:

```swift
    rows[i].entryId = eid
    rows[i].accountLegCount = acctCount[eid] ?? 1
```

- [ ] **Step 5: Mirror on the web** — the interface in `state.ts`, the stamp in `queries/transactions.ts`.
- [ ] **Step 6: Regenerate the projection fixture** and confirm `ProjectionParityTests` is green. **If it is red, the web stamp is missing or differs.**
- [ ] **Step 7:** `swift test` + `bun run test`. **Step 8: Commit — one commit, both stacks.**

### Task 2: The two primitives

**Files:** `ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift` (`byPurchase`), `ios/FinchCore/Sources/FinchCore/Project/Models.swift` (`purchaseKey`, beside `Tx`), `SelectorsTests.swift`

**Interfaces produced:** `Tx.purchaseKey: String`, `Selectors.byPurchase(_ txns: [Tx]) -> [Tx]`.

- [ ] **Step 1: Write the failing tests.** Exact numbers — "the count went down" passes for the wrong reason.

```swift
func testPurchaseKeyCollapsesLegsButNotDistinctEntries() {
    let a = Tx(id: "p1", merchant: "X", amount: -120, account: "a1", date: "2026-05-14", entryId: "e1")
    let b = Tx(id: "p2", merchant: "X", amount:  -80, account: "a2", date: "2026-05-14", entryId: "e1")
    let c = Tx(id: "p3", merchant: "X", amount:  -50, account: "a1", date: "2026-05-15", entryId: "e2")
    XCTAssertEqual(Set([a, b, c].map(\.purchaseKey)).count, 2)
}

func testByPurchaseSumsLegs() {
    let a = Tx(id: "p1", merchant: "X", amount: -120, account: "a1", date: "2026-05-14", entryId: "e1")
    let b = Tx(id: "p2", merchant: "X", amount:  -80, account: "a2", date: "2026-05-14", entryId: "e1")
    let out = Selectors.byPurchase([a, b])
    XCTAssertEqual(out.count, 1)
    XCTAssertEqual(out[0].amount, -200, accuracy: 0.001)
}

func testByPurchaseDedupsSplitsInsteadOfConcatenating() {   // Bug B
    let s = [TxSplit(id: "c1p", categoryId: "c1", amount: 70, amountBase: 70, description: nil),
             TxSplit(id: "c2p", categoryId: "c2", amount: 30, amountBase: 30, description: nil)]
    let a = Tx(id: "p1", merchant: "X", amount: -60, account: "a2", date: "2026-05-14", entryId: "e1", splits: s)
    let b = Tx(id: "p2", merchant: "X", amount: -40, account: "a1", date: "2026-05-14", entryId: "e1", splits: s)
    let out = Selectors.byPurchase([a, b])
    XCTAssertEqual(out[0].splits?.count, 2, "the entry's splits appear ONCE, not once per leg")
}

func testByPurchaseDropsNativeAmountAcrossCurrencies() {     // Decision 4
    let a = Tx(id: "p1", merchant: "X", amount: -60, account: "a1", date: "2026-05-14",
               currency: "EUR", nativeAmount: -55, entryId: "e1")
    let b = Tx(id: "p2", merchant: "X", amount: -40, account: "a2", date: "2026-05-14",
               currency: "USD", nativeAmount: -40, entryId: "e1")
    XCTAssertNil(Selectors.byPurchase([a, b])[0].nativeAmount, "EUR + USD is not a number")
}

func testByPurchaseIsIdentityForSingleLegRows() {
    let c = Tx(id: "p3", merchant: "X", amount: -50, account: "a1", date: "2026-05-15", entryId: "e2")
    XCTAssertEqual(Selectors.byPurchase([c]), [c])
}

func testPurchaseKeyFallsBackToPostingIdWhenEntryIdMissing() {
    let old = Tx(id: "p9", merchant: "X", amount: -10, account: "a1", date: "2026-05-15")
    XCTAssertEqual(old.purchaseKey, "p9")
}
```

- [ ] **Step 2: Run, record all six failures.**
- [ ] **Step 3: Implement.**

```swift
public extension Tx {
    /// Groups this row with the other legs of the same purchase. Falls back to the
    /// posting id when `entryId` is absent, reproducing pre-fix behaviour.
    var purchaseKey: String { entryId ?? id }
}

public extension Selectors {
    /// One row per purchase: amounts summed across payment legs, and the entry's
    /// `splits` kept ONCE rather than once per leg (the projection copies the whole
    /// splits array onto every account-leg row — `Projection.swift:145-147`).
    ///
    /// `nativeAmount` and `currency` are dropped when the legs disagree: split tender
    /// is multi-currency and summing raw natives is meaningless. Consumers read
    /// `nativeAmount ?? amount` and so fall back to the comparable base amount.
    ///
    /// Identity fields (`id`, `account`, `clearedAt`, `pending`) are the FIRST leg's.
    /// Do not use this where a specific leg's account or reconcile mark matters.
    /// On a transfer the legs cancel to `amount == 0`; every current caller filters
    /// by `kind` first, but a new one must.
    static func byPurchase(_ txns: [Tx]) -> [Tx] {
        var order: [String] = []
        var acc: [String: Tx] = [:]
        for t in txns {
            let k = t.purchaseKey
            guard var seen = acc[k] else { order.append(k); acc[k] = t; continue }
            seen.amount += t.amount
            if seen.currency != t.currency { seen.currency = nil; seen.nativeAmount = nil }
            else if let a = seen.nativeAmount, let b = t.nativeAmount { seen.nativeAmount = a + b }
            else { seen.nativeAmount = nil }
            acc[k] = seen   // `splits` is the entry's and already correct — never appended
        }
        return order.compactMap { acc[$0] }
    }
}
```

- [ ] **Step 4:** `swift test`. **Step 5: Commit.**

---

## Phase 2 — the engine selectors

Every task below is **"revert the fix, watch the test fail, record it."** These functions return plausible numbers today; a test written after the fix passes against the bug.

### Task 3: Bug B — make rules obey the rule

**Three changes, and the doubling becomes unreachable.**

**Files:**
- Modify: `Entries.swift:410` — skip a rule's `split` action when the entry has ≥2 account legs
- Modify: `Entries.swift:275` `validateShape` — reject ≥2 account legs together with ≥2 plain category legs
- Create: a migration in `Storage/Migrations.swift` (`DatabaseMigrator.registerMigration`) collapsing any existing entry in that shape
- Modify: `MultiAccountRulesTests.swift:9-63` — currently asserts the shape **balances**; must now assert the split is **skipped**. Change it deliberately; do not delete it.
- Mirror all three on the web (`frontend/lib/`), or the stacks diverge on data rather than code

**One place to change, and the pattern already exists.** `patch.splits` is consumed in **exactly one** place — `Entries.swift:410` — so the skip covers every caller: the Add sheet, scheduled postings, everything. And the guard shape is already in the tree: the rule **backfill** does this correctly today, requiring `acctLegCount <= 1` before touching category legs (`Rules.swift:107`, one of the #704 guards). **Copy that.**

**Scheduled postings are already safe** and must stay that way: the scheduled split path posts N account legs against a **single** category via `autoBalance: .category(categoryId)` (`Scheduled.swift:97-110`), and is income-only. It never produces the forbidden shape.

**Skip, do not throw.** `setTransactionSplits` throws because the user asked explicitly. A rule runs by itself, so throwing would refuse a legitimate purchase over an unrelated rule. **The rule's other actions still apply** — merchant, tags, a single category, kind. **Record the rule as applied only if something applied**, or `ruleMatchCounts` claims a match that did nothing.

**The migration is not optional, because of a trap.** `rebuildEntry` re-runs `validateShape` (`:718`, `:724`) — and `:724` validates the **existing** legs even for an edit that touches no legs at all. So without a migration, a transaction already in this shape becomes **uneditable**: no date change, no note change, and an error about leg shapes that does not hint that deleting is the only way out.

**Collapse into the dominant category** — the one with the largest `abs(amount_base)`. That is already the single category the projection displays for such an entry (`Projection.swift:142-144`), so the migration preserves what the user currently *sees* while removing what they cannot see.

- [ ] **Step 1: Write the failing test** using the shape that reaches this in production — a rule with a `split` action on a two-account entry, copied from `MultiAccountRulesTests.swift:9-63`. Assert the entry ends with **one** category leg, and that `categorySpend` and `budgetProgress.used` report the true `70`, not `140`.
- [ ] **Step 2: Write the migration test.** Insert a both-axes entry directly (bypassing the new guard, as the corruption fixtures do), run the migrator, assert one category leg remains and it is the dominant one. **Then assert the entry is editable** — change its note through `rebuildEntry` and confirm it succeeds. That second assertion is the one that proves the trap is closed.
- [ ] **Step 3: Run both, record the failures.** The output showing `140` is the evidence this plan's original premise was wrong — keep it in the commit message.
- [ ] **Step 4: Implement all three changes.**
- [ ] **Step 5:** `swift test`. **Confirm no selector changed** — that is the whole point of fixing the cause rather than six symptoms.
- [ ] **Step 6: Mirror on the web**, migration included.
- [ ] **Step 7: Commit.**

**A known limit, accepted deliberately.** Once the follow-on plan's grid ships, a person **will** be able to split by card and category — as several linked transactions — while a rule still cannot. Accepted: a rule silently restructuring one purchase into several is a large thing to do unasked, and belongs to the separate rules redesign, not to a footnote here.

### Task 4: Bug A — `Selectors.swift`, seven functions

| Function | Line | Fix |
|---|---|---|
| `merchantStats` | 119 | `byPurchase` first — both `n` and the magnitudes are wrong |
| `counterpartyTxCounts` | 184 | Count distinct `purchaseKey` |
| `tagTxCounts` | 239 | Count distinct `purchaseKey` |
| `categoryTxCounts` | 253 | Count distinct `purchaseKey` (its dedup is only *within* one row's splits) |
| `ruleMatchCounts` | 513 | Count distinct `purchaseKey` — `appliedRuleIds` is entry-level, copied to every leg |
| `detectRecurring` | 523 | `byPurchase` first. **Note `accountId: mode(items.map(\.account))` becomes "first leg's account" for a split** — accept and document |
| `anomalyScore` | 169 | **Do NOT change** (Decision 5) — fixed at its callers in Task 6 |

- [ ] **Step 1: One failing test per function.** For `merchantStats` assert the exact pair `count == 1, mean == 200`. For `detectRecurring` assert a **split subscription is still detected** — the case where the bug hides a real result instead of inflating one.
- [ ] **Step 2: Run, record all six failures. Step 3: Implement.**
- [ ] **Step 4:** `swift test`, then **revert `byPurchase` to `{ $0 }` and confirm all six fail again**, proving they test the fix and not each other. **Step 5: Commit.**

### Task 5: Bug A — the insight and digest functions, **three files**

An earlier census placed all of these in `Insights.swift`; `pendingInsight` is not there at all.

| Site | File:line | Fix |
|---|---|---|
| `weeklyDigest` `txCount` | `Insights.swift:218`, counter `:229`, `+= 1` `:250` | Count distinct `purchaseKey` |
| `weeklyDigest` `biggest` | `Insights.swift:218` | `byPurchase` first |
| `suggestCategory` | `Insights.swift:188`, increments `:201-205` | **`byPurchase` first, keeping the per-split loop.** Not "count distinct `purchaseKey`" — the increments are per-*split* inside a row, so that phrasing does not map onto the loop. Confidence semantics shift; assert the new value explicitly |
| `pendingInsight` | **`InsightRules.swift:80-87`**, `pend.count` `:85` | Count distinct `purchaseKey` |
| `quietestDayInsight` | **`InsightRules.swift:246-256`** | `counts[dow] += 1` per leg; the "≥ 25 expense rows" gate trips early |
| `findDuplicate` | `Insights.swift:164-183` | Match on the **purchase total**, and treat the draft's card as matching if it was **any** of the paying cards — see below |
| `recentExpenses` | `Insights.swift:137-160` | **Filter out `accountLegCount > 1`** (Decision 8) — do NOT collapse. It feeds a **write** path that can only express one card |

**`findDuplicate` needs more than `byPurchase`, and here is why.** It filters `t.account != draft.accountId` (`:172`) — a split purchase has no single account, and `byPurchase` keeps only the *first* leg's. So group locally: for each `purchaseKey` keep the summed amount, **the set of paying accounts**, and the first row's merchant/date/id. Then:
- compare the draft's amount against the **purchase total** (using `byPurchase`'s currency rule — sum natives when the legs agree, otherwise fall back to base, since a mixed-currency native sum is meaningless)
- match the card if `draft.accountId` is **in** that set, not equal to one representative
- apply `excludeId` by **`purchaseKey`**, or editing one leg of a split makes the sheet warn about itself
- return the first leg's id in `DuplicateMatch`, which resolves to the purchase

- [ ] **Step 1: Seven failing tests.** `weeklyDigest.biggest` needs the adversarial case: a $200 split $120/$80 against an unsplit $150 — before the fix the $150 wins. `recentExpenses` asserts a split purchase produces **no** shortcut at all — not one of $100, and not two of $60 and $40. `findDuplicate` needs three: adding $100 Market **warns** when a $60+$40 Market purchase exists; adding $60 Market does **not** warn (it is not the same purchase); and editing one leg of that purchase does **not** warn about itself.
- [ ] **Step 2: Run, record. Step 3: Implement across both files. Step 4:** `swift test`. **Step 5: Commit.**

---

## Phase 3 — the surfaces

### Task 6: Anomaly, at the callers

Per Decision 5, `anomalyScore` keeps its single-`Tx` signature. Both callers must feed it purchases:

- `NotificationPlanner.swift:78-88` — iterates legs, emits one notification per leg keyed `"anomaly:\(t.id)"` (a posting id) and prints `money(t.amount)` (a leg amount). **Not fixed transitively.** Iterate `byPurchase(txns)` and key on `purchaseKey`.
- `FinchStore+ViewHelpers.swift:197-200` `isAnomaly(_ tx:)` — the per-row feed badge, scored on a leg.

**Performance:** `isAnomaly` is called per row per render. Calling `byPurchase` inside it is O(n) per row over the whole ledger. **Cache the collapsed array beside `merchantStatsCache` and invalidate it at the same place (`FinchStore.swift:400`).**

- [ ] **Step 1-5:** Failing tests (assert one notification per split purchase, at the full amount), record, implement, `swift test`, commit.

### Task 7: The Categories / Tags / Merchants surface

**Two bugs, heavily copy-pasted. Fix the shape, not eighteen things eighteen ways.**

**Bug A1 — `Set<Tx.id>` merge-impact dedup** in destructive-action confirmation text. Twelve functions across six files: `CategoriesView.swift:445,460`, `TagsView.swift:231,244`, `MerchantsView.swift:208,214`, `CategoriesVC.swift:479,486`, `TagsVC.swift:310,317`, `MerchantsVC.swift:314,323`. Change `.map(\.id)` → `.map(\.purchaseKey)`.

**Bug A2 — `txns.count` and `total / count`** in detail views: `CategoryDetailView.swift:32,35`, `CounterpartyDetailView.swift:29,32`, `TagDetailView.swift:31,34`, `TxListDetailVC.swift:147,152-154,199`.

**Pending counts — the same class, and the plan must fix all of them or none:** `ActivityTab.swift:411` (rendered `:142`), `:137`, `CategoryDetailView.swift:39`, `TagDetailView.swift:38`, `CounterpartyDetailView.swift:36`, `TxListDetailVC.swift:213`, `ActivityFeedVC.swift:500`, `AccountDetailVC.swift:466`, `AccountDetailView.swift:246`, `ReconcileSheet.swift:179`.

**Do NOT fix `deleteImpactMessage` call sites** (`CategoriesView.swift:170`, `TagsView.swift:102`, `MerchantsView.swift:85`, UIKit twins) — they read `counts[...]` from Task 4's selectors and are fixed transitively. **Assert that; do not edit them.**

**The lists collapse too — one row per purchase.** Fixing only the count would print "1 transaction" above a 2-row list, contradicting itself on one screen. So these views run their rows through `byPurchase` as well: a $100 purchase paid on two cards is **one $100 row**, and the count, total and average all agree with it.

**The reasoning, so it is applied consistently:** a category / merchant / tag screen answers *"what did I spend on groceries"* — one $100 shop, not two half-shops. Which card paid is not the question there. **An account's own screen is the opposite** and must NOT collapse: it shows what hit that card, it only ever sees its own leg anyway, and its counts are already correct (`ReconcileState.swift:31`, `AccountDetailView`, `AccountDetailVC`).

**Two consequences to handle:**
- **Tapping a collapsed row must open the purchase.** `byPurchase` keeps the *first* leg's `id`, and the detail sheet resolves the entry from any posting, so this works — but assert it, because the row the user taps is no longer the row they see.
- **The "To confirm" sections on these three screens collapse too** (`CategoryDetailView.swift:39`, `TagDetailView.swift:38`, `CounterpartyDetailView.swift:36`). `ReconcileSheet.swift:179` and `AccountDetailView.swift:246` are account-scoped and stay per-leg.

**A known cost, accepted:** splitting an existing purchase makes it stop showing as two familiar rows here and start showing as one. To someone thinking in payments that reads as something going missing. The account screens still show each payment, which is where that expectation belongs.

- [ ] **Step 1: Write the confirmation-text test first** — the one that misleads someone into a destructive action. A category holding one split purchase must report **"1 transaction"**.
- [ ] **Step 2: Run, record. Step 3: Implement. Step 4:** `swift test` + build both UI targets. **Step 5: Commit.**

### Task 8: Sort, Watch, and the delete dialog

- **`TxSort.amountDesc` / `.amountAsc`** — the enum is `ActivityTab.swift:19-20`, but it is **applied** at `ActivityTab.swift:305`, `:535` and `ActivityFeedVC.swift:431`, `:442`. `:582` is only the sort *menu* — **editing it does nothing.** Rank on the purchase total.
- **`QuickAddCatalog.swift:27`** `categoryUse` — `+= 1` per leg. **Leave `accountUse` (`:26`) alone**: a split purchase genuinely uses both accounts.
- **`ActivityTab.swift:343-347`** — "Delete N transaction(s)?" over `selected`, which holds posting ids.

  **The feed itself keeps one row per payment** — it is the list you check against a statement, and a statement shows payments. It is also the only place left that shows *how* something was paid, now that the category screens collapse. The existing linked-rows badge is what keeps that legible.

  **So the dialog must speak in purchases while the list speaks in payments.** Count distinct `purchaseKey`, not selected rows, and warn when the selection covers only part of a purchase:
  - both payments selected → "Delete 1 transaction?" — one purchase goes
  - one payment selected → "Delete 1 transaction? This also removes the other payment." Today it says "Delete 1 transaction?" and silently removes both, which is the dangerous case.

- [ ] **Step 1-5:** Failing tests, record, implement, `swift test`, commit.

---

## Phase 4 — make it stay fixed

### Task 9: A fixture that would catch this again

**Without this task, the fix has zero regression coverage.** The selector fixtures are hand-authored (`frontend/lib/select.fixtures.ts:74 CASES`) and every existing case is single-leg, so after the fix they produce byte-identical output.

- [ ] **Step 1: Add a split-tender case to `CASES`** for `merchantStats`, `weeklyDigest` and `suggestCategory` — two `Tx` rows sharing one `entryId`, plus a both-axes case carrying the same `splits` array on both rows for `categorySpend` (Bug B).
- [ ] **Step 2: Mirror the four selector fixes on the web** — `select.ts:854` `merchantStats`, `:640` `weeklyDigest`, `:959` `suggestCategory`, `:100-107` `categorySpend`. (`anomalyScore` at `:896` is unchanged, per Decision 5.)
- [ ] **Step 3: Regenerate selector fixtures.** The diff is the new cases only; existing cases must be **unchanged**.
- [ ] **Step 4:** `SelectorParityTests` green — both stacks independently produce the corrected numbers.
- [ ] **Step 5: Commit.**

### Task 10: Gate and PR

- [ ] **Step 1:** `ci-local.sh` with `RUN_ALL=1` until it prints `all checks passed`.
- [ ] **Step 2:** Confirm `ProjectionParityTests`, `SelectorParityTests` and `WriteParityTests` are all green. **`WriteParityTests` should be untouched** — it compares database tables and never runs a selector; a diff there means something wrote to the ledger that shouldn't have.
- [ ] **Step 3:** Open the PR against `feat/frontend`.

---

## Out of scope

- **`transferGroupId`** — a different question with existing consumers (Decision 6).
- **The eight split-invariant selectors** — already correct, and the pattern being copied.
- **`findDuplicate`** (`Insights.swift:164`) — **considered and deferred.** It matches a draft's amount against `abs(t.nativeAmount ?? t.amount)` within one account (`:172-178`), so re-adding a $200 purchase stored as $120 + $80 finds no match and the duplicate nudge never fires. Real, but it needs a product decision — what "duplicate" means when the existing purchase spans accounts the draft doesn't name — and it degrades to a *missing soft warning*, not a wrong number. Recorded so it is not rediscovered as new.
- **The grid's second grouping level** — the follow-on plan. Two notes for it:
  - It must fold `group_id` into `purchaseKey`, or a grid group counts as N purchases and reintroduces exactly this bug.
  - **`byPurchase` is NOT enough for a grid on a category screen.** It sums each row's account-leg `amount`, which for a grid group is the whole purchase — but a category screen wants only that category's share of it. Collapsing by entry is safe *here* only because split tender has a single category (Task 3 now guarantees that). A grid's rows are category-split, so the follow-on plan needs a collapse that sums the matching **splits**, not the account legs.

## Verification checklist

- [ ] `ci-local.sh` (with `RUN_ALL=1`) prints `all checks passed`; catalog churn discarded
- [ ] Task 1 landed as **one commit across both stacks**; `ProjectionParityTests` never left green
- [ ] Both legs of a split share an `entryId`, and it differs from `Tx.id`
- [ ] `byPurchase` keeps the entry's `splits` **once**, is the identity on single-leg rows, and **drops `nativeAmount` when currencies differ**
- [ ] A split rule applied to a multi-card purchase leaves **one** category leg — its other actions still apply
- [ ] `categorySpend` reports `70/30` and **`budgetProgress.used` reports 70, not 140** — reached by removing the shape, not by changing either selector
- [ ] `validateShape` rejects an entry with 2+ account legs and 2+ category legs
- [ ] `MultiAccountRulesTests` was updated deliberately, not deleted
- [ ] An entry already in the forbidden shape is migrated **and is still editable afterwards**
- [ ] Reverting `byPurchase` to `{ $0 }` makes every Task 4 test fail
- [ ] "N transactions will be combined" reports 1 for a single split purchase
- [ ] A split subscription is still detected by `detectRecurring`
- [ ] "Biggest expense" picks a split $200 over an unsplit $150
- [ ] The Watch offers **no** quick-add for a split purchase, and its three slots go to repeatable ones
- [ ] Re-adding a $100 purchase that was paid $60 + $40 **does** warn; editing one of its legs does not warn about itself
- [ ] One anomaly notification per split purchase, at the full amount
- [ ] Detail views do not print "1 transaction" above a 2-row list
- [ ] **No summing selector changed at all**
- [ ] `SelectorParityTests` green, **with new split-tender cases** — existing cases unchanged
- [ ] Every new test verified to fail with its change reverted, output recorded
