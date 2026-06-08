import { test, expect } from 'bun:test';
import { reconcileState } from '@/lib/reconcile';
import type { Tx } from '@/lib/store';
import type { AccountRow } from '@/lib/db/queries/accounts';

const tx = (over: Partial<Tx>): Tx => ({
  id: Math.random().toString(36).slice(2),
  merchant: 'm',
  category: 'food',
  amount: -10,
  account: 'chk',
  date: '2026-05-01',
  pending: false,
  ledgerId: 'personal',
  ...over,
});

const acct = (over: Partial<AccountRow>): AccountRow => ({
  id: 'chk',
  ledgerId: 'personal',
  name: 'Checking',
  type: 'cash',
  currency: 'USD',
  balance: 0,
  openingBalance: 0,
  openingBalanceBase: 0,
  groupId: null,
  groupName: null,
  includeInNetWorth: 1,
  isActive: true,
  color: null,
  sortOrder: 0,
  lastReconciledAt: null,
  lastReconciledBalance: null,
  archivedAt: null,
  ...over,
});

test('reconcileState: cleared sum + balanced gate', () => {
  // opening $100, two cleared expenses of $25 + $10 → cleared $65; statement $65 → balanced.
  const a = acct({ openingBalance: 100 });
  const txns = [
    tx({ id: 'a', amount: -25, clearedAt: '2026-05-31T12:00:00Z' }),
    tx({ id: 'b', amount: -10, clearedAt: '2026-05-31T12:00:00Z' }),
  ];
  const s = reconcileState(a, txns, 65);
  expect(s.clearedBalance).toBe(65);
  expect(s.difference).toBe(0);
  expect(s.balanced).toBe(true);
  expect(s.clearedCount).toBe(2);
  expect(s.unclearedCount).toBe(0);
});

test('reconcileState: uncleared rows do not enter the running balance', () => {
  const a = acct({ openingBalance: 100 });
  const txns = [
    tx({ id: 'a', amount: -25, clearedAt: '2026-05-31T12:00:00Z' }),
    tx({ id: 'b', amount: -10 }), // not cleared
    tx({ id: 'c', amount: -7.50, clearedAt: '2026-05-31T12:00:00Z' }),
  ];
  const s = reconcileState(a, txns, 67.5);
  expect(s.clearedBalance).toBe(67.5);
  expect(s.clearedCount).toBe(2);
  expect(s.unclearedCount).toBe(1);
  expect(s.balanced).toBe(true);
});

test('reconcileState: pending rows never count, even when "cleared"', () => {
  // A pending row with cleared_at would be a UI mistake; the math defensively
  // excludes it so a half-finished workflow can't poison the cleared balance.
  const a = acct({ openingBalance: 100 });
  const txns = [
    tx({ id: 'a', amount: -25, clearedAt: '2026-05-31T12:00:00Z' }),
    tx({ id: 'p', amount: -50, pending: true, clearedAt: '2026-05-31T12:00:00Z' }),
  ];
  const s = reconcileState(a, txns, 75);
  expect(s.clearedBalance).toBe(75);
  expect(s.clearedCount).toBe(1);
  expect(s.unclearedCount).toBe(0); // pending excluded from both buckets
});

test('reconcileState: penny tolerance', () => {
  const a = acct({ openingBalance: 100 });
  const txns = [tx({ amount: -33.33, clearedAt: '2026-05-31T12:00:00Z' })];
  // statement balance off by 0.002 — within tolerance.
  const s = reconcileState(a, txns, 66.668);
  expect(s.balanced).toBe(true);
});

test('reconcileState: only the requested account is walked', () => {
  const a = acct({ id: 'chk', openingBalance: 100 });
  const txns = [
    tx({ account: 'chk', amount: -25, clearedAt: '2026-05-31T12:00:00Z' }),
    tx({ account: 'sav', amount: -1000, clearedAt: '2026-05-31T12:00:00Z' }),
  ];
  const s = reconcileState(a, txns, 75);
  expect(s.balanced).toBe(true); // 100 − 25 = 75; the sav row is ignored.
  expect(s.clearedCount).toBe(1);
});

test('reconcileState: foreign-currency row uses ledger-base amount (matches recomputeAccount)', () => {
  // USD account; a row already in USD walks native; a row in JPY walks the
  // ledger-base figure (same as the live recompute path).
  const a = acct({ openingBalance: 1000, currency: 'USD' });
  const usd = tx({ amount: -50, nativeAmount: -50, currency: 'USD', clearedAt: 'X' });
  const jpyRow = tx({ amount: -30, nativeAmount: -4500, currency: 'JPY', clearedAt: 'X' });
  const s = reconcileState(a, [usd, jpyRow], 920);
  // 1000 − 50 (USD) − 30 (JPY's amount_base) = 920.
  expect(s.clearedBalance).toBe(920);
  expect(s.balanced).toBe(true);
});

test('reconcileState: adding + clearing a missing row closes the difference (v2 flow)', () => {
  // opening $100, one cleared −$25 → cleared $75; statement says $50, so we're
  // $25 over → there's a missing −$25 expense not yet logged. Modelling the
  // §10.2 quick-add: append that row already cleared, and the gap closes.
  const a = acct({ openingBalance: 100 });
  const before = reconcileState(a, [tx({ id: 'a', amount: -25, clearedAt: 'x' })], 50);
  expect(before.difference).toBe(-25); // statement − cleared = 50 − 75
  expect(before.balanced).toBe(false);

  const after = reconcileState(
    a,
    [tx({ id: 'a', amount: -25, clearedAt: 'x' }), tx({ id: 'missing', amount: -25, clearedAt: 'now' })],
    50,
  );
  expect(after.clearedBalance).toBe(50);
  expect(after.difference).toBe(0);
  expect(after.balanced).toBe(true);
  expect(after.clearedCount).toBe(2);
});
