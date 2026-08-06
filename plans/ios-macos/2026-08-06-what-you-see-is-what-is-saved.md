# What You See Is What Is Saved — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop `saveTransaction` recording figures the user never typed — the foreign-currency amount it silently converts away, and the split amount it silently ignores.

**Architecture:** Two live bugs, one cause: the sheet shows one number and the ledger stores another. The engine gains `orig_amount`/`orig_currency` on every leg it writes (the pair the app already *displays* from), the projection carries the per-cell copy through to `TxSplit`, and both sheets refuse to save while the cells and the stated total disagree.

**Tech Stack:** Swift 5.9 / SwiftUI / GRDB (SQLite), XCTest. iOS package `ios/FinchCore` (engine + projection) and app target `ios/FinchApp`.

## Global Constraints

- **Branch:** `fix/typed-amounts`, cut from `origin/feat/frontend`. PRs target `feat/frontend`, never `main`.
- **No `Co-Authored-By` trailer in commits.**
- **Nothing is released.** Breaking changes and schema migrations are acceptable; no backfill of existing rows is required or possible.
- **iOS only.** Do NOT modify anything under `frontend/`. The web has no `saveTransaction` and no grid; the resulting divergence in `TxSplit` is a deliberate, user-approved decision and must be recorded in a code comment where the field is defined.
- **Do not regenerate the parity fixture.** `ios/FinchCore/Tests/ParityTests/` artefacts stay byte-identical.
- **Build:** `xcodebuild` needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` **and** `PATH="$DEVELOPER_DIR/usr/bin:$PATH"` (a teardown subprocess calls `simctl` and will fail `TEST FAILED` after all tests pass without the PATH entry).
- **Simulator:** this session's sim is `ios-finch-splits`. Never touch a sim with another name — parallel sessions own those.
- **New user-facing strings are forbidden in this plan.** Every message reused here already exists in `Localizable.xcstrings`. Adding a key requires committing the catalog, and the i18n guard diffs against HEAD.
- **`I18nError` codes localize in `ios/FinchApp/Sources/FinchShared/Common/ErrorL10n.swift`**, NOT in `zh-manual.json`, where they are a silent no-op.
- After any `xcodebuild` run, discard catalog churn before committing:
  `git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings`

---

## Background: the two bugs, and why the tests missed them

### Bug 1 — the typed foreign amount is thrown away

`Projection.swift:81` is what the whole app displays:

```swift
currency: origCcy ?? pCcy, nativeAmount: origAmount ?? pAmount,
```

`orig_amount`/`orig_currency` mean *"what the user typed, and in what currency"*. `addTransaction` fills them (`Transactions.swift:351-363`), and does so **only when the entered currency differs from the account's**:

```swift
let inputCcy = a.currency ?? acctCcy
if inputCcy != acctCcy {
    ... origAmount: a.amount, origCurrency: inputCcy ...
}
```

`saveTransaction` never fills them at all. Verified on this base:

| action | recorded | app shows |
|---|---|---|
| `addTransaction` | `orig = −100 EUR`, posting `−110 USD` | **€100** |
| `saveTransaction` | `orig = nil`, posting `−110 USD` | **$110** |

Both sheets moved to `saveTransaction` in already-merged work, so this is live for anyone spending abroad.

**Why `SaveTransactionEquivalenceTests` missed it:** its `canonical()` compares
`account_id|category_id|amount|currency|amount_base|memo` and never reads
`orig_*`. "Identical ledger" was measured on the columns that happened to agree.

### Bug 2 — changing a split's amount saves the old figure

In `EditTransactionSheet.swift`:

- `accountAlloc.setTotal(...)` is called **only in `.onAppear`** (`:421`). Nothing re-totals it when the amount changes.
- `splitAlloc.setTotal(...)` *is* called on change (`:399-401`), but its rows are seeded **pinned** by `SplitAllocation.merging`, and `redistribute()` returns early when every row is pinned — so no amount moves.

Either way `save()` sends `alloc.payload`, which still holds the old per-row
figures. Type 120 over a 100 split, tap ✓, and 100 is saved with no complaint.

`SplitAllocation` already computes exactly the right diagnosis —
`problem == .sumMismatch` — but only the *picker sheets* consult it
(`SearchablePickerRow.swift:242`, `CategoryPickerRow.swift:171`). The main
sheet's ✓ never does.

### The decisions this plan implements (settled, do not relitigate)

1. **The Amount field is the target.** Cells must reach it; ✓ is refused otherwise. The alternative (grid wins, amount derives) was rejected: a mistyped cell would silently change the purchase total.
2. **Per-cell fidelity.** Category legs carry `orig_*` too, so a foreign-currency grid can later reopen showing the exact figures typed rather than back-converted ones.
3. **A new named field, not a redefinition.** `TxSplit.amount` keeps meaning *ledger base*. Redefining it would change a field under three live consumers (`Selectors.swift:319` `categoryShares`, `Transactions.swift:75` split-sum guard, `EditTransactionSheet.swift:101` split seeding); a new field touches none of them.
4. **iOS only; accept the divergence.** The web keeps reading `amountBase`. Nothing breaks today — it has no grid — but the field will mean subtly different things per stack, unguarded, until the web catches up. Say so in a comment.
5. **Transfers are exempt.** A transfer's cells are already in each card's own currency (`SaveTransaction.swift:308`), so there is no "as typed in another currency" figure to record. Leave `orig_*` nil, which is precisely what "not a foreign-currency entry" means.

---

## File structure

| File | Responsibility after this plan |
|---|---|
| `ios/FinchCore/Sources/FinchCore/Store/Entries.swift` | `CategoryLeg` gains `origAmount`/`origCurrency`; `categoryLeg()` forwards them. `AccountLeg` already has the pair — no change. `insertPostings` already writes both columns — no change. |
| `ios/FinchCore/Sources/FinchCore/Store/Domain/SaveTransaction.swift` | `buildLegs` records what was typed, on account legs and per cell. |
| `ios/FinchCore/Sources/FinchCore/Project/Projection.swift` | The private `Leg` struct, its query, and the `TxSplit` construction carry `orig_*` through. |
| `ios/FinchCore/Sources/FinchCore/Project/Models.swift` | `TxSplit` gains `origAmount`/`origCurrency`, with the divergence note. |
| `ios/FinchCore/Tests/FinchCoreTests/SaveTransactionEquivalenceTests.swift` | `canonical()` compares `orig_*` on account legs, closing the hole that hid this. |
| `ios/FinchCore/Tests/FinchCoreTests/TypedAmountTests.swift` (new) | Per-cell recording and its projection — the shapes the old actions cannot express. |
| `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/EditTransactionSheet.swift` | Amount changes reach both allocations; ✓ refuses a mismatch. |
| `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/AddTransactionSheet.swift` | ✓ refuses a mismatch, including the grid. |
| `ios/FinchApp/Tests/FinchAppTests/SplitSaveGateTests.swift` (new) | The gate's arithmetic, tested without a view. |

---

## Task 1: The guard that should have caught this

Extends the equivalence oracle to compare the columns it was blind to, and adds
the foreign-currency case. **This task ends RED on purpose** — it proves the
regression before anything is fixed. Task 2 turns it green.

**Files:**
- Modify: `ios/FinchCore/Tests/FinchCoreTests/SaveTransactionEquivalenceTests.swift` — `canonical()` at `:41-64`; new test appended before the closing `}`

**Interfaces:**
- Consumes: nothing.
- Produces: `canonical(_ q: DatabaseQueue) throws -> String` now includes `orig_amount`/`orig_currency` for account legs. Later tasks rely on this comparison staying account-only.

- [ ] **Step 1: Widen `canonical()`.** Replace the `legs` block inside `canonical` with:

```swift
                let legs = try Row.fetchAll(db, sql: """
                    SELECT account_id, category_id, ROUND(amount,2) AS a, currency,
                           ROUND(amount_base,2) AS ab, memo,
                           ROUND(orig_amount,2) AS oa, orig_currency AS oc
                      FROM postings WHERE entry_id = ?
                     ORDER BY COALESCE(account_id,''), COALESCE(category_id,''), ab
                    """, arguments: [eid])
                    .map { r -> String in
                        let acct = r["account_id"] as String? ?? ""
                        // orig_amount/orig_currency — what the user TYPED, and the pair
                        // `Projection.swift:81` displays from. Compared on the ACCOUNT leg
                        // only: that is the one the old actions also fill, so it is the one
                        // where a difference means a real disagreement.
                        //
                        // Category legs carry a per-cell copy that `addTransaction` has no
                        // concept of — it writes one auto-balanced category leg, and a grid
                        // has no old-action equivalent at all. Comparing it here would
                        // assert a difference that is by design. `TypedAmountTests` covers
                        // that side instead.
                        let orig = acct.isEmpty ? "" : "\(r["oa"] as Double? ?? 0)|\(r["oc"] as String? ?? "")"
                        return "\(acct)|\(r["category_id"] as String? ?? "")|\(r["a"] as Double)"
                             + "|\(r["currency"] as String? ?? "")|\(r["ab"] as Double)"
                             + "|\(r["memo"] as String? ?? "")|\(orig)"
                    }
