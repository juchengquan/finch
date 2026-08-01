# Multi-Account Transactions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One purchase paid from several accounts is stored as **one transaction** with several account legs, in both front-ends.

**Architecture:** The `postings` schema already permits N account legs — `tr_entry_seal` requires only `sum(amount_base) = 0`, `>= 2` postings and `>= 1` account leg, with no upper bound, and transfers already use two. What refuses a split purchase is the *same rule written twice*: `Entries.validateShape:299` throws on the write path, and `Audit.swift:128` reports after the fact — neither clause is part of the written invariant I7. This plan relaxes both, repairs the places that silently assume a single account leg, extends the write API, then does the same in the web stack and regenerates the shared fixtures. **No schema migration anywhere.**

**Tech Stack:** Swift 6 / GRDB / XCTest (iOS + macOS core), TypeScript / bun:test / sql.js (web), XcodeGen, shared SQLite schema and JSON fixtures.

## Global Constraints

- **Parity is mandatory.** `plans/ios-macos/2026-08-01-date-and-time-everywhere-design.md` decided *"the web follows iOS"* — every phase changes **both** front-ends and regenerates fixtures. The two schemas do not diverge.
- **No schema migration.** If any task appears to need a new column or a `CHECK` change, stop and escalate — it means the design drifted.
- **Base branch is `feat/frontend`**, never `main`. Work in an isolated worktree off `origin/feat/frontend`.
- **Build with** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and `xcodegen generate` (the `.xcodeproj` is git-ignored).
- **Gate before every push:** `ios/scripts/ci-local.sh` must print `all checks passed`. It churns `Localizable.xcstrings` as a side effect — **discard that before committing** (`git checkout -- ios/FinchApp/Sources/FinchShared/Resources/Localizable.xcstrings`) or ~8,800 junk lines land in the commit.
- **No `Co-Authored-By` trailer** in commit messages.
- **Invariant I7 stays authoritative for the shapes it names.** `transfer` ⟺ exactly 2 account legs and 0 category legs; `opening`/`adjustment` ⟺ exactly 1 account leg plus the matching equity leg; `refund` ⟹ no negative account leg. Only the undocumented `acct != 1` clause for `income`/`expense`/`refund` is being relaxed.

## Semantic decisions already taken (do not relitigate)

1. **One record, not several.** A split payment is one entry with N account legs. Decomposing into N entries destroys the fact that they were one purchase, irrecoverably.
2. **No account↔category pairing is stored.** An entry is a balanced set of postings; which account funded which category is deliberately not recorded. This matches the double-entry model already chosen and needs no schema change.
3. **Rules match on the whole entry.** The synthetic transaction handed to the rules engine carries the **sum** of the account legs, and its `account` is the **largest** leg.
4. **Different items per account is out of scope.** That is two purchases sharing a receipt, and the user logs two transactions. A matrix-entry screen for that case is a separate, later plan.

## File structure

| File | Responsibility | Change |
|---|---|---|
| `ios/FinchCore/Sources/FinchCore/Storage/Audit.swift` | `kind-shape` invariant | relax `badSimple` |
| `ios/FinchCore/Sources/FinchCore/Project/Projection.swift` | feed rows, one per account leg | transfer detection by `kind` |
| `ios/FinchCore/Sources/FinchCore/Store/Entries.swift` | rules engine synthetic Tx | sum legs; largest leg wins |
| `ios/FinchCore/Sources/FinchCore/Store/Domain/Transactions.swift` | `addTransaction` write API; `setTransactionSplits` and `updateTransaction` guards | accept `accounts: [...]`; refuse category splits on a multi-account entry (Task 4b); tell a split apart from a transfer when editing (Task 8) |
| `ios/FinchCore/Sources/FinchCore/Store/Domain/Scheduled.swift` | scheduled posting | one entry per split template, not N (Task 11) |
| `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/AccountSplitEditorView.swift` | the split-payment editor | create — twin of `SplitEditorView` |
| `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/AddTransactionSheet.swift` | Add sheet | present the editor; send `accounts` |
| `frontend/lib/db/core/entries.ts` | web audit + rules mirror | mirror of the above |
| `frontend/lib/select.ts` | web projection mirror | mirror |
| `frontend/components/add-expense-form.tsx` | web Add form | repeating account rows; `sharesCover` |
| `frontend/scripts/export-fixtures.ts` | fixture regeneration | run it |

**Not changing** (verified, already correct):
- `Schema.swift` — the seal trigger already permits N account legs.
- `Entries.dedupHash` (`Entries.swift:318`) — already maps over **all** account legs and sorts them.
- `Entries.resolveLegs` / `autoBalance` — `acctSum` already reduces over every account leg.
- `Selectors.matchedAmount` — correct by construction once the projection stops duplicating splits.

---

### Task 1: Relax the kind-shape invariant (iOS)

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Entries.swift:299` and `:302` (`validateShape`)
- Modify: `ios/FinchCore/Sources/FinchCore/Storage/Audit.swift:128`
- Test: `ios/FinchCore/Tests/FinchCoreTests/MultiAccountShapeTests.swift` (create)

> **The rule is enforced TWICE and both must move together.** `Entries.validateShape`
> (called from `postEntry:409` and the two `rebuildEntry` paths at `:691`/`:697`) throws
> `error.entry.oneAccountLeg` *before anything is written*; `Audit.swift` only reports
> after the fact. Relaxing the audit alone changes nothing observable — the write still
> fails. This was missed when the plan was drafted and found by the Task 1 implementer.

**Interfaces:**
- Consumes: `TestSeed.base()` → migrated `DatabaseQueue` with ledger `l1` (USD), account `a1` (Cash, USD), category `c1` (Food, expense).
- Produces: a legal entry shape — `kind='expense'` with `acct >= 1` and `plain >= 1` — that Tasks 2, 3 and 4 build on.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchCore/Tests/FinchCoreTests/MultiAccountShapeTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

final class MultiAccountShapeTests: XCTestCase {

    /// Seed a second USD account so an entry can span two of them.
    private func seedTwoAccounts() throws -> DatabaseQueue {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Card','credit_card','USD',0,1,1,1,datetime('now'),datetime('now'))
                """)
        }
        return q
    }

    /// $100 of groceries, $60 on the card and $40 in cash. One purchase.
    func test_expenseAcrossTwoAccounts_passesAudit() throws {
        let q = try seedTwoAccounts()
        try q.write { db in
            _ = try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: "l1", date: "2026-06-01", time: "12:00",
                description: "Market", kind: .expense,
                legs: [
                    .account(Entries.AccountLeg(accountId: "a2", amount: -60)),
                    .account(Entries.AccountLeg(accountId: "a1", amount: -40)),
                    .category(Entries.CategoryLeg(categoryId: "c1", amountBase: 100)),
                ]))
        }
        let problems = try Audit.run(on: q)
        XCTAssertTrue(problems.filter { $0.code == .kindShape }.isEmpty,
                      "a two-account expense is a legal shape: \(problems.map(\.detail))")
    }

    /// The relaxation must NOT loosen transfers — I7 still pins them at exactly 2
    /// account legs and no category leg.
    func test_transferWithThreeAccountLegs_stillFailsAudit() throws {
        let q = try seedTwoAccounts()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a3','l1','Savings','savings','USD',0,2,1,1,datetime('now'),datetime('now'))
                """)
            _ = try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: "l1", date: "2026-06-01", time: "12:05",
                description: "Sweep", kind: .transfer,
                legs: [
                    .account(Entries.AccountLeg(accountId: "a1", amount: -100)),
                    .account(Entries.AccountLeg(accountId: "a2", amount: 40)),
                    .account(Entries.AccountLeg(accountId: "a3", amount: 60)),
                ]))
        }
        let problems = try Audit.run(on: q)
        XCTAssertFalse(problems.filter { $0.code == .kindShape }.isEmpty,
                       "a 3-leg transfer must still be a kind-shape defect")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ios && swift test --filter MultiAccountShapeTests
```

