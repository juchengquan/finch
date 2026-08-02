# Editing a Split Purchase — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open a purchase paid from several accounts and change *all* of its payments at once, instead of having to delete and re-add it.

**Architecture:** No new mechanism. `Entries.EntryPatch.legs` is already `Field<[Leg]>` and `rebuildEntry` already replaces an entry's whole leg set from it — that is how `setTransactionSplits` edits category splits today. This plan extends `updateTransaction` to accept an `accounts: [{accountId, amount}]` array, exactly as `addTransaction` already does on create, and shows the existing split editor in the Edit sheet. **No schema migration.**

**Tech Stack:** Swift 6 / GRDB / XCTest (iOS + macOS core), TypeScript / bun:test / sql.js (web), XcodeGen, shared SQLite schema and parity fixtures.

## Why this is worth doing

A user can create a split but cannot correct one. Today `updateTransaction` refuses any money edit on an entry with more than one account leg (`Transactions.swift`, the `error.tx.splitLegEdit` throw) because a patch carries **one** `account` and **one** `amount` and cannot say which leg it means. The fix is not a richer patch — it is to stop patching legs individually and hand over the whole set, which the engine already supports.

## Global Constraints

- **No schema migration.** If this appears to need a new column, stop and escalate — the design drifted.
- **Parity is mandatory.** `plans/ios-macos/2026-08-01-date-and-time-everywhere-design.md`: the web follows iOS. Every change lands on both stacks and the fixtures regenerate.
- **Base branch is `feat/frontend`.** Work in an isolated worktree off `origin/feat/frontend` **after PR #715 has merged** — this plan builds directly on its guards.
- **Build with** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and `xcodegen generate`.
- **Gate before every push:** `ios/scripts/ci-local.sh` must print `all checks passed`. It churns `Localizable.xcstrings` — discard that before committing unless a genuinely new string was generated (a few lines, never thousands).
- **`I18nError` codes localize in `ios/FinchApp/Sources/FinchShared/Common/ErrorL10n.swift`**, a code map. Static UI text goes `String(localized:)` → `ios/scripts/zh-manual.json` → `bun run ios/scripts/build-xcstrings.ts`. Putting an error code in `zh-manual.json` is a silent no-op.
- **No `Co-Authored-By` trailer.**
- **Poll for long-running gates** (`pgrep -f ci-local.sh` in a loop). Waiting for a harness notification about a process you started yourself never resolves — that stalled the predecessor plan five times.

## The one genuinely delicate requirement

**A rebuild replaces postings. Identity must survive it.**

Each account posting carries state the user cannot retype: its `id`, its `cleared_at` reconcile mark, its `memo`, and `orig_amount`/`orig_currency` for a foreign-currency entry. If the rebuild mints fresh postings, editing a split **silently un-reconciles it** — the entry still balances, the audit still passes, and a reconciled statement quietly comes undone. That is the exact failure shape the predecessor plan spent five guards on: something that balances and is therefore invisible.

The codebase already solves this twice; copy it rather than inventing:

- `rebuildEntry`'s date-change path reconstructs legs from the old rows carrying `memo:`, `id:` and the FX fields.
- `setTransactionSplits` reads the existing account posting with `id`, `memo`, `cleared_at`, `orig_amount`, `orig_currency` and passes them straight into its new `AccountLeg`.

**Match kept legs by `accountId`.** A leg whose account is unchanged keeps its posting id and reconcile mark; a newly added account gets a fresh posting; a removed account's posting goes. Note the degenerate case — two legs on the *same* account is representable through the action API (the predecessor plan logged it as unvalidated) — so matching must be deterministic there rather than silently picking one. Prefer sort order within an account.

## File structure

| File | Responsibility | Change |
|---|---|---|
| `ios/FinchCore/Sources/FinchCore/Store/Domain/Transactions.swift` | `updateTransaction` | accept `accounts: [...]`; retire the `splitLegEdit` refusal for this path |
| `frontend/lib/db/queries/transactions.ts` | web `updateTransaction` | mirror |
| `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/EditTransactionSheet.swift` | Edit sheet | show the split editor; send `accounts` |
| `frontend/scripts/export-fixtures.ts` | parity oracle | add an edit-a-split step |

**Not changing** (verified): `Entries.EntryPatch`, `rebuildEntry`, `SplitAllocation`, `SearchablePickerRow` — all already do what this needs.