```

- [ ] **Step 2: Add the foreign-currency equivalence test.** Append inside the class, immediately before its closing brace:

```swift
    /// A foreign-currency purchase: €100 paid with a USD card, ledger base USD.
    ///
    /// The figure the app DISPLAYS is `orig_amount ?? amount`
    /// (`Projection.swift:81`), so an action that does not record the pair shows
    /// the converted $110 where the user typed €100 — and the €100 is gone, not
    /// recoverable from anything else in the row.
    func test_matchesAddTransaction_forAForeignCurrencyPurchase() throws {
        let old = try seed(), new = try seed()
        for q in [old, new] {
            try q.write { db in
                try db.execute(sql: "INSERT INTO exchange_rates (date,currency,rate) VALUES ('2026-06-01','EUR',1.10)")
            }
        }

        try Apply.apply(dbQueue: old, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-100),
            "currency": .string("EUR"), "merchant": .string("Market"), "categoryId": .string("c1"),
            "date": .string("2026-06-01"), "time": .string("12:00"), "skipRules": .bool(true),
        ]))
        try Apply.apply(dbQueue: new, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "merchant": .string("Market"),
            "date": .string("2026-06-01"), "time": .string("12:00"),
            "kind": .string("expense"), "currency": .string("EUR"), "skipRules": .bool(true),
            "cells": .array([.object([
                "accountId": .string("a1"), "categoryId": .string("c1"), "amount": .double(-100),
            ])]),
        ]))
        XCTAssertEqual(try canonical(new), try canonical(old))
    }