Expected: `test_expenseAcrossTwoAccounts_passesAudit` FAILS with a `kind-shape` problem reading `kind=expense but shape is acct=2 plain=1 …`. `test_transferWithThreeAccountLegs_stillFailsAudit` already PASSES.

- [ ] **Step 3a: Relax the write-path check**

In `ios/FinchCore/Sources/FinchCore/Store/Entries.swift`, in `validateShape`'s
`default:` branch (income / expense / refund), replace lines 299 and 302:

```swift
            if acct.count != 1 { throw I18nError("error.entry.oneAccountLeg", ["kind": kind.rawValue], "A \(kind.rawValue) entry has exactly one account leg") }
```
```swift
            if kind == .refund && acct[0].amount <= 0 { throw I18nError("error.refund.positive", [:], "A refund must be positive") }
```

with:

```swift
            // One purchase may be paid from SEVERAL accounts (split tender), so the
            // count is no longer pinned at 1. `legs.count < 2 || acct.count < 1` above
            // already guarantees at least one account leg, so nothing weaker is needed
            // here. Invariant I7 never asked for exactly one — see the plan header.
```
```swift
            // EVERY account leg must be positive, not just the first. `acct[0]` was
            // adequate while there could only be one; with split tender it would wave
            // through a refund whose second leg is negative.
            if kind == .refund && acct.contains(where: { $0.amount <= 0 }) {
                throw I18nError("error.refund.positive", [:], "A refund must be positive")
            }
```

- [ ] **Step 3b: Relax the audit clause**

In `ios/FinchCore/Sources/FinchCore/Storage/Audit.swift`, replace line 128:

```swift
                let badSimple = ["income", "expense", "refund"].contains(kind) && (acct != 1 || plain < 1 || eqOpen + eqAdj > 0)
```

with:

```swift
                // `acct >= 1` rather than `acct == 1`: one purchase may be paid from
                // several accounts (split tender). The written invariant I7 never
                // required a single account leg for income/expense/refund — only
                // transfer (exactly 2), opening/adjustment (exactly 1) — and the seal
                // trigger already guarantees at least one account leg exists.
                let badSimple = ["income", "expense", "refund"].contains(kind) && (acct < 1 || plain < 1 || eqOpen + eqAdj > 0)
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd ios && swift test --filter MultiAccountShapeTests
```

Expected: both PASS.

- [ ] **Step 5: Run the full core suite for regressions**

```bash
cd ios && swift test
```

Expected: PASS. `AuditTests`, `AuditParityTests` and the 10 corruption fixtures must all stay green — the `unbalanced` fixture is caught by the trial-balance rule, not by `kind-shape`, so it is unaffected.

- [ ] **Step 6: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Storage/Audit.swift ios/FinchCore/Tests/FinchCoreTests/MultiAccountShapeTests.swift
git commit -m "feat(core): a purchase may be paid from several accounts"
```

---

### Task 2: Stop reading transfer from the leg count (iOS projection)

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Project/Projection.swift:149`
- Test: `ios/FinchCore/Tests/FinchCoreTests/MultiAccountShapeTests.swift` (extend)

**Interfaces:**
- Consumes: the legal two-account expense from Task 1.
- Produces: `Tx.transferGroupId == nil` for multi-account non-transfers; still set for real transfers. Task 4 relies on this.

`Projection.swift:149` currently reads `if (acctCount[eid] ?? 1) >= 2 { rows[i].transferGroupId = eid }`. Since Task 1, `acct >= 2` no longer implies transfer. `entries.kind` is the authority — `postEntry` stamps it and the audit verifies it.

- [ ] **Step 1: Write the failing test**

Append to `MultiAccountShapeTests`:

```swift
    /// A split-tender purchase must not be presented as a transfer.
    func test_twoAccountExpense_isNotATransferGroup() throws {
        let q = try seedTwoAccounts()
        try q.write { db in
            _ = try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: "l1", date: "2026-06-01", time: "12:00",
                description: "Market", kind: .expense,
                legs: [
                    .account(Entries.AccountLeg(accountId: "a2", amount: -60)),
                    .account(Entries.AccountLeg(accountId: "a1", amount: -40)),
                    .category(Entries.CategoryLeg(categoryId: "c1", amountBase: 100)),
                ]))
        }
        let txns = try Projection.run(dbQueue: q, ledgerId: "l1")
        XCTAssertEqual(txns.count, 2, "one row per account leg")
        XCTAssertTrue(txns.allSatisfy { $0.transferGroupId == nil },
                      "a split-tender expense is not a transfer")
    }

    /// A genuine transfer keeps its grouping.
    func test_transfer_stillCarriesTransferGroupId() throws {
        let q = try seedTwoAccounts()
        try q.write { db in
            _ = try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: "l1", date: "2026-06-02", time: "09:00",
                description: "Move", kind: .transfer,
                legs: [
                    .account(Entries.AccountLeg(accountId: "a1", amount: -50)),
                    .account(Entries.AccountLeg(accountId: "a2", amount: 50)),
                ]))
        }
        let txns = try Projection.run(dbQueue: q, ledgerId: "l1")
        XCTAssertEqual(txns.count, 2)
        XCTAssertTrue(txns.allSatisfy { $0.transferGroupId != nil },
                      "a transfer's two legs must stay grouped")
    }
```

- [ ] **Step 2: Run to verify the first fails**

```bash
cd ios && swift test --filter MultiAccountShapeTests
```

Expected: `test_twoAccountExpense_isNotATransferGroup` FAILS (`transferGroupId` is set). `test_transfer_stillCarriesTransferGroupId` PASSES.

- [ ] **Step 3: Read kind instead of the leg count**

In `ios/FinchCore/Sources/FinchCore/Project/Projection.swift`, replace line 149:

```swift
            if (acctCount[eid] ?? 1) >= 2 { rows[i].transferGroupId = eid }
```

with:

```swift
            // `kind`, not the leg count: since split tender, `acct >= 2` no longer
            // means transfer. postEntry stamps kind and the audit verifies it, so it
            // is the authority. Shape agrees — a transfer is the only kind with two
            // account legs and NO category leg.
            if rows[i].kind == "transfer", (acctCount[eid] ?? 1) >= 2 { rows[i].transferGroupId = eid }
```

- [ ] **Step 4: Run to verify both pass**

```bash
cd ios && swift test --filter MultiAccountShapeTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Project/Projection.swift ios/FinchCore/Tests/FinchCoreTests/MultiAccountShapeTests.swift
git commit -m "fix(core): a split-tender purchase is not a transfer"
```

---

