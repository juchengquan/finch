import { test, expect } from 'bun:test';
import { balanceSeries, netWorthSeries, categorySpend } from '@/lib/select';
import type { Tx } from '@/lib/store';
import type { AccountRow } from '@/lib/db/queries/accounts';

const tx = (over: Partial<Tx>): Tx => ({
  id: Math.random().toString(36).slice(2),
  merchant: 'm',
  category: 'food',
  amount: -10,
  account: 'cc',
  date: '2026-05-01',
  pending: false,
  recurring: false,
  ledgerId: 'personal',
  ...over,
});

const acct = (over: Partial<AccountRow>): AccountRow => ({
  id: 'cc',
  ledgerId: 'personal',
  name: 'cc',
  type: 'credit_card',
  currency: 'USD',
  balance: 0,
  groupId: null,
  groupName: null,
  includeInNetWorth: 1,
  color: null,
  last4: null,
  institution: null,
  routing: null,
  ...over,
});

test('balanceSeries ends at the current balance and walks back to opening', () => {
  const txns = [tx({ amount: -10, date: '2026-05-01' }), tx({ amount: -20, date: '2026-05-02' })];
  const s = balanceSeries(txns, 'cc', 100);
  expect(s[0]).toBe(130); // opening = 100 − (−30)
  expect(s[s.length - 1]).toBe(100);
  expect(s.length).toBe(3);
});

test('balanceSeries only counts the requested account', () => {
  const txns = [tx({ amount: -10, account: 'cc' }), tx({ amount: -20, account: 'chk' })];
  const s = balanceSeries(txns, 'cc', 50);
  expect(s.length).toBe(2);
  expect(s[s.length - 1]).toBe(50);
});

test('netWorthSeries ends at the ledger total and ignores other ledgers', () => {
  const accounts = [acct({ id: 'cc', balance: 100 }), acct({ id: 'x', ledgerId: 'family', balance: 999 })];
  const txns = [tx({ amount: -10 }), tx({ amount: 50, ledgerId: 'family' })];
  const s = netWorthSeries(txns, accounts, 'personal');
  expect(s[s.length - 1]).toBe(100);
});

test('categorySpend excludes pending, transfers, and income', () => {
  const txns = [
    tx({ amount: -10, category: 'food' }),
    tx({ amount: -5, category: 'food', pending: true }),
    tx({ amount: -7, category: 'food', transferGroupId: 'tg1' }),
    tx({ amount: 20, category: 'food' }),
  ];
  expect(categorySpend(txns, 'personal').food).toBe(10);
});