---

### Task 1: `updateTransaction` accepts a full account-leg set (iOS)

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Domain/Transactions.swift` — `updateTransaction`
- Test: `ios/FinchCore/Tests/FinchCoreTests/MultiAccountEditTests.swift` (extend — it exists and already has split-purchase fixtures)

**Interfaces:**
- Produces: `updateTransaction` accepts `patch.accounts` as `[{accountId, amount}]`. When present, the entry's account legs are replaced by that set; category legs are recomputed by auto-balance. Kept accounts retain their posting `id`, `cleared_at`, `memo`, `orig_amount`, `orig_currency`.

- [ ] **Step 1: Write the failing tests**

Three behaviours, each its own test in `MultiAccountEditTests.swift`. Reuse its existing `splitPurchase()` helper.

1. **Amounts change and the entry still balances.** Patch `accounts: [{a2, -70}, {a1, -30}]` on a −60/−40 split; assert both legs' amounts, that `SUM(amount_base) == 0`, and that the category leg absorbed the change.
2. **Reconcile marks survive.** Set `cleared_at` on one posting before the edit (raw SQL), patch the *other* leg's amount, then assert the first posting's `id` **and** `cleared_at` are unchanged. This is the test that matters most — write it first.
3. **Adding and removing an account.** Patch from two accounts to three, then back to one; assert leg counts, and that going to one account leaves an ordinary single-account entry that `Audit.run` finds clean.

- [ ] **Step 2: Run to verify they fail**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter MultiAccountEditTests
```

Expected: all three FAIL with `error.tx.splitLegEdit` — the current refusal. **Confirm that is the actual failure**, not something else; if a different error fires first, the test is not reaching the code under change.

- [ ] **Step 3: Implement**

In `updateTransaction`, before the multi-leg refusal, add an `accounts` branch:

- Read the existing account postings once, keeping `id`, `amount`, `memo`, `cleared_at`, `orig_amount`, `orig_currency`, `exchange_rate`, ordered by `sort_order`.
- Build the new leg set from `patch.accounts`, matching each share to an existing posting **by `accountId`** (in sort order, so repeated accounts are deterministic) and carrying that posting's identity fields through. Unmatched shares become new legs; unmatched postings are dropped.
- Validate the shares the same way `addTransactionReturningId` does — **convert both sides to the ledger base**, tolerance `0.005 * (shares.count + 1)`. Reuse that code rather than restating it; a raw sum adds incomparable units the moment two accounts differ in currency, and a flat tolerance falsely rejects valid splits.
- Set `ep.legs = .set(...)` and let `rebuildEntry` do the rest, including auto-balancing the category leg.
- Leave the `splitLegEdit` refusal in place for money patches that **don't** carry `accounts` — a bare `amount` patch still cannot address a leg.

- [ ] **Step 4: Run to verify they pass**

Same command. Then the full suite:

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

- [ ] **Step 5: Commit**

```bash
git add ios/FinchCore/
git commit -m "feat(core): a split purchase can be edited as a whole"
```

---

### Task 2: Mirror it in the web stack

**Files:**
- Modify: `frontend/lib/db/queries/transactions.ts` — `updateTransaction`
- Test: `frontend/lib/db/multi-account.test.ts` (extend)

**Interfaces:**
- Consumes: Task 1's semantics exactly — same matching rule, same base-currency validation, same tolerance.

- [ ] **Step 1: Write the failing tests** — the same three behaviours as Task 1, in the web idiom. The reconcile-preservation test is the important one.
- [ ] **Step 2: Run to verify they fail**

```bash
cd frontend && bun install --frozen-lockfile && bun test lib/db/multi-account.test.ts
```

- [ ] **Step 3: Implement**, mirroring Task 1. Read the iOS version first and match its behaviour, including the comment explaining why identity is carried through.
- [ ] **Step 4: Verify**

```bash
cd frontend && bun run typecheck && bun run lint && bun test
```

- [ ] **Step 5: Commit**

```bash
git add frontend/
git commit -m "feat(web): a split purchase can be edited as a whole"
```

---