```

- [ ] **Step 3: Run it and record the failure.**

Run:
```bash
cd ios/FinchCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter SaveTransactionEquivalenceTests
```
Expected: `test_matchesAddTransaction_forAForeignCurrencyPurchase` FAILS. The
diff shows `|-100.0|EUR` on the `addTransaction` side and `|0.0|` on the
`saveTransaction` side. **The other five tests in the class must still pass** —
they are same-currency, so `orig_*` is nil on both sides. If any of them fails,
stop: `canonical()` has been widened incorrectly.

- [ ] **Step 4: Commit the red test.**

```bash
git add ios/FinchCore/Tests/FinchCoreTests/SaveTransactionEquivalenceTests.swift
git commit -m "test: the equivalence oracle compares what the user typed

canonical() compared account_id|category_id|amount|currency|amount_base|memo
and never orig_amount/orig_currency — so \"identical ledger\" was measured on
the columns that happened to agree, and a currency regression walked straight
through it.

Fails as committed. saveTransaction records no typed amount, so a EUR purchase
comes back as its USD conversion."
```

---

## Task 2: The account leg records what was typed

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Domain/SaveTransaction.swift` — `buildLegs`, the `.account` leg at `:321-325`

**Interfaces:**
- Consumes: `canonical()` from Task 1.
- Produces: `Entries.AccountLeg.origAmount` / `.origCurrency` populated by `saveTransaction`. `AccountLeg` already declares both (`Entries.swift:64-65`) and `insertPostings` already writes both columns (`Entries.swift:377-381`) — no change is needed in either.

- [ ] **Step 1: Record the pair on the account leg.** In `buildLegs`, replace the `legs.append(.account(...))` call with:

```swift
            // What the user TYPED, when that is not already what the leg says.
            // `Projection.swift:81` displays `orig_amount ?? amount`, so without
            // this a €100 purchase on a USD card comes back as $110 — and the €100
            // is gone, recoverable from nothing else in the row.
            //
            // Only when the currencies differ, mirroring `addTransaction`
            // (`Transactions.swift:350`): on a same-currency purchase the pair
            // would just duplicate `amount`, and a nil is what "not a
            // foreign-currency entry" means everywhere else in the schema.
            //
            // A transfer never qualifies: `cellCcy` IS `acctCcy` above, because a
            // transfer's two sides are each typed in their own card's currency.
            let typedInAnotherCurrency = cellCcy != acctCcy
            legs.append(.account(Entries.AccountLeg(
                accountId: accountId, amount: native,
                amountBase: Entries.r2(conv.amountBase), exchangeRate: conv.rate,
                memo: prior?["memo"] ?? transferMemos[accountId], id: prior?["id"],
                origAmount: typedInAnotherCurrency ? Entries.r2(amount) : nil,
                origCurrency: typedInAnotherCurrency ? cellCcy : nil,
                clearedAt: sameAmount ? prior?["cleared_at"] : nil)))
```

- [ ] **Step 2: Run Task 1's test — it must now pass.**

Run:
```bash
cd ios/FinchCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter SaveTransactionEquivalenceTests
```
Expected: all six PASS.

- [ ] **Step 3: Run the whole engine suite.**

Run:
```bash
cd ios/FinchCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```
Expected: 0 failures. Pay attention to `WriteParityTests`, `ProjectionParityTests`
and `AuditParityTests` — none should move, because every parity shape is
same-currency and therefore still writes nil.

- [ ] **Step 4: Commit.**

```bash
git add ios/FinchCore/Sources/FinchCore/Store/Domain/SaveTransaction.swift
git commit -m "fix: a foreign-currency purchase remembers what you paid

Projection displays orig_amount ?? amount, and saveTransaction wrote neither.
A EUR100 purchase on a USD card displayed as USD110 — the conversion, not the
price — and the EUR100 was unrecoverable from the row.

Recorded only when the entered currency differs from the card's, mirroring
addTransaction. A transfer never qualifies: its cells are already in each
card's own currency."
```

---

## Task 3: Every cell records what was typed

Per-cell fidelity, so a foreign-currency grid can later reopen with the exact
figures typed. Category legs are stored in **ledger base**, so the typed figure
differs from what is stored whenever the purchase currency is not the base.

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Entries.swift` — `CategoryLeg` at `:75-83`; `categoryLeg()` at `:152-156`
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Domain/SaveTransaction.swift` — the category-leg loop in `buildLegs` at `:341-344`
- Modify: `ios/FinchCore/Sources/FinchCore/Project/Models.swift` — `TxSplit` at `:94-100`
- Modify: `ios/FinchCore/Sources/FinchCore/Project/Projection.swift` — `Leg` at `:92`, its query at `:100-111`, the `TxSplit` construction at `:146-148`
- Test: `ios/FinchCore/Tests/FinchCoreTests/TypedAmountTests.swift` (new)

**Interfaces:**
- Consumes: Task 2's `typedInAnotherCurrency` pattern (same rule, different comparison — base rather than account currency).
- Produces:
  - `Entries.CategoryLeg(categoryId:amountBase:memo:id:origAmount:origCurrency:)`
  - `TxSplit.origAmount: Double?`, `TxSplit.origCurrency: String?`
  - **Sign convention:** a category leg's `amountBase` is stored NEGATED relative to its cell (`buildLegs` writes `-b`), and `Projection.swift:147` negates it back. `origAmount` is stored with the SAME negation and restored the same way, so the two always travel together.

