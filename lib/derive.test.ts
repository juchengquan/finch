import { test, expect } from 'bun:test';
import { categorySpent, accountBalance, netWorth } from '@/lib/derive';
import seed from '@/data/transactions.json';
import categories from '@/data/categories.json';
import accounts from '@/data/accounts.json';
import type { Tx } from '@/lib/store';

const SEED = seed as Tx[];

test('categorySpent equals the baseline when the txns are exactly the seed', () => {
  const base = categories.find((c) => c.id === 'food')!.spent;
  expect(categorySpent(SEED, 'food')).toBeCloseTo(base, 2);
});

test('categorySpent increases by an added expense (delta)', () => {
  const base = categorySpent(SEED, 'food');
  const withExtra = [
    ...SEED,
    { id: 'x', merchant: 'X', category: 'food', amount: -50, account: 'cc', date: '2026-05-26' },
  ] as Tx[];
  expect(categorySpent(withExtra, 'food')).toBeCloseTo(base + 50, 2);
});

test('accountBalance equals the baseline for the seed', () => {
  const base = accounts.find((a) => a.id === 'cc')!.balance;
  expect(accountBalance(SEED, 'cc')).toBeCloseTo(base, 2);
});

test('accountBalance drops by a new expense on that account', () => {
  const base = accountBalance(SEED, 'cc');
  const withExtra = [
    ...SEED,
    { id: 'x', merchant: 'X', category: 'food', amount: -50, account: 'cc', date: '2026-05-26' },
  ] as Tx[];
  expect(accountBalance(withExtra, 'cc')).toBeCloseTo(base - 50, 2);
});

test('netWorth sums the account balances for the seed', () => {
  const total = accounts.reduce((s, a) => s + a.balance, 0);
  expect(netWorth(SEED)).toBeCloseTo(total, 2);
});
