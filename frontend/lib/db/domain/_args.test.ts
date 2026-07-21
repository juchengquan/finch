import { test, expect, expectTypeOf } from 'bun:test';
import type { ActionName } from './_args';

// This test pins the shape of the `Args` map in lib/db/domain/_args.ts.
//
// The plan defers the actual dispatcher type-check (where
// `applyMutation(exec, action, args)` is constrained to
// `Args[ActionName]`) to PR 4, when the per-domain handlers and
// mutate.ts dispatcher are written. This test pins the SHAPE of the
// union so a future PR that adds/removes an action fails typecheck
// rather than silently drifting.

test('Args map has all 73 action names as keys', () => {
  const keys = [
    'addScheduledSplit',
    'addTransaction',
    'adjustAccountBalance',
    'archiveAccount',
    'backfillRule',
    'bulkRecategorize',
    'changeLedgerBase',
    'clearPendingAmount',
    'confirmAllPending',
    'confirmPendingWithMerchant',
    'confirmTransaction',
    'createAccount',
    'createAccountGroup',
    'createBudget',
    'createBudgetGroup',
    'createCategory',
    'createCounterparty',
    'createHolding',
    'createLedger',
    'createRule',
    'createScheduled',
    'createTag',
    'createTransfer',
    'deleteAccount',
    'deleteAccountGroup',
    'deleteBudgetGroup',
    'deleteCategory',
    'deleteCounterparty',
    'deleteExchangeRate',
    'deleteHolding',
    'deleteLedger',
    'deleteRule',
    'deleteScheduled',
    'deleteTag',
    'deleteTransaction',
    'deleteTransfer',
    'generateDueScheduled',
    'markAllReviewed',
    'postScheduled',
    'reconcileAccount',
    'removeAttachment',
    'removeBudget',
    'removeScheduledSplit',
    'reset',
    'setBackupFrequency',
    'setBackupRetention',
    'setCleared',
    'setDefaultLedger',
    'setDisplayCurrency',
    'setExchangeRate',
    'setHoldingPrice',
    'setMobileTabIds',
    'setReviewed',
    'setTransactionSplits',
    'setTransactionTags',
    'unarchiveAccount',
    'unverifyCounterparty',
    'updateAccount',
    'updateAccountGroup',
    'updateBudget',
    'updateBudgetCycle',
    'updateBudgetGroup',
    'updateCategory',
    'updateCounterparty',
    'updateHolding',
    'updateLedger',
    'updateRule',
    'updateScheduled',
    'updateScheduledSplit',
    'updateTag',
    'updateTransaction',
    'updateTransfer',
    'verifyCounterparty',
  ] as const;

  expect(keys.length).toBe(73);
  expectTypeOf<ActionName>().toEqualTypeOf<(typeof keys)[number]>();
});