- [ ] **Step 1: Write the failing test.** Create `ios/FinchCore/Tests/FinchCoreTests/TypedAmountTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

/// What the user typed, kept per cell.
///
/// A category leg is stored in the LEDGER BASE, so on a foreign-currency
/// purchase the stored figure is not the one that was entered. Keeping the typed
/// figure alongside it is what lets a grid reopen showing the numbers the user
/// actually wrote rather than back-converted ones — which drift by a cent on
/// awkward rates, and would be baked in as the new truth on the next save.
///
/// This is deliberately NOT part of the equivalence oracle: `addTransaction`
/// writes one auto-balanced category leg and has no per-cell concept, so there
/// is nothing to be equivalent to.
final class TypedAmountTests: XCTestCase {

    /// Base USD, one USD card, rate 1 EUR = 1.10 USD.
    private func seed() throws -> DatabaseQueue {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Card','credit_card','USD',0,1,1,1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at)
                VALUES ('c2','l1',NULL,'Household','expense',1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: "INSERT INTO exchange_rates (date,currency,rate) VALUES ('2026-06-01','EUR',1.10)")
        }
        return q
    }

    /// A €100 purchase split €70 / €30 across two categories, on a USD card.
    /// Each category leg must remember its own typed figure, not just the
    /// converted $77 / $33.
    func test_eachCellRemembersTheAmountAsTyped() throws {
        let q = try seed()
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "merchant": .string("Market"),
            "date": .string("2026-06-01"), "kind": .string("expense"),
            "currency": .string("EUR"), "skipRules": .bool(true),
            "cells": .array([
                .object(["accountId": .string("a1"), "categoryId": .string("c1"), "amount": .double(-70)]),
                .object(["accountId": .string("a1"), "categoryId": .string("c2"), "amount": .double(-30)]),
            ]),
        ]))

        let byCategory = try q.read { db in
            try Row.fetchAll(db, sql: """
                SELECT category_id, ROUND(orig_amount,2) AS oa, orig_currency AS oc
                  FROM postings WHERE category_id IS NOT NULL ORDER BY category_id
                """).reduce(into: [String: (Double?, String?)]()) {
                    $0[$1["category_id"]] = ($1["oa"], $1["oc"])
                }
        }
        // Stored with the same negation the category leg's amount_base carries,
        // so the projection's existing flip restores both together.
        XCTAssertEqual(byCategory["c1"]?.0, 70, "the €70 the user typed")
        XCTAssertEqual(byCategory["c1"]?.1, "EUR")
        XCTAssertEqual(byCategory["c2"]?.0, 30, "the €30 the user typed")
        XCTAssertEqual(byCategory["c2"]?.1, "EUR")
    }

    /// And it survives the trip back out, sign-corrected like `amount` is.
    func test_theTypedAmountReachesTheProjectedSplits() throws {
        let q = try seed()
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "merchant": .string("Market"),
            "date": .string("2026-06-01"), "kind": .string("expense"),
            "currency": .string("EUR"), "skipRules": .bool(true),
            "cells": .array([
                .object(["accountId": .string("a1"), "categoryId": .string("c1"), "amount": .double(-70)]),
                .object(["accountId": .string("a1"), "categoryId": .string("c2"), "amount": .double(-30)]),
            ]),
        ]))

        // `Projection.run` returns `[Tx]` directly — there is no wrapper type.
        let txns = try Projection.run(dbQueue: q, ledgerId: "l1")
        let tx = txns.first { $0.splits?.isEmpty == false }
        let splits = try XCTUnwrap(tx?.splits)
        let c1 = try XCTUnwrap(splits.first { $0.categoryId == "c1" })
        XCTAssertEqual(c1.origAmount ?? 0, -70, accuracy: 0.001, "signed like `amount`, and in euros")
        XCTAssertEqual(c1.origCurrency, "EUR")
        XCTAssertEqual(c1.amountBase, -77, accuracy: 0.001, "the base figure is unchanged by any of this")
    }

    /// A same-currency purchase records nothing: the pair would only duplicate
    /// what is already stored, and nil is what "not a foreign entry" means.
    func test_aSameCurrencyPurchaseRecordsNoTypedCopy() throws {
        let q = try seed()
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "merchant": .string("Market"),
            "date": .string("2026-06-01"), "kind": .string("expense"),
            "currency": .string("USD"), "skipRules": .bool(true),
            "cells": .array([
                .object(["accountId": .string("a1"), "categoryId": .string("c1"), "amount": .double(-70)]),
                .object(["accountId": .string("a1"), "categoryId": .string("c2"), "amount": .double(-30)]),
            ]),
        ]))
        let anyOrig = try q.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE orig_amount IS NOT NULL") ?? -1
        }
        XCTAssertEqual(anyOrig, 0)
    }
}
```

- [ ] **Step 2: Run it and record the failure.**

Run:
```bash
cd ios/FinchCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter TypedAmountTests
```
Expected: `test_eachCellRemembersTheAmountAsTyped` and
`test_theTypedAmountReachesTheProjectedSplits` FAIL (nil where a number is
expected; `origAmount` will not even compile until Step 4). The
same-currency test passes.

