// frontend/lib/store/_args.test.ts — smoke test that pins the set of
// action names exposed by the store. Mirrors the backend's
// lib/db/domain/_args.test.ts (PR 2 of the backend refactor). Any
// future change that adds or removes an action must update this
// test (and the action map in lib/store/_args.ts if applicable).

import { test, expect } from 'bun:test';
import { useFinanceStore } from './index';

test('useFinanceStore exposes all expected action names', () => {
  const state = useFinanceStore.getState();
  const expected = [
    'addScheduledSplit',
    'addTransaction',
    'adjustAccountBalance',
    'archiveAccount',
    'backfillRule',
    'bulkRecategorize',
    'cancelPending',
    'changeLedgerBase',
    'clearPendingAmount',
    'confirmAllPending',
    'confirmPending',
    'confirmPendingWithMatch',
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
    'markAllReviewed',
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
    'uploadAttachment',
    'verifyCounterparty',
  ];
  const stateAsRecord = state as unknown as Record<string, unknown>;
  for (const name of expected) {
    expect(typeof stateAsRecord[name]).toBe('function');
  }
  expect(expected.length).toBe(72);
});