### Task 3: Rules see the whole entry, not the first leg (iOS)

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Entries.swift` (the rules block inside `postEntry`, ~lines 363-390)
- Test: `ios/FinchCore/Tests/FinchCoreTests/MultiAccountRulesTests.swift` (create)

**Interfaces:**
- Consumes: the legal shape from Task 1.
- Produces: `postEntry` writes a **balanced** entry when a rule carrying `splits` fires on a multi-account entry.

Today the block does `legs.first(where: { $0.accountId != nil })` and derives split portions from that one leg's amount. On a `-60 / -40` entry a splits rule deletes both category legs and rebuilds them summing to 60 against 100 of account legs — `tr_entry_seal` aborts the write.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchCore/Tests/FinchCoreTests/MultiAccountRulesTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

final class MultiAccountRulesTests: XCTestCase {

    /// A splits rule must distribute over the TOTAL of the account legs, not the
    /// first one, or the entry cannot balance and the seal aborts.
    func test_splitsRule_onTwoAccountEntry_balances() throws {
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
        }
        // Build the rule through the action, not raw SQL — the `rules` table stores
        // `condition` and `actions` as JSON blobs (NOT `match_json`/`actions_json`),
        // and `createRule` is what the rest of the suite uses. Shape copied from
        // BackfillRuleTests.swift:27-29; the "split" action shape is
        // RulesEngine.swift:111-116.
        let condition: JSONValue = .object([
            "field": .string("merchant"), "op": .string("contains"), "value": .string("Market")])
        let actions: JSONValue = .array([.object([
            "type": .string("split"),
            "splits": .array([
                .object(["fraction": .double(0.7), "categoryId": .string("c1")]),
                .object(["fraction": .double(0.3), "categoryId": .string("c2")]),
            ])])])
        try Apply.apply(dbQueue: q, action: "createRule", args: Args([
            "id": .string("r1"), "ledgerId": .string("l1"), "name": .string("Split market"),
            "condition": condition, "actions": actions]))
        let eid = try q.write { db in
            try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: "l1", date: "2026-06-01", time: "12:00",
                description: "Market", kind: .expense,
                legs: [
                    .account(Entries.AccountLeg(accountId: "a2", amount: -60)),
                    .account(Entries.AccountLeg(accountId: "a1", amount: -40)),
                    .category(Entries.CategoryLeg(categoryId: "c1", amountBase: 100)),
                ]))
        }
        let sum = try q.read { db in
            try Double.fetchOne(db, sql: "SELECT ROUND(SUM(amount_base), 2) FROM postings WHERE entry_id = ?", arguments: [eid])
        }
        XCTAssertEqual(sum, 0, "the entry must balance after the rule rewrote its splits")

        let catTotal = try q.read { db in
            try Double.fetchOne(db, sql: "SELECT ROUND(SUM(amount_base), 2) FROM postings WHERE entry_id = ? AND category_id IS NOT NULL", arguments: [eid])
        }
        XCTAssertEqual(catTotal, 100, "splits must cover the FULL 100, not just the first leg's 60")
    }
}
```

> Verified against the source: the `rules` table's JSON columns are `condition` and
> `actions` (`Schema.swift:286-292`), the rule is created via the `createRule` action
> (`BackfillRuleTests.swift:27-29`), and the splits action is `type: "split"` carrying a
> `splits` array of `{fraction, categoryId}` (`RulesEngine.swift:111-116`). The condition
> matches on `merchant`, which `postEntry` fills from the entry's description — so
> `description: "Market"` is what makes this rule fire.

- [ ] **Step 2: Run to verify it fails**

```bash
cd ios && swift test --filter MultiAccountRulesTests
```

Expected: FAIL — either the write aborts with `Entry postings must balance`, or `catTotal` is 60.

- [ ] **Step 3: Sum the account legs; largest leg names the account**

In `ios/FinchCore/Sources/FinchCore/Store/Entries.swift`, inside `postEntry`'s rules block, replace the single-leg lookup:

```swift
            if !rules.isEmpty, let acctLeg = legs.first(where: { $0.accountId != nil }) {
```

with a whole-entry view:

```swift
            // The rules engine sees ONE synthetic transaction for the whole entry.
            // Amount is the SUM of every account leg (so a rule matching ">= 100"
            // fires on a 60 + 40 split tender), and the account is the LARGEST leg
            // (an account-matching rule has to pick one, and the biggest payer is
            // the least surprising choice). Deriving either from `legs.first` made a
            // splits rule rebuild the category legs against one leg's amount, leaving
            // the entry unbalanced and aborting the seal.
            let acctLegs = legs.filter { $0.accountId != nil }
            let acctTotal = r2(acctLegs.reduce(0.0) { $0 + $1.amount })
            let acctTotalBase = r2(acctLegs.reduce(0.0) { $0 + $1.amountBase })
            if !rules.isEmpty, let acctLeg = acctLegs.max(by: { abs($0.amountBase) < abs($1.amountBase) }) {
```

Then in the synthetic `Tx`, use the totals rather than the single leg:

```swift
                    amount: acctTotalBase, account: acctLeg.accountId!, date: e.date,
```
```swift
                    currency: acctLeg.currency, nativeAmount: acctTotal, time: e.time,
```

And in the splits-replacement block, replace every `acctLeg.amount` / `acctLeg.amountBase` with the totals:

```swift
                        let ratio = acctTotal != 0 ? acctTotalBase / acctTotal : 1
                        legs.removeAll { $0.accountId == nil }
                        var remaining = acctTotal
                        var remainingBase = acctTotalBase
                        for (i, s) in splits.enumerated() {
                            let isLast = i == splits.count - 1
                            let portion = isLast ? r2(remaining) : r2(acctTotal * s.fraction)
                            remaining = r2(remaining - portion)
                            let catBase = isLast ? r2(-remainingBase) : r2(-portion * ratio)
                            remainingBase = r2(remainingBase + catBase)
                            legs.append(categoryLeg(nil, s.categoryId, catBase, base, s.description))
                        }
```

> The last-split-absorbs-the-remainder rule is unchanged and still required — it is
> what stops `r2` drift minting a phantom `sys:fx` residue on cross-currency entries.

- [ ] **Step 4: Run to verify it passes**

```bash
cd ios && swift test --filter MultiAccountRulesTests
```

Expected: PASS.

- [ ] **Step 5: Run the full core suite**

```bash
cd ios && swift test
```

Expected: PASS. Single-account entries are unaffected — with one account leg the totals equal that leg, so every existing rules test sees identical values.

- [ ] **Step 6: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Store/Entries.swift ios/FinchCore/Tests/FinchCoreTests/MultiAccountRulesTests.swift
git commit -m "fix(core): rules read the whole entry, not its first account leg"
```

---

### Task 4: `addTransaction` accepts several accounts (iOS)

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Domain/Transactions.swift:193-216` (`AddInput`) and `:225` (`addTransactionReturningId`)
- Test: `ios/FinchCore/Tests/FinchCoreTests/MultiAccountAddTests.swift` (create)

**Interfaces:**
- Consumes: Tasks 1-3.
- Produces: the action contract the UI in Tasks 10-11 calls —
  `addTransaction` accepts an optional `accounts: [{accountId: String, amount: Double}]`.
  When present with 2+ entries it replaces `accountId`/`amount`; `sum(accounts[].amount)`
  must equal `amount` or the call throws `error.split.accountsMismatch`.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchCore/Tests/FinchCoreTests/MultiAccountAddTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

final class MultiAccountAddTests: XCTestCase {