- [ ] **Step 3: Give `CategoryLeg` the pair.** In `Entries.swift`, replace the `CategoryLeg` struct:

```swift
    public struct CategoryLeg: Sendable {
        public var categoryId: String?
        public var amountBase: Double      // signed, ledger base
        public var memo: String?
        public var id: String?
        public var origAmount: Double?     // foreign-currency entry: this cell as entered
        public var origCurrency: String?   // …and the currency it was entered in
        public init(categoryId: String?, amountBase: Double, memo: String? = nil, id: String? = nil,
                    origAmount: Double? = nil, origCurrency: String? = nil) {
            self.categoryId = categoryId; self.amountBase = amountBase; self.memo = memo; self.id = id
            self.origAmount = origAmount; self.origCurrency = origCurrency
        }
    }
```

and widen the private builder so the pair reaches the row:

```swift
    private static func categoryLeg(_ id: String?, _ categoryId: String?, _ amountBase: Double,
                                    _ base: String, _ memo: String?,
                                    _ origAmount: Double? = nil, _ origCurrency: String? = nil) -> ResolvedLeg {
        ResolvedLeg(id: id ?? newId("p"), accountId: nil, categoryId: categoryId,
                    amount: amountBase, currency: base, amountBase: amountBase, exchangeRate: 1,
                    memo: memo, origAmount: origAmount, origCurrency: origCurrency)
    }
```

Then, in the `case .category(let c):` arm of the leg resolver (`Entries.swift:250`), forward them:

```swift
                legs.append(categoryLeg(c.id, c.categoryId, r2(c.amountBase), base, c.memo,
                                        c.origAmount.map(r2), c.origCurrency))
```

The auto-balance call site (`Entries.swift:397`) is left alone — it passes five
arguments and the two new parameters default to nil, which is correct: an
auto-balanced leg is computed, not typed.

- [ ] **Step 4: Give `TxSplit` the pair.** In `Models.swift`, replace the struct:

```swift
public struct TxSplit: Codable, Equatable, Sendable {
    public var id: String?
    public var categoryId: String?
    public var amount: Double
    public var amountBase: Double
    public var description: String?
    /// What the user typed for THIS cell, when the purchase was entered in a
    /// currency other than the ledger base — and the currency they typed it in.
    ///
    /// `amount` and `amountBase` both remain the LEDGER BASE figure. This is a
    /// separate field rather than a redefinition of `amount` deliberately:
    /// `Selectors.categoryShares`, the split-sum guard in `Transactions.swift`
    /// and the Edit sheet's split seeding all read `amount` today, and all three
    /// want base.
    ///
    /// **iOS-only, by decision.** The web's projection
    /// (`frontend/lib/db/queries/transactions.ts`) does not read the column, so
    /// it never populates this. Nothing breaks — the web has no grid and no
    /// `saveTransaction` — but the two stacks do not agree about it, and the
    /// parity oracle cannot catch that: its fixture contains no split at all
    /// (3 entries × one account leg + one category leg). If you are adding the
    /// web side, add a split to the fixture at the same time.
    public var origAmount: Double?
    public var origCurrency: String?
}
```

- [ ] **Step 5: Record the typed figure per cell.** In `SaveTransaction.buildLegs`, replace the `for (categoryId, amount) in byCategory` loop:

```swift
            // The caller computes the balancing legs (Decision 25): `rebuildEntry`
            // writes exactly what it is handed and has no auto-balance field.
            //
            // A category leg is stored in the LEDGER BASE, so on a foreign-currency
            // purchase the stored figure is not the one that was entered. Keeping
            // the typed figure per cell is what lets a grid reopen showing the
            // numbers the user wrote rather than back-converted ones — which drift
            // by a cent on awkward rates, and would be baked in on the next save.
            //
            // Negated alongside `amountBase` so the two carry one sign convention
            // and `Projection`'s existing flip restores both together.
            let typedInAnotherCurrency = purchaseCcy != base
            for (categoryId, amount) in byCategory {
                let b = try Entries.convertToBase(db, amount, purchaseCcy, base, date).amountBase
                legs.append(.category(Entries.CategoryLeg(
                    categoryId: categoryId, amountBase: Entries.r2(-b),
                    origAmount: typedInAnotherCurrency ? Entries.r2(-amount) : nil,
                    origCurrency: typedInAnotherCurrency ? purchaseCcy : nil)))
            }
```

- [ ] **Step 6: Carry it through the projection.** In `Projection.swift`, widen the private `Leg`:

```swift
    private struct Leg {
        let id: String; let categoryId: String?; let amountBase: Double; let sortOrder: Int
        let origAmount: Double?; let origCurrency: String?
    }
```

add the two columns to its query:

```swift
            SELECT p.id, p.entry_id, p.category_id, p.amount_base, p.sort_order,
                   p.orig_amount, p.orig_currency
```

fill them where the `Leg` is constructed:

```swift
                                                     amountBase: r["amount_base"], sortOrder: r["sort_order"],
                                                     origAmount: r["orig_amount"], origCurrency: r["orig_currency"]))
```

and pass them to `TxSplit`, negated exactly as `amountBase` already is:

