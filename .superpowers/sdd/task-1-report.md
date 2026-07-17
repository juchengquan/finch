# Task 1 report — engine: setBudgetOrder action + projection + unit test

**Status:** DONE
**Commit:** 15afdfc1bd08b69c1367e9fac64ee60fdfadfb20 (`feat/ios-budget-order`)

## Files
- `ios/FinchCore/Sources/FinchCore/Store/ActionName.swift` — `case setBudgetOrder` after `setDisplayCurrency`; app_state comment count 5→6.
- `ios/FinchCore/Sources/FinchCore/Store/Domain/App.swift` — handler entry + `setBudgetOrder` func (design-doc code, verbatim), after `setDisplayCurrency`.
- `ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift` — `budgetOrderByLedger(dbQueue:) -> [String: [String]]`, exact mirror of the `displayCurrencyByLedger` reader, key `'budgetOrderByLedger'`.
- `ios/FinchCore/Tests/FinchCoreTests/BudgetOrderTests.swift` — new; round-trip + second-ledger merge (no clobber) + re-set overwrite.
- `ios/FinchCore/Tests/FinchCoreTests/ArgsTests.swift` — **5th file, required**: `test_actionCount` hard-asserts `ActionName.allCases.count`; bumped 75→76 (that guard exists to be bumped when an action is added; leaving it would break the suite).

## Idiom adaptations (vs plan skeleton)
- `TestSeed.emptyDB()` → the suite's real helper `TestSeed.base()` (in-memory `DatabaseQueue` + `Migrations.runAll` + seed, ledger `l1`); ledger ids `l1`/`l2` per `DisplayCurrencyTests` style.
- `Apply.apply` takes a **String** action name (`action: "setBudgetOrder"`) — matched suite call style. `Args`/`.string`/`.array` literals as in the skeleton.
- Test run path: `swift test` works from `/tmp/finch-bo/ios` (the Package.swift root, NOT `ios/FinchCore/`) with `DEVELOPER_DIR` exported. `xcodebuild -only-testing:FinchCoreTests/...` does NOT work: FinchCoreTests is not in the FinchApp scheme (scheme tests only FinchAppTests) and the auto-generated FinchCore scheme has no test action.

## Verification
- `swift test --filter BudgetOrderTests` → `Executed 1 test, with 0 failures`.
- Full package suite: `Test Suite 'All tests' passed — Executed 267 tests, with 0 failures`.
- iOS build: `xcodebuild build -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` → `** BUILD SUCCEEDED **`.

No schema change (app_state KV only); no web/frontend or FinchApp-source edits.