    private func seedTwoAccounts() throws -> DatabaseQueue {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Card','credit_card','USD',0,1,1,1,datetime('now'),datetime('now'))
                """)
        }
        return q
    }

    func test_addTransaction_withTwoAccounts_makesOneEntryWithTwoAccountLegs() throws {
        let q = try seedTwoAccounts()
        let eid = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "amount": .double(-100),
            "merchant": .string("Market"), "categoryId": .string("c1"),
            "date": .string("2026-06-01"),
            "accounts": .array([
                .object(["accountId": .string("a2"), "amount": .double(-60)]),
                .object(["accountId": .string("a1"), "amount": .double(-40)]),
            ])]))
        let acctLegs = try q.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [eid!])
        }
        XCTAssertEqual(acctLegs, 2, "one entry carrying both payment sources")

        let problems = try Audit.run(on: q)
        XCTAssertTrue(problems.isEmpty, "the written entry must be clean: \(problems.map(\.detail))")
    }

    func test_addTransaction_withAccountsNotSummingToAmount_throws() throws {
        let q = try seedTwoAccounts()
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "amount": .double(-100),
            "merchant": .string("Market"), "categoryId": .string("c1"),
            "date": .string("2026-06-01"),
            "accounts": .array([
                .object(["accountId": .string("a2"), "amount": .double(-60)]),
                .object(["accountId": .string("a1"), "amount": .double(-30)]),
            ])])), "shares that don't total the amount must be rejected")
    }

    /// Balances must move on BOTH accounts.
    func test_addTransaction_withTwoAccounts_movesBothBalances() throws {
        let q = try seedTwoAccounts()
        _ = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "amount": .double(-100),
            "merchant": .string("Market"), "categoryId": .string("c1"),
            "date": .string("2026-06-01"),
            "accounts": .array([
                .object(["accountId": .string("a2"), "amount": .double(-60)]),
                .object(["accountId": .string("a1"), "amount": .double(-40)]),
            ])]))
        let (card, cash) = try q.read { db in
            (try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id = 'a2'") ?? 0,
             try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id = 'a1'") ?? 0)
        }
        XCTAssertEqual(card, -60)
        XCTAssertEqual(cash, -40)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd ios && swift test --filter MultiAccountAddTests
```

Expected: FAIL — `accounts` is not in `AddInput`, so it is ignored and only one account leg is written (`acctLegs == 1`).

- [ ] **Step 3: Add the input and the multi-account branch**

In `ios/FinchCore/Sources/FinchCore/Store/Domain/Transactions.swift`, make `accountId` optional and add the shares. Replace `let accountId: String` in `AddInput` (line 195) with:

```swift
        /// Single-account form. Optional only because `accounts` may carry the
        /// payment sources instead; exactly one of the two must be present.
        let accountId: String?
        /// Split tender: the same purchase paid from several accounts. Each share's
        /// `amount` is in that account's own currency and they must total `amount`.
        let accounts: [AccountShare]?
```

Add the nested type immediately after `AddInput`'s other properties, before its closing brace:

```swift
        struct AccountShare: Decodable {
            let accountId: String
            let amount: Double
        }
```

Then at the top of `addTransactionReturningId`, after `let a = try args.to(AddInput.self)` (line 227), insert the multi-account branch:

```swift
        // Split tender: one purchase, several payment sources -> ONE entry with an
        // account leg per source plus a single auto-balanced category leg. Rejected
        // if the shares don't total the stated amount, so a typo cannot silently
        // post a different purchase than the one on screen.
        if let shares = a.accounts, shares.count >= 2 {
            let total = (shares.reduce(0.0) { $0 + $1.amount } * 100).rounded() / 100
            let stated = (a.amount * 100).rounded() / 100
            guard total == stated else {
                throw I18nError("error.split.accountsMismatch",
                                ["total": String(format: "%.2f", total), "amount": String(format: "%.2f", stated)],
                                "The account amounts add up to \(total), not \(stated)")
            }
            let eid = try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: a.ledgerId, date: a.date, time: a.time, description: a.merchant, kind: kind,
                status: a.status.flatMap(Entries.Status.init(rawValue:)),
                legs: shares.map { .account(Entries.AccountLeg(accountId: $0.accountId, amount: $0.amount)) },
                autoBalance: .category(a.categoryId),
                notes: (a.note?.isEmpty ?? true) ? nil : a.note,
                counterpartyId: counterpartyId, refundedEntryId: refundedEntryId,
                sourceTemplateId: a.sourceTemplateId, occurrenceDate: a.occurrenceDate,
                skipRules: a.skipRules ?? false, allowDuplicate: a.allowDuplicate ?? false))
            try Budgets.invalidateForEntry(db, eid)
            try insertTags(db, entryId: eid, tagIds: a.tagIds)
            return eid
        }

        guard let singleAccountId = a.accountId else {
            throw I18nError("error.split.noAccount", [:], "A transaction needs an account")
        }
```

Then replace the remaining uses of `a.accountId` in the single-account paths (the `acctCcy` lookup at line 233, the foreign-currency `AccountLeg` at line 245, and the `postSimple` call at line 259) with `singleAccountId`.

- [ ] **Step 4: Run to verify it passes**

```bash
cd ios && swift test --filter MultiAccountAddTests
```

Expected: PASS.

- [ ] **Step 5: Run the full core suite**

```bash
cd ios && swift test
```

Expected: PASS. Every existing caller sends `accountId` and no `accounts`, so it takes the `guard` path unchanged.

- [ ] **Step 6: Add the two new error strings**

Add `error.split.accountsMismatch` and `error.split.noAccount` to `ios/scripts/zh-manual.json`, then regenerate the catalog:

```bash
bun run ios/scripts/build-xcstrings.ts
```

- [ ] **Step 7: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Store/Domain/Transactions.swift \
        ios/FinchCore/Tests/FinchCoreTests/MultiAccountAddTests.swift \
        ios/scripts/zh-manual.json ios/FinchApp/Sources/FinchShared/Resources/Localizable.xcstrings
git commit -m "feat(core): addTransaction takes several payment accounts"
```

---

### Task 4b: Category splits must not silently delete account legs

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Domain/Transactions.swift:36-52` (`setTransactionSplits`)
- Test: `ios/FinchCore/Tests/FinchCoreTests/MultiAccountAddTests.swift` (extend)

**Interfaces:**
- Consumes: the multi-account entry from Task 4.
- Produces: `setTransactionSplits` throws `error.split.multiAccount` on an entry with more
  than one account leg, instead of destroying data.

**This is the most dangerous interaction in the whole feature and it must ship with
Task 4, not after it.** `setTransactionSplits` reads *one* account leg —

```sql
SELECT … FROM postings WHERE entry_id = ? AND account_id IS NOT NULL LIMIT 1
```

— and rebuilds the entry as `[that leg] + category legs`. Run against a split purchase it
**silently deletes every other account leg**: `Card -60 / Cash -40 / Groceries +100`
becomes `Card -60 / Groceries +60`, and the $40 cash payment is gone with no error. The
entry still balances, so no trigger and no audit rule catches it.

Blocking it also keeps this phase's promise that a split purchase carries exactly one
category leg — which is what makes budgets correct with no changes to any consumer.

- [ ] **Step 1: Write the failing test**

Append to `MultiAccountAddTests`:

```swift
    /// Splitting the CATEGORY of a purchase that was paid from several ACCOUNTS would
    /// rebuild it from a single account leg and silently drop the rest. Refuse it.
    func test_setTransactionSplits_onMultiAccountEntry_isRefusedAndKeepsBothLegs() throws {
        let q = try seedTwoAccounts()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at)
                VALUES ('c2','l1',NULL,'Household','expense',1,datetime('now'),datetime('now'))
                """)
        }
        let eid = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "amount": .double(-100),
            "merchant": .string("Market"), "categoryId": .string("c1"),
            "date": .string("2026-06-01"),
            "accounts": .array([
                .object(["accountId": .string("a2"), "amount": .double(-60)]),
                .object(["accountId": .string("a1"), "amount": .double(-40)]),
            ])]))!

        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "setTransactionSplits", args: Args([
            "id": .string(eid),
            "splits": .array([
                .object(["categoryId": .string("c1"), "amount": .double(60)]),
                .object(["categoryId": .string("c2"), "amount": .double(40)]),
            ])])))

        // The refusal must leave the entry exactly as it was — both payments intact.
        let (legs, total) = try q.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [eid]) ?? 0,
             try Double.fetchOne(db, sql: "SELECT ROUND(SUM(amount_base), 2) FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [eid]) ?? 0)
        }
        XCTAssertEqual(legs, 2, "both payment accounts must survive the refusal")
        XCTAssertEqual(total, -100, "…carrying the full amount")
    }
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd ios && swift test --filter MultiAccountAddTests
```

Expected: FAIL — no error is thrown, `legs == 1`, and `total == -60`. **That failure is
the data loss; confirm you see those numbers before fixing it.**

- [ ] **Step 3: Refuse the operation**

In `setTransactionSplits`, immediately after `let entryId = ref.entryId` (line 42), insert:

```swift
        // A purchase paid from several accounts carries one category leg by design, and
        // the rebuild below reads a single account leg (LIMIT 1) — running it here would
        // drop every other payment silently, leaving a balanced entry that no trigger and
        // no audit rule flags. Refuse instead.
        let acctLegCount = try Int.fetchOne(db, sql:
            "SELECT COUNT(*) FROM postings WHERE entry_id = ? AND account_id IS NOT NULL",
            arguments: [entryId]) ?? 0
        if acctLegCount > 1 {
            throw I18nError("error.split.multiAccount", [:],
                            "A purchase paid from several accounts takes a single category")
        }
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd ios && swift test --filter MultiAccountAddTests
```

Expected: PASS — the throw happens and both legs survive.

- [ ] **Step 5: Add the string, rebuild the catalog, mirror on the web**

Add `error.split.multiAccount` to `ios/scripts/zh-manual.json`, run
`bun run ios/scripts/build-xcstrings.ts`, and apply the identical guard to the web's
`setTransactionSplits` equivalent in `frontend/lib/db/core/` with a matching test.

- [ ] **Step 6: Run both suites and commit**

```bash
cd ios && swift test
cd ../frontend && bun test
git add ios/ frontend/
git commit -m "fix: splitting the category of a multi-account purchase dropped its other payments"
```

---

### Task 5: Mirror the invariant, projection and rules in the web stack

**Files:**
- Modify: `frontend/lib/db/core/entries.ts:806` (audit) and its rules block
- Modify: `frontend/lib/select.ts` (transfer-group detection)
- Test: `frontend/lib/db/multi-account.test.ts` (create)

**Interfaces:**
- Consumes: the iOS semantics from Tasks 1-4 — identical rules, identical error codes.
- Produces: byte-equivalent behaviour, so the shared fixtures regenerate cleanly in Task 6.

- [ ] **Step 1: Write the failing test**

Create `frontend/lib/db/multi-account.test.ts`:

```typescript
import { test, expect } from 'bun:test';
import { newDb, addAccount } from './entries.test';
import { postEntry, auditLedger } from './core/entries';