```swift
                rows[i].splits = legs.sorted { $0.sortOrder < $1.sortOrder }.map {
                    TxSplit(id: $0.id, categoryId: $0.categoryId,
                            amount: -$0.amountBase, amountBase: -$0.amountBase, description: nil,
                            origAmount: $0.origAmount.map { -$0 }, origCurrency: $0.origCurrency)
                }
```

- [ ] **Step 7: Run the new tests — all three must pass.**

Run:
```bash
cd ios/FinchCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter TypedAmountTests
```
Expected: 3 tests, 0 failures.

- [ ] **Step 8: Run the whole engine suite, and read the parity results specifically.**

Run:
```bash
cd ios/FinchCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```
Expected: 0 failures. `ProjectionParityTests` is the one to watch: it compares a
decoded `[Tx]` against a web-generated fixture. It must still pass **because the
fixture has no splits** — every entry there has exactly one category leg, so
`splits` is nil on both sides. If it fails, do NOT regenerate the fixture; stop
and report, because that would mean the fixture's shape is not what this plan
assumed.

- [ ] **Step 9: Commit.**

```bash
git add ios/FinchCore/Sources/FinchCore ios/FinchCore/Tests/FinchCoreTests/TypedAmountTests.swift
git commit -m "feat: every cell remembers the amount as typed

A category leg is stored in the ledger base, so on a foreign-currency purchase
the stored figure is not the one entered. Each cell now carries its own typed
figure and currency alongside it.

This is what lets a grid reopen showing the numbers the user actually wrote
rather than back-converted ones — which drift by a cent on awkward rates, and
would be baked in as the new truth on the next save.

TxSplit gains the pair as NEW fields; amount and amountBase both still mean
ledger base, so categoryShares, the split-sum guard and the Edit sheet's split
seeding are all untouched. iOS-only by decision, with the divergence and the
oracle's blind spot recorded where the field is defined."
```

---

## Task 4: Changing a split's amount is honoured, or refused

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/EditTransactionSheet.swift` — the `.onChange(of: amountText)` at `:399-402`; `save()` at `:459`
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/AddTransactionSheet.swift` — `save()`, at the point after `guard let value = DecimalInput.parse(amount)`
- Test: `ios/FinchApp/Tests/FinchAppTests/SplitSaveGateTests.swift` (new)

**Interfaces:**
- Consumes: `SplitAllocation.problem -> Problem?` (`.needsAmount` / `.needsTwo` / `.sumMismatch`) and `SplitAllocation.setTotal(_:)`, both already public to the module. `PurchaseFlow.isBalanced(_:) -> Bool`.
- Produces: nothing later tasks depend on.

**Copy rule:** reuse the exact string `"Splits must add up to the transaction total."`, which already exists in the catalog (`SearchablePickerRow.swift:302`, `CategoryPickerRow.swift:228`). Do NOT invent a new message — a new key means committing the catalog, and the i18n guard diffs against HEAD.

**Known gap, deliberately left:** that key has no `zh-Hans` value — one of 32
untranslated keys out of 762. Reusing it does not make the gap worse, but this
plan does promote the message from a picker-sheet footnote to the primary save
error, so a Chinese user now sees English in a more prominent place. Translating
it belongs with the other 31 in a batch that owns the catalog commit and the
guard dance, not here. Do NOT add a lone translation as a drive-by: the catalog
guard diffs against HEAD and an intentional `.xcstrings` change fails the
pre-commit gate until it is committed on its own.

- [ ] **Step 1: Write the failing test.** Create `ios/FinchApp/Tests/FinchAppTests/SplitSaveGateTests.swift`:

```swift
import XCTest
@testable import FinchApp

/// Typing a new amount over an existing split.
///
/// The rows of a reopened split arrive PINNED (`SplitAllocation.merging`) —
/// they are figures the user set before and must not be re-divided just by
/// opening the sheet. `redistribute()` therefore returns early when every row is
/// pinned, so `setTotal` moves the target without moving a single cell.
///
/// That is correct behaviour for the model and a silent data loss at the sheet:
/// `save()` sends `payload`, which still holds the old figures, so typing 120
/// over a 100 split saved 100 and said nothing. The model already computes the
/// right diagnosis; nothing consulted it.
final class SplitSaveGateTests: XCTestCase {

    /// A reopened two-card split of 100.
    private func reopened() -> SplitAllocation {
        SplitAllocation.merging([(id: Optional("a1"), amount: 60),
                                 (id: Optional("a2"), amount: 40)], total: 100)
    }

    func test_aReopenedSplitStartsAgreeingWithItsTotal() {
        XCTAssertNil(reopened().problem, "60 + 40 = 100, nothing to complain about")
    }

    /// The bug, stated as an assertion: raising the total leaves the cells alone,
    /// so what would be SAVED no longer matches what is on screen.
    func test_raisingTheTotalLeavesTheCellsBehind() {
        var alloc = reopened()
        alloc.setTotal(120)
        XCTAssertEqual(alloc.allocated, 100, accuracy: 0.001,
                       "every row is pinned, so redistribute cannot move them")
        XCTAssertEqual(alloc.problem, .sumMismatch,
                       "and the model says so — this is the signal the sheet must not ignore")
    }

    /// Correcting a cell clears it. This is the way out of the blocked state, so
    /// it has to actually work.
    func test_correctingACellClearsTheMismatch() {
        var alloc = reopened()
        alloc.setTotal(120)
        alloc.setAmount("a1", 80)
        XCTAssertEqual(alloc.allocated, 120, accuracy: 0.001)
        XCTAssertNil(alloc.problem)
    }

    /// Unpinning a row lets it absorb the difference instead — the other way out.
    func test_unpinningARowAbsorbsTheDifference() {
        var alloc = reopened()
        alloc.setTotal(120)
        alloc.setAmount("a2", nil)
        XCTAssertEqual(alloc.allocated, 120, accuracy: 0.001, "a2 floats and takes the rest")
        XCTAssertNil(alloc.problem)
    }

    /// A single row is not a split, and must never be blocked.
    func test_aSingleRowIsNeverBlocked() {
        var alloc = SplitAllocation.merging([(id: Optional("a1"), amount: 100)], total: 100)
        alloc.setTotal(120)
        XCTAssertNil(alloc.problem, "one row is a plain purchase, not a split")
    }

    /// The grid's own balance check, which gates the same save.
    func test_theGridBlocksUntilItsCellsReachTheTotal() {
        var grid = SplitAllocation(total: 100)
        for key in ["a1|c1", "a2|c1"] { grid.tick(key) }
        grid.setAmount("a1|c1", 60)
        grid.setAmount("a2|c1", 35)
        XCTAssertFalse(PurchaseFlow.isBalanced(grid), "5 unaccounted")
        grid.setAmount("a2|c1", 40)
        XCTAssertTrue(PurchaseFlow.isBalanced(grid))
    }
}
```