### Task 3: The Edit sheet shows the split editor (iOS)

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/EditTransactionSheet.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/` — an args test alongside `AccountSplitArgsTests`

**Interfaces:**
- Consumes: Task 1's `accounts` patch.
- Produces: the Edit sheet emits `accounts` when the entry has 2+ account legs or the user creates a split; single-account edits are byte-identical to today's.

**The editor already exists.** `SearchablePickerRow`'s `splitting:` parameter drives it in the Add sheet; `SplitAllocation` is axis-agnostic. Read `AddTransactionSheet`'s `accountAlloc` wiring and mirror it. Seed the allocation from the entry's existing legs with `SplitAllocation.merging(...)`, which arrives **pinned** so opening the sheet does not silently re-divide amounts the user set earlier — the same reason the category split uses it.

- [ ] **Step 1: Write the failing test**

Test the **args**, not the allocation model. The predecessor plan shipped a version of this feature where every expense split was rejected because the shares were unsigned while the stated amount was signed, and 407 green tests missed it — they all exercised `SplitAllocation`, which was already correct. Assert that an expense edit emits shares summing to the signed amount, and that `currency` is present.

- [ ] **Step 2: Run to verify it fails**

```bash
cd ios && xcodegen generate --spec project.yml,project-mac.yml
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" -derivedDataPath /tmp/dd \
  -only-testing:FinchAppTests -skipPackagePluginValidation -skipMacroValidation \
  COMPILER_INDEX_STORE_ENABLE=NO
```

- [ ] **Step 3: Implement.** Mirror the Add sheet. Keep the same constraints: emit `accounts` only at 2+ funded rows, sign the shares to match the stated amount, send `currency` explicitly, and restrict a split to one currency (the picker cannot yet display per-row currencies).
- [ ] **Step 4: Verify** — same command, then the full app suite.
- [ ] **Step 5: Localize** any new strings the UI route, reusing existing ones where they exist.
- [ ] **Step 6: Commit**

---

### Task 4: Parity coverage, gate, PR

- [ ] **Step 1: Add an edit-a-split step to `WRITE_SEQUENCE`** in `frontend/scripts/export-fixtures.ts` — create a split, then `updateTransaction` it with a changed `accounts` set. The oracle currently covers creating a split but never editing one.
- [ ] **Step 2: Regenerate and inspect**

```bash
cd frontend && bun scripts/export-fixtures.ts
git diff --stat ios/FinchCore/Tests/ParityTests/Fixtures/
```

A real diff is expected — you are adding sequence steps. Confirm it contains exactly your new rows; revert the wall-clock ULID/timestamp noise (`ios/README.md`).

**If the two stacks disagree, stop and report it. Do not adjust a fixture to make them agree** — that makes the oracle certify a bug permanently.

- [ ] **Step 3: Full gate**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/ci-local.sh
git checkout -- ios/FinchApp/Sources/FinchShared/Resources/Localizable.xcstrings
git status --porcelain   # expect clean
```

- [ ] **Step 4: PR against `feat/frontend`.** The body must state that editing a split rebuilds its postings, and that reconcile marks and posting ids are carried through — with the test that proves it named.

---

## Out of scope

- **Splitting categories *and* accounts on the same purchase.** This plan makes the accounts editable; the categories of a multi-account purchase remain a single category. That is not an oversight in this plan — `setTransactionSplits` deliberately refuses multi-account entries (added as a data-loss guard: it rebuilds from one account leg and would delete the others), and the Add sheet makes the two splits mutually exclusive for the same reason. Supporting both axes at once needs the account×category question answered first: with no pairing recorded, there is no way to say *which* account paid for *which* category. That was explicitly deferred when the feature was designed — a purchase where each account bought different things is two purchases sharing a receipt.
- **Editing a split on the web.** The web add form still has no split UI (deliberate); its edit form would need the same affordance designed first.
- **Per-row currencies in the editor.** A split stays single-currency until the picker can display and convert per row. The engine already accepts mixed.
- **Changing an entry's *kind* while it has several account legs.** Untouched; the existing refusal still applies.

## Verification checklist

- [ ] `ci-local.sh` prints `all checks passed`
- [ ] Catalog churn discarded; `git status --porcelain` clean
- [ ] `bun run typecheck && bun run lint && bun test` green
- [ ] Reconcile marks and posting ids provably survive an edit — on both stacks
- [ ] Editing a split down to one account leaves an entry `Audit.run` finds clean
- [ ] Every new test verified to fail with its fix reverted, output recorded