test('a purchase paid from two accounts is a legal shape', async () => {
  const exec = await newDb();
  await addAccount(exec, 'card', 'SGD', 'personal');
  await addAccount(exec, 'cash', 'SGD', 'personal');

  await postEntry(exec, {
    ledgerId: 'personal', date: '2026-06-01', time: '12:00',
    description: 'Market', kind: 'expense',
    legs: [
      { accountId: 'card', amount: -60 },
      { accountId: 'cash', amount: -40 },
      { categoryId: 'food', amount: 100 },
    ],
  });

  const problems = await auditLedger(exec, 'personal');
  expect(problems.filter((p) => p.code === 'kind-shape')).toEqual([]);
});

test('a transfer with three account legs is still a defect', async () => {
  const exec = await newDb();
  await addAccount(exec, 'a', 'SGD', 'personal');
  await addAccount(exec, 'b', 'SGD', 'personal');
  await addAccount(exec, 'c', 'SGD', 'personal');

  await postEntry(exec, {
    ledgerId: 'personal', date: '2026-06-01', time: '12:05',
    description: 'Sweep', kind: 'transfer',
    legs: [
      { accountId: 'a', amount: -100 },
      { accountId: 'b', amount: 40 },
      { accountId: 'c', amount: 60 },
    ],
  });

  const problems = await auditLedger(exec, 'personal');
  expect(problems.some((p) => p.code === 'kind-shape')).toBe(true);
});
```

> Use whatever category id the seeded web fixture actually provides in place of
> `'food'` — read `frontend/lib/db/core/test-utils.ts` for the seeded ids. The
> assertions are what matter.

- [ ] **Step 2: Run to verify the first fails**

```bash
cd frontend && bun test lib/db/multi-account.test.ts
```

Expected: the first test FAILS with a `kind-shape` problem; the second PASSES.

- [ ] **Step 3: Relax BOTH web clauses**

The web mirrors iOS exactly: `validateShape` (`frontend/lib/db/core/entries.ts:202`)
blocks the write, and the `kind-shape` audit rule reports afterwards. **Both must move**,
matching Task 1 Steps 3a and 3b — including generalising the refund check from the first
account leg to every account leg. Relaxing only the audit leaves the write still failing.

First, in `validateShape`'s income/expense/refund branch, drop the `acct.length !== 1`
throw and make the refund positivity check cover every account leg rather than `acct[0]`.

Then, in the same file's audit rule (line ~806), replace:

```typescript
      (['income', 'expense', 'refund'].includes(kind) && (acct !== 1 || plain < 1 || eqOpen + eqAdj > 0));
```

with:

```typescript
      // `acct < 1` not `acct !== 1`: split tender means one purchase may be paid
      // from several accounts. Mirrors ios/FinchCore/.../Audit.swift — invariant I7
      // never required a single account leg for income/expense/refund.
      (['income', 'expense', 'refund'].includes(kind) && (acct < 1 || plain < 1 || eqOpen + eqAdj > 0));