- [ ] **Step 2: Run it and record which fail.**

Run:
```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" \
  xcodebuild -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-splits' \
  -only-testing:FinchAppTests/SplitSaveGateTests test 2>&1 | grep -E "passed|failed|error:"
```
Expected: **all six PASS.** These assert what `SplitAllocation` already does
correctly — the model was never the bug. They are written first because they
pin the contract the sheet changes below depend on, and because a later
refactor of `merging`/`redistribute` would otherwise break the gate silently.

- [ ] **Step 3: Re-total both allocations when the amount changes.** In `EditTransactionSheet.swift`, replace the `.onChange(of: amountText)` block:

```swift
            .onChange(of: amountText) { _, newValue in
                // Keep BOTH splits dividing the amount actually on screen.
                //
                // `accountAlloc` was seeded in `.onAppear` and never re-totalled,
                // so typing a new amount changed nothing at all: `save()` sends
                // `payload`, which still held the old per-card figures. You typed
                // 120 over a 100 split, tapped ✓, and 100 was saved in silence.
                //
                // Re-totalling does not by itself move the cells — a reopened
                // split's rows arrive pinned — which is why `save()` also refuses
                // a mismatch rather than trusting this to fix it.
                let total = abs(DecimalInput.parse(newValue) ?? 0)
                splitAlloc.setTotal(total)
                accountAlloc.setTotal(total)
            }
```

- [ ] **Step 4: Refuse a save the screen does not agree with.** In `EditTransactionSheet.save()`, insert immediately before the `let parsedAmount: Double` declaration:

```swift
        // The amount on screen is the target, and the cells must reach it.
        //
        // A reopened split's rows are pinned, so raising the amount leaves them
        // behind: without this the sheet would post the old figures under the new
        // total and report success. Refused rather than silently reconciled — the
        // user is the only one who knows which cell was wrong.
        if accountAlloc.payload.count >= 2, accountAlloc.problem != nil {
            errorMessage = String(localized: "Splits must add up to the transaction total.")
            return
        }
        if isSplit, splitAlloc.problem != nil {
            errorMessage = String(localized: "Splits must add up to the transaction total.")
            return
        }
```

- [ ] **Step 5: Gate the Add sheet the same way, including the grid.** In `AddTransactionSheet.save()`, insert immediately after the existing `guard let value = DecimalInput.parse(amount), value != 0 else { … }` line:

```swift
        // Same rule as the Edit sheet: the amount is the target, the cells must
        // reach it. The grid is the case that could silently under-post — its
        // footer already SAYS "N unaccounted", and nothing stopped the save.
        if usesGrid, !PurchaseFlow.isBalanced(gridAlloc) {
            errorMessage = String(localized: "Splits must add up to the transaction total."); return
        }
        if accountAlloc.payload.count >= 2, accountAlloc.problem != nil {
            errorMessage = String(localized: "Splits must add up to the transaction total."); return
        }
        if splitAlloc.payload.count >= 2, splitAlloc.problem != nil {
            errorMessage = String(localized: "Splits must add up to the transaction total."); return
        }
```

- [ ] **Step 6: Build and run the whole app suite.**

Run:
```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" \
  xcodebuild -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-splits' test 2>&1 \
  | grep -E "^Test Suite 'All tests'|error:|Executed [0-9]+ tests"
```
Expected: 0 failures across all three bundles, and the UI suite passes.
If a UI test now fails on a split flow, read it before changing it: a save that
used to succeed and now refuses may be the test asserting the old silent
behaviour.

- [ ] **Step 7: Discard catalog churn, then commit.**

