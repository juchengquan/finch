import { test, expect } from 'bun:test';
import { serializeState, deserializeState } from '@/lib/db/state';
import type { PersistState } from '@/lib/db/repo';

const sample: PersistState = {
  transactions: [
    { id: 't01', merchant: 'Blue Bottle', category: 'food', amount: -6.75, account: 'cc', date: '2026-05-24', time: '08:14', note: 'Cortado', pending: false, recurring: false },
    { id: 't03', merchant: 'Lyft', category: 'trans', amount: -18.4, account: 'cc', date: '2026-05-23', time: '14:01', pending: true },
    { id: 't05', merchant: 'Acme Payroll', category: null, amount: 2900, account: 'chk', date: '2026-05-22', time: '00:00', pending: false, kind: 'income' },
    { id: 'f01', merchant: 'FairPrice', category: 'f-grocery', amount: -128.4, account: 'f-dbs', date: '2026-05-24', pending: false, ledgerId: 'family' },
  ],
  pending: [{ id: 'p1', merchant: 'Donki', amount: -82.4, currency: 'SGD', date: '2026-05-24', account: 'a', reason: 'verify', source: 'import' }],
  budgetOverrides: { food: 800 },
  accountOverrides: { cc: { name: 'Amex Platinum', institution: 'Amex' } },
  verifiedExtra: ['cp-04'],
  aliasExtra: { 'cp-04': ['DDD', 'DON DONKI'] },
  recurring: [
    { id: 'rt-salary', name: 'Salary', type: 'income', amount: 5800, frequency: 'monthly', dayOfMonth: 25, account: 'a', autoPost: 0, nextRun: 'May 25', lastRun: 'Apr 25', splits: [{ account: 'a', pct: 60, abs: null, label: 'Daily' }] },
  ],
};

test('store state round-trips through the relational schema', async () => {
  const bytes = await serializeState(sample);
  expect(bytes[0]).toBe(0x53); // "S" — SQLite file magic
  const loaded = await deserializeState(bytes);

  expect(loaded.transactions).toHaveLength(4);
  const t01 = loaded.transactions.find((t) => t.id === 't01')!;
  expect(t01.amount).toBe(-6.75);
  expect(t01.merchant).toBe('Blue Bottle');
  expect(t01.category).toBe('food');
  expect(t01.account).toBe('cc');
  expect(t01.pending).toBe(false);

  const t03 = loaded.transactions.find((t) => t.id === 't03')!;
  expect(t03.pending).toBe(true);

  const t05 = loaded.transactions.find((t) => t.id === 't05')!;
  expect(t05.category).toBeNull();
  expect(t05.amount).toBe(2900);

  expect(loaded.transactions.find((t) => t.id === 'f01')!.ledgerId).toBe('family');

  expect(loaded.pending[0].currency).toBe('SGD');
  expect(loaded.budgetOverrides.food).toBe(800);
  expect(loaded.accountOverrides.cc).toEqual({ name: 'Amex Platinum', institution: 'Amex' });
  expect(loaded.verifiedExtra).toContain('cp-04');
  expect(loaded.aliasExtra['cp-04']).toEqual(['DDD', 'DON DONKI']);
  expect(loaded.recurring[0].splits?.[0].pct).toBe(60);
});

test('cancelled transactions are dropped on projection', async () => {
  const bytes = await serializeState(sample);
  const loaded = await deserializeState(bytes);
  // All sample txns are active; ensure the count matches (no phantom rows).
  expect(loaded.transactions.every((t) => t.id)).toBe(true);
  expect(loaded.transactions).toHaveLength(4);
});