```

- [ ] **Step 4: Mirror the rules fix**

In the same file's `postEntry`, apply the Task 3 change: replace the `legs.find((l) => l.accountId != null)` lookup with the summed totals and the largest leg, and derive split portions from the totals. Match the Swift comment so the two read alike.

- [ ] **Step 5: Mirror the transfer-group fix**

In `frontend/lib/select.ts`, find where a transfer group is inferred from a count of account legs and gate it on `kind === 'transfer'`, exactly as Task 2 did.

- [ ] **Step 6: Run the web suite**

```bash
cd frontend && bun test
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add frontend/lib/db/core/entries.ts frontend/lib/select.ts frontend/lib/db/multi-account.test.ts
git commit -m "feat(web): a purchase may be paid from several accounts"
```

---

### Task 6: Regenerate the shared fixtures and prove parity

**Files:**
- Modify: `ios/FinchCore/Tests/ParityTests/Fixtures/**` (regenerated, not hand-edited)
- Run: `frontend/scripts/export-fixtures.ts`

**Interfaces:**
- Consumes: Tasks 1-5 landed in both stacks.
- Produces: fixtures both suites agree on — the contract every later task builds on.

- [ ] **Step 1: Regenerate**

```bash
cd frontend && bun install --frozen-lockfile && bun scripts/export-fixtures.ts
```

> `ios/README.md` documents this script's two gotchas — read it before running.

- [ ] **Step 2: Inspect the diff before trusting it**

```bash
git diff --stat ios/FinchCore/Tests/ParityTests/Fixtures/
```

Expected: no change, or only changes you can explain. **A large unexplained diff means a stack diverged — stop and investigate rather than committing it.** None of Tasks 1-5 alters the output for any existing single-account entry, so a big diff is a signal, not noise.

- [ ] **Step 3: Run both suites**

```bash
cd ios && swift test
cd ../frontend && bun test
```

Expected: PASS in both.

- [ ] **Step 4: Commit**

```bash
git add ios/FinchCore/Tests/ParityTests/Fixtures/
git commit -m "test: regenerate fixtures for split-tender purchases"
```

---

### Task 7: Full gate, then open the core PR

- [ ] **Step 1: Rebase onto the base branch**

```bash
git fetch origin feat/frontend && git rebase origin/feat/frontend
```

> `ci-local.sh` refuses to run while the branch is behind — CI builds the merge commit,
> so a green run from a stale branch is a false signal.

- [ ] **Step 2: Run the gate**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/ci-local.sh
```

Expected: `all checks passed`.

- [ ] **Step 3: Discard the catalog churn**

```bash
git checkout -- ios/FinchApp/Sources/FinchShared/Resources/Localizable.xcstrings
git status --porcelain   # expect empty
```

> The gate churns this generated file every run. Committing it is how PR #680 broke CI.

- [ ] **Step 4: Push and open the PR against `feat/frontend`**

Title: `feat: one purchase can be paid from several accounts`. The body must state that
no schema migration was needed, that invariant I7's documented shapes are unchanged, and
that the relaxed `acct != 1` clause was never part of the written invariant.

---

### Task 8: A split purchase can be edited (iOS core)

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Domain/Transactions.swift:326-331`
- Test: `ios/FinchCore/Tests/FinchCoreTests/MultiAccountEditTests.swift` (create)

**Interfaces:**
- Consumes: the entry shape from Task 4.
- Produces: `updateTransaction` tells a transfer apart from a split purchase. Header-only
  patches succeed on both. A money patch on a split purchase throws
  `error.tx.splitLegEdit`, not the transfer message.

`updateTransaction` currently reads `acctLegs.count > 1` as "this is a transfer" and
refuses money edits with *"Edit transfers from the Transfers screen"*. Since Task 1 that
premise is false — a split purchase has more than one account leg too, and its user would
be sent to a screen that has nothing to do with their purchase.

**Scope decision:** this task fixes the *message*, not the capability. Editing the amounts
of a posted split is deferred: a money patch carries one account and one amount and cannot
say which leg it means, so supporting it needs a richer patch shape and a leg-by-leg
`rebuildEntry` — a plan of its own. Delete-and-re-add works today.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchCore/Tests/FinchCoreTests/MultiAccountEditTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

final class MultiAccountEditTests: XCTestCase {

    private func splitPurchase() throws -> (DatabaseQueue, String) {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Card','credit_card','USD',0,1,1,1,datetime('now'),datetime('now'))
                """)
        }
        let eid = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "amount": .double(-100),
            "merchant": .string("Market"), "categoryId": .string("c1"),
            "date": .string("2026-06-01"),
            "accounts": .array([
                .object(["accountId": .string("a2"), "amount": .double(-60)]),
                .object(["accountId": .string("a1"), "amount": .double(-40)]),
            ])]))
        return (q, eid!)
    }

    /// Renaming the merchant touches no money and must succeed.
    func test_headerOnlyPatch_onSplitPurchase_succeeds() throws {
        let (q, eid) = try splitPurchase()
        try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
            "id": .string(eid), "patch": .object(["merchant": .string("Waitrose")])]))
        let name = try q.read { db in
            try String.fetchOne(db, sql: "SELECT description FROM entries WHERE id = ?", arguments: [eid])
        }
        XCTAssertEqual(name, "Waitrose")
    }

    /// A money patch is still refused — but with the SPLIT message, not the transfer one.
    func test_moneyPatch_onSplitPurchase_throwsSplitMessage() throws {
        let (q, eid) = try splitPurchase()
        do {
            try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
                "id": .string(eid), "patch": .object(["amount": .double(-120)])]))
            XCTFail("editing the money of a split purchase should be refused")
        } catch let e as I18nError {
            XCTAssertEqual(e.code, "error.tx.splitLegEdit",
                           "a split purchase is not a transfer — don't send its user to the Transfers screen")
        }
    }

    /// A real transfer keeps the transfer message.
    func test_moneyPatch_onTransfer_stillThrowsTransferMessage() throws {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Card','credit_card','USD',0,1,1,1,datetime('now'),datetime('now'))
                """)
        }
        let eid = try q.write { db in
            try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: "l1", date: "2026-06-02", time: "09:00",
                description: "Move", kind: .transfer,
                legs: [
                    .account(Entries.AccountLeg(accountId: "a1", amount: -50)),
                    .account(Entries.AccountLeg(accountId: "a2", amount: 50)),
                ]))
        }
        do {
            try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
                "id": .string(eid), "patch": .object(["amount": .double(-70)])]))
            XCTFail("editing a transfer's money through updateTransaction should be refused")
        } catch let e as I18nError {
            XCTAssertEqual(e.code, "error.tx.transferLegEdit")
        }
    }
}
```

> `I18nError` exposes its identifier as `.code` (see I18nError.swift:9); assert on
> whatever identifies it. The point is that the two cases produce *different* errors.

- [ ] **Step 2: Run to verify it fails**

```bash
cd ios && swift test --filter MultiAccountEditTests
```

Expected: `test_moneyPatch_onSplitPurchase_throwsSplitMessage` FAILS — it currently throws
`error.tx.transferLegEdit`. The other two PASS.

- [ ] **Step 3: Tell the two shapes apart**

In `ios/FinchCore/Sources/FinchCore/Store/Domain/Transactions.swift`, replace lines 326-331:

```swift
        let acctLegs = oldLegs.filter { ($0["account_id"] as String?) != nil }
        let touchesMoney = has("amount") || has("category") || has("account") || has("currency") || has("kind")
        // Transfers (>1 account leg) only take header-only patches.
        if acctLegs.count > 1 && touchesMoney {
            throw I18nError("error.tx.transferLegEdit", [:], "Edit transfers from the Transfers screen")
        }
```

with:

```swift
        let acctLegs = oldLegs.filter { ($0["account_id"] as String?) != nil }
        let touchesMoney = has("amount") || has("category") || has("account") || has("currency") || has("kind")
        // More than one account leg no longer means "transfer" — a purchase paid from
        // several accounts has them too. Both still take header-only patches, because a
        // money patch carries ONE account and ONE amount and cannot say which leg it
        // means. They get different messages: sending someone who split a purchase to
        // the Transfers screen is nonsense.
        if acctLegs.count > 1 && touchesMoney {
            let entryKind = try String.fetchOne(db, sql: "SELECT kind FROM entries WHERE id = ?", arguments: [entryId]) ?? ""
            if entryKind == "transfer" {
                throw I18nError("error.tx.transferLegEdit", [:], "Edit transfers from the Transfers screen")
            }
            throw I18nError("error.tx.splitLegEdit", [:],
                            "Delete and re-add this purchase to change how it was paid")
        }
```

- [ ] **Step 4: Run to verify all three pass**

```bash
cd ios && swift test --filter MultiAccountEditTests
```

- [ ] **Step 5: Add the string and rebuild the catalog**

Add `error.tx.splitLegEdit` to `ios/scripts/zh-manual.json`, then:

```bash
bun run ios/scripts/build-xcstrings.ts
```

- [ ] **Step 6: Mirror in the web stack**

Apply the identical split wherever `frontend/lib/db/core/` implements the same guard, with
a matching test in `frontend/lib/db/multi-account.test.ts`.

- [ ] **Step 7: Run both suites and commit**

```bash
cd ios && swift test
cd ../frontend && bun test
git add ios/ frontend/
git commit -m "fix: a split purchase is not a transfer when you try to edit it"
```

---

### Task 9: The Add sheet takes several accounts (iOS)

**Files:**
- Create: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/AccountSplitEditorView.swift`
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/AddTransactionSheet.swift` — state block (lines 44-68), the account row (lines 302 and 352), `save()` (line 541)
- Test: `ios/FinchApp/Tests/FinchAppTests/AccountSplitEditorTests.swift` (create)

**Interfaces:**
- Consumes: the `accounts: [{accountId, amount}]` contract from Task 4.
- Produces: `AccountSplitEditorView.DraftShare = (accountId: String, amount: Double)` and
  `AccountSplitEditorView.sharesCover(_:total:) -> Bool`, which Task 10 mirrors exactly.

**Model it on the category split editor that already exists.**
`SplitEditorView.swift` is the same shape one axis over — `typealias DraftSplit =
(categoryId: String?, amount: Double)`, a `Target` enum with `.draft(onSave:)`, a private
`Row: Identifiable` holding a string amount, an `allocated` computed property summing
`DecimalInput.parse`, and a remainder check against `total`. `AddTransactionSheet` already
drives it through `@State private var pendingSplits` / `showingSplit` (lines 64-65) and
applies it after save via `setTransactionSplits` (lines 624-628). Follow that idiom
closely — a reviewer should be able to diff the two editors.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchApp/Tests/FinchAppTests/AccountSplitEditorTests.swift`:

```swift
import XCTest
@testable import FinchAppSwiftUI

final class AccountSplitEditorTests: XCTestCase {

    func test_sharesTotallingTheAmount_areValid() {
        let shares: [AccountSplitEditorView.DraftShare] = [
            (accountId: "a2", amount: -60),
            (accountId: "a1", amount: -40),
        ]
        XCTAssertTrue(AccountSplitEditorView.sharesCover(shares, total: -100))
    }

    /// Shares that don't total the amount are rejected in the UI, so the engine's
    /// error.split.accountsMismatch stays unreachable in normal use.
    func test_sharesNotTotallingTheAmount_areRejected() {
        let shares: [AccountSplitEditorView.DraftShare] = [
            (accountId: "a2", amount: -60),
            (accountId: "a1", amount: -30),
        ]
        XCTAssertFalse(AccountSplitEditorView.sharesCover(shares, total: -100))
    }

    /// Rounding must not make a legitimate three-way split unsavable.
    func test_sharesWithinAPenny_areAccepted() {
        let shares: [AccountSplitEditorView.DraftShare] = [
            (accountId: "a2", amount: -33.33),
            (accountId: "a1", amount: -66.67),
        ]
        XCTAssertTrue(AccountSplitEditorView.sharesCover(shares, total: -100))
    }

    /// One share is not a split — the sheet must send a plain accountId instead.
    func test_aSingleShareIsNotASplit() {
        let shares: [AccountSplitEditorView.DraftShare] = [(accountId: "a1", amount: -100)]
        XCTAssertFalse(AccountSplitEditorView.sharesCover(shares, total: -100))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd ios && xcodegen generate --spec project.yml,project-mac.yml
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FinchAppTests/AccountSplitEditorTests -derivedDataPath /tmp/dd \
  -skipPackagePluginValidation -skipMacroValidation COMPILER_INDEX_STORE_ENABLE=NO
```

Expected: FAIL — `AccountSplitEditorView` does not exist.

- [ ] **Step 3: Create the editor**

Create `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/AccountSplitEditorView.swift`:

```swift
import SwiftUI
import FinchCore

/// Split tender — one purchase paid from several accounts.
///
/// This is `SplitEditorView` one axis over: that one divides a purchase across
/// CATEGORIES, this one across the ACCOUNTS that paid for it. Keep the two readable
/// side by side.
struct AccountSplitEditorView: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss

    typealias DraftShare = (accountId: String, amount: Double)

    /// Two or more shares totalling the purchase, within a penny of rounding.
    /// A penny of tolerance because a three-way split of an odd amount cannot land
    /// exactly and the user should not be blocked by the last cent.
    static func sharesCover(_ shares: [DraftShare], total: Double) -> Bool {
        guard shares.count >= 2 else { return false }
        return abs(shares.reduce(0) { $0 + $1.amount } - total) < 0.005
    }

    private let total: Double
    private let onSave: ([DraftShare]) -> Void

    private struct Row: Identifiable { let id = UUID(); var accountId: String; var amount: String }
    @State private var rows: [Row]

    init(total: Double, initialShares: [DraftShare]?, onSave: @escaping ([DraftShare]) -> Void) {
        self.total = total
        self.onSave = onSave
        _rows = State(initialValue: (initialShares ?? []).map {
            Row(accountId: $0.accountId, amount: String(format: "%.2f", $0.amount))
        })
    }

    private var shares: [DraftShare] {
        rows.compactMap {
            guard !$0.accountId.isEmpty, let v = DecimalInput.parse($0.amount) else { return nil }
            return (accountId: $0.accountId, amount: v)
        }
    }
    private var allocated: Double { shares.reduce(0) { $0 + $1.amount } }
    private var remainder: Double { ((total - allocated) * 100).rounded() / 100 }

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Transaction total", value: store.displayNative(total, currency: store.baseCurrency))
                LabeledContent("Allocated", value: store.displayNative(allocated, currency: store.baseCurrency))

                ForEach($rows) { $row in
                    SearchablePickerRow(title: "Account", glyph: .account,
                                        accounts: store.accounts, selection: $row.accountId)
                    TextField(String(localized: "Amount"), text: $row.amount)
                        .keyboardType(.decimalPad)
                }
                .onDelete { rows.remove(atOffsets: $0) }

                Button(String(localized: "Add another account")) {
                    rows.append(Row(accountId: "", amount: String(format: "%.2f", remainder)))
                }

                if remainder != 0 {
                    Text(String(localized: "Still to assign: \(Money.format(remainder, currency: store.baseCurrency))"))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(String(localized: "Split payment"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { onSave(shares); dismiss() }
                        .disabled(!Self.sharesCover(shares, total: total))
                }
            }
        }
    }
}
```

> Signatures verified against the codebase: the account picker is
> `SearchablePickerRow(title:glyph:accounts:selection:)` (`SearchablePickerRow.swift`,
> called at `AddTransactionSheet.swift:301` and `:352`) — there is no `AccountPickerRow`,
> only an `AccountPickerRowLabel`. Money formatting is `Money.format(_:currency:)` and
> `store.displayNative(_:currency:)`; `store.baseCurrency` lives in
> `FinchStore+ViewHelpers.swift:11`. `DecimalInput.parse(_:)` is
> `FinchApp/Sources/FinchAppSwiftUI/Common/DecimalInput.swift:16`. `SplitEditorView`
> formats its row amounts with `String(format: "%g", …)`; this editor uses `"%.2f"`
> because a payment share is money rather than a free-form figure.

- [ ] **Step 4: Wire it into the Add sheet**

Add state beside the existing split state (`AddTransactionSheet.swift`, after line 65):

```swift
    @State private var pendingAccounts: [AccountSplitEditorView.DraftShare]? = nil
    @State private var showingAccountSplit = false
```

In `save()`, in the non-transfer branch immediately after `args` is built (~line 600),
add the shares:

```swift
                // Split tender: several accounts paid for this one purchase. `accountId`
                // is still sent — the engine ignores it when `accounts` is present, and
                // keeping it leaves the duplicate check and the currency lookup above
                // untouched.
                if let shares = pendingAccounts,
                   AccountSplitEditorView.sharesCover(shares, total: signed) {
                    args["accounts"] = .array(shares.map { .object([
                        "accountId": .string($0.accountId), "amount": .double($0.amount)]) })
                }
```

Present the editor from the account row, mirroring how `showingSplit` presents
`SplitEditorView`:

```swift
                .sheet(isPresented: $showingAccountSplit) {
                    AccountSplitEditorView(
                        total: (kind == .income || kind == .refund)
                            ? abs(DecimalInput.parse(amount) ?? 0)
                            : -abs(DecimalInput.parse(amount) ?? 0),
                        initialShares: pendingAccounts,
                        onSave: { pendingAccounts = $0.isEmpty ? nil : $0 })
                }
```

- [ ] **Step 5: Run to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 6: Run the whole app suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" -derivedDataPath /tmp/dd \
  -retry-tests-on-failure -test-iterations 3 -test-repetition-relaunch-enabled YES \
  -skipPackagePluginValidation -skipMacroValidation COMPILER_INDEX_STORE_ENABLE=NO
```

Expected: PASS. The retry flags match CI (see the comment on that step in `ci.yml`).

- [ ] **Step 7: Localize**

`Account`, `Amount`, `Add another account`, `Still to assign: %@`, `Split payment`,
`Cancel`, `Done` — each through `String(localized:)`, added to `ios/scripts/zh-manual.json`,
then `bun run ios/scripts/build-xcstrings.ts`. Several already exist in the catalog;
reuse rather than duplicate.

- [ ] **Step 8: Commit**

```bash
git add ios/FinchApp/ ios/scripts/zh-manual.json ios/FinchApp/Sources/FinchShared/Resources/Localizable.xcstrings
git commit -m "feat(ios): pay for one purchase from several accounts"
```

---

### Task 10: The web add form takes several accounts

**Files:**
- Modify: `frontend/components/add-expense-form.tsx`
- Test: `frontend/components/add-expense-form.test.tsx` (create, or extend if present)

**Interfaces:**
- Consumes: the Task 5 web write path and the Task 4 contract.
- Produces: `sharesCover(shares, total)` with behaviour identical to Task 9's Swift twin,
  including the same penny tolerance and the same "one share is not a split" rule.

- [ ] **Step 1: Write the failing test**

```typescript
import { test, expect } from 'bun:test';
import { sharesCover } from './add-expense-form';

test('shares totalling the amount are valid', () => {
  expect(sharesCover([{ accountId: 'card', amount: -60 }, { accountId: 'cash', amount: -40 }], -100)).toBe(true);
});

test('shares not totalling the amount are rejected', () => {
  expect(sharesCover([{ accountId: 'card', amount: -60 }, { accountId: 'cash', amount: -30 }], -100)).toBe(false);
});

test('a penny of rounding is tolerated', () => {
  expect(sharesCover([{ accountId: 'card', amount: -33.33 }, { accountId: 'cash', amount: -66.67 }], -100)).toBe(true);
});

test('one share is not a split', () => {
  expect(sharesCover([{ accountId: 'cash', amount: -100 }], -100)).toBe(false);
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd frontend && bun test components/add-expense-form.test.tsx
```

Expected: FAIL — `sharesCover` is not exported.

- [ ] **Step 3: Implement**

```typescript
export type AccountShare = { accountId: string; amount: number };

/// Two or more shares totalling the purchase, within a penny of rounding.
/// Mirrors AccountSplitEditorView.sharesCover in the iOS app — keep them identical.
export const sharesCover = (shares: AccountShare[], total: number): boolean =>
  shares.length >= 2 && Math.abs(shares.reduce((s, x) => s + x.amount, 0) - total) < 0.005;
```

Add repeating account+amount rows, disable submit while `!sharesCover(...)`, show the
remainder, and send `accounts` alongside `accountId` exactly as Task 9 does.

- [ ] **Step 4: Run to verify it passes**

```bash
cd frontend && bun run typecheck && bun run lint && bun test
```

- [ ] **Step 5: Commit**

```bash
git add frontend/
git commit -m "feat(web): pay for one purchase from several accounts"
```

---

### Task 11: Scheduled splits become one entry

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Domain/Scheduled.swift:81-95`
- Modify: the web's scheduled-post mirror
- Test: `ios/FinchCore/Tests/FinchCoreTests/ScheduledSplitEntryTests.swift` (create)

**Interfaces:**
- Consumes: Task 4's multi-account posting path.
- Produces: a split template posts **one** entry with N account legs, so a split done by
  schedule and the same split done by hand store identically.

`Scheduled.post` loops over `scheduled_splits` calling `postSingle` once per split,
producing N unrelated transactions. That predates split tender and is now the odd one out.

> **This is the only task that changes behaviour for existing data.** Templates already
> split across accounts post differently from the day it ships. Transactions posted
> *before* it are untouched — no backfill, no migration — so history stays as recorded.
> Say both halves of that in the PR body.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchCore/Tests/FinchCoreTests/ScheduledSplitEntryTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

final class ScheduledSplitEntryTests: XCTestCase {

    /// A salary split 60/40 across two accounts posts ONE transaction with two account
    /// legs — the same shape the Add sheet produces by hand.
    func test_splitTemplate_postsOneEntryWithTwoAccountLegs() throws {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Savings','savings','USD',0,1,1,1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at)
                VALUES ('cin','l1',NULL,'Salary','income',1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO scheduled_templates
                  (id,ledger_id,name,description,kind,amount,amount_varies,splits_enabled,account_id,category_id,
                   frequency,start_date,auto_post,is_active,created_at,updated_at)
                VALUES ('t1','l1','Salary','Salary','income',3000,0,1,'a1','cin',
                        'monthly','2026-06-01',1,1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO scheduled_splits (id,template_id,account_id,amount_pct,amount_abs,category_id,description,sort_order)
                VALUES ('s1','t1','a1',60,NULL,NULL,'main',0), ('s2','t1','a2',40,NULL,NULL,'savings',1)
                """)
        }
        try Apply.apply(dbQueue: q, action: "postScheduled", args: Args([
            "templateId": .string("t1"), "date": .string("2026-06-01")]))

        let (entries, acctLegs) = try q.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE source_template_id = 't1'") ?? 0,
             try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM postings p JOIN entries e ON e.id = p.entry_id
                 WHERE e.source_template_id = 't1' AND p.account_id IS NOT NULL
                """) ?? 0)
        }
        XCTAssertEqual(entries, 1, "one salary is one transaction")
        XCTAssertEqual(acctLegs, 2, "…carrying both destination accounts")

        let problems = try Audit.run(on: q)
        XCTAssertTrue(problems.isEmpty, "the posted entry must be clean: \(problems.map(\.detail))")
    }
}
```

> The action name (`postScheduled`) and its argument keys must match `ActionName.swift`
> and `Scheduled.post`'s `Args` decoding — read both and adjust the `Apply.apply` call.
> The three assertions are the point.

- [ ] **Step 2: Run to verify it fails**

```bash
cd ios && swift test --filter ScheduledSplitEntryTests
```

Expected: FAIL — `entries == 2`, each with one account leg.

- [ ] **Step 3: Post one entry instead of N**

In `Scheduled.swift`, replace the `for sp in splits { try postSingle(...) }` loop
(lines ~85-93) with a single `postEntry`:

```swift
                // ONE transaction with an account leg per split — the same shape the Add
                // sheet produces for a split payment. This used to call postSingle once
                // per split, so a salary paid into two accounts became two unrelated
                // transactions while the identical split entered by hand became one.
                let legs: [Entries.Leg] = splits.compactMap { sp in
                    let portion = (sp["amount_abs"] as Double?) ?? (amount * ((sp["amount_pct"] as Double?) ?? 0) / 100)
                    guard portion != 0, let acct = sp["account_id"] as String? else { return nil }
                    return .account(Entries.AccountLeg(accountId: acct, amount: portion))
                }
                if legs.isEmpty {
                    throw I18nError("error.scheduled.noSplits", ["name": name], "No split amounts to post for \"\(name)\"")
                }
                _ = try Entries.postEntry(db, Entries.NewEntry(
                    ledgerId: ledgerId, date: date, time: postTime, description: desc, kind: .income,
                    legs: legs, autoBalance: .category(categoryId),
                    sourceTemplateId: templateId, occurrenceDate: occurrenceDate))
                return
```

Note the per-split `description` column is dropped — a single entry has one description.
If per-split descriptions must survive, carry each into its leg's `memo:` instead.

- [ ] **Step 4: Run to verify it passes**

```bash
cd ios && swift test --filter ScheduledSplitEntryTests
```

- [ ] **Step 5: Mirror in the web stack and regenerate fixtures**

```bash
cd frontend && bun test && bun scripts/export-fixtures.ts
git diff --stat ios/FinchCore/Tests/ParityTests/Fixtures/
```

A diff **is** expected here, unlike Task 6. Read it and confirm every changed row belongs
to a split template.

- [ ] **Step 6: Full gate, discard catalog churn, commit**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/ci-local.sh
git checkout -- ios/FinchApp/Sources/FinchShared/Resources/Localizable.xcstrings
git status --porcelain   # expect only intended files
git add ios/ frontend/
git commit -m "refactor: a split schedule posts one transaction, not several"
```

---

## Out of scope (deliberately)

- **The account × category matrix.** When each account paid for *different* categories, no
  pairing is recorded, so per-account category attribution is unavailable. That case is two
  purchases sharing a receipt, and the user logs two transactions. A matrix screen that
  writes them is a separate plan.
- **Editing the money of a posted split.** Task 8 fixes the misleading message; changing
  the amounts still needs delete-and-re-add. A money patch carries one account and one
  amount and cannot address a specific leg, so real support needs a richer patch shape.
- **Backfilling scheduled splits posted before Task 11.** They stay as recorded.
- **`SplitEditorView` and `AccountSplitEditorView` sharing code.** They are near-twins and
  the duplication is deliberate for now — unifying them is a refactor to do once both have
  settled, not while one is brand new.

## Verification checklist before the final PR

- [ ] `ios/scripts/ci-local.sh` prints `all checks passed`
- [ ] `Localizable.xcstrings` churn discarded; `git status --porcelain` clean of it
- [ ] `frontend`: `bun run typecheck && bun run lint && bun test` green
- [ ] Fixture diff after Task 6 is empty; after Task 11 contains only split templates
- [ ] `Audit.run` clean on a DB containing: a split purchase, a transfer, a refund, an
      opening balance and an adjustment
- [ ] A split purchase created on iOS opens correctly in the web app and vice versa