```bash
git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings
git add ios/FinchApp
git commit -m "fix: changing a split's amount actually saves it

Typing a new amount over a split did nothing. accountAlloc was seeded in
.onAppear and never re-totalled; splitAlloc was re-totalled but its rows arrive
pinned, so redistribute could not move them. Either way save() sent payload —
the old per-row figures. You typed 120 over a 100 split and 100 was saved,
silently.

Both allocations now follow the amount field, and ✓ refuses while the cells and
the stated total disagree, rather than posting a figure the screen does not
show. SplitAllocation already computed exactly this diagnosis; only the picker
sheets consulted it.

The grid is gated the same way: its footer already said \"N unaccounted\" while
letting the save through."
```

---

## Task 5: Gate and PR

**Files:** none modified — verification only.

- [ ] **Step 1: Confirm the branch is not behind.**

```bash
git fetch -q origin && git rev-list --count HEAD..origin/feat/frontend
```
Expected: `0`. If not, `git rebase origin/feat/frontend` and re-run Task 4 Step 6
before continuing — `ci-local.sh` refuses to run behind the base, because CI
builds the merge result and a stale run is a false green.

- [ ] **Step 2: Run the full gate, frontend job included.**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" \
  SIM_NAME=ios-finch-splits ./scripts/ci-local.sh --all
```
Expected: `all checks passed`. The frontend job must be run even though this
plan changes nothing under `frontend/` — it is the check that proves that claim.

- [ ] **Step 3: Discard the catalog churn the gate warns about, and confirm the tree is clean.**

```bash
git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings
git status --short
git diff --stat origin/feat/frontend...HEAD -- frontend/
```
Expected: `git status` prints nothing, and the `frontend/` diff is empty.

- [ ] **Step 4: Push and open the PR against `feat/frontend`.**

```bash
git push -u origin fix/typed-amounts
gh pr create --base feat/frontend --head fix/typed-amounts \
  --title "What you see is what is saved" --body-file <(cat <<'BODY'
Two live bugs on merged code, one cause: the sheet showed one number and the
ledger stored another.

## A foreign-currency purchase forgot what you paid

`Projection.swift:81` displays `orig_amount ?? amount` — the figure as typed,
falling back to the posting. `addTransaction` fills that pair; `saveTransaction`
never did, and both sheets moved to `saveTransaction` in merged work.

So €100 on a dollar card displayed as **$110** — the conversion, not the price —
and the €100 was unrecoverable from the row.

Recorded only when the entered currency differs from the card's, mirroring
`addTransaction`. Transfers never qualify: their cells are already in each
card's own currency.

**Why the equivalence tests missed it:** `canonical()` compared
`account_id|category_id|amount|currency|amount_base|memo` and never `orig_*`, so
"identical ledger" was measured on the columns that happened to agree. It now
compares them, on the account leg — the one the old actions also fill.

## Changing a split's amount did nothing

`accountAlloc` was seeded in `.onAppear` and never re-totalled. `splitAlloc` was
re-totalled, but a reopened split's rows arrive pinned and `redistribute()`
returns early when nothing floats. Either way `save()` sent `payload` — the old
per-row figures.

Type 120 over a 100 split, tap ✓, and 100 was saved without a word.

Both allocations now follow the amount field, and ✓ refuses while the cells and
the stated total disagree. `SplitAllocation` already computed exactly this
diagnosis (`.sumMismatch`); only the picker sheets consulted it. The grid is
gated the same way — its footer already said "N unaccounted" while letting the
save through.

## Also: every cell remembers what was typed

A category leg is stored in the ledger base, so on a foreign-currency purchase
the stored figure is not the one entered. Each cell now carries its own typed
figure, which is what will let a grid reopen showing the numbers the user wrote
rather than back-converted ones — those drift by a cent on awkward rates and
would be baked in as the new truth on the next save.

`TxSplit` gains the pair as **new fields**; `amount` and `amountBase` both still
mean ledger base, so `categoryShares`, the split-sum guard and the Edit sheet's
split seeding are untouched.

**iOS-only, deliberately.** The web does not read the column, so it never
populates it. Nothing breaks — the web has no grid and no `saveTransaction` —
but the two stacks do not agree about the field, and the parity oracle cannot
catch that: its fixture contains no split at all. Both facts are recorded where
the field is defined.

## Verification

`ios/scripts/ci-local.sh --all` → `all checks passed`; catalog churn discarded.
No changes under `frontend/`.
BODY
)
```

- [ ] **Step 5: Report the PR number and stop.** Do not merge — the user merges their own PRs.

---

## Out of scope

- **The two-page grid flow and grid reopen.** That is the next plan and depends on this one landing: without per-cell typed amounts a foreign-currency grid can only reopen showing back-converted figures.
- **Backfilling existing rows.** Purchases already written by `saveTransaction` have no typed amount to recover; nothing can invent one.
- **The web side of `TxSplit`.** Explicitly declined; see the comment on the field.
- **Rules.** Frozen, flagged for its own design review.

## Verification checklist

- [ ] `ci-local.sh --all` prints `all checks passed`; catalog churn discarded
- [ ] `canonical()` compares `orig_*` — proven by Task 1's test failing before Task 2 and passing after
- [ ] A same-currency purchase writes `orig_amount IS NULL` on every posting
- [ ] A transfer writes `orig_amount IS NULL` on both legs
- [ ] `ProjectionParityTests` passes with the fixture untouched
- [ ] Raising a reopened split's amount refuses the save instead of posting the old figures
- [ ] A single-row (non-split) purchase is never blocked by the new gate
- [ ] `git diff origin/feat/frontend...HEAD -- frontend/` is empty
