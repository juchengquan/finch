import { test, expect } from 'bun:test';
import { exportStateToBytes, importBytesToState } from '@/lib/db/sqlite';
import type { PersistState } from '@/lib/db/repo';

const sample: PersistState = {
  transactions: [{ id: 't01', merchant: 'Blue Bottle', category: 'food', amount: -6.75, account: 'cc', date: '2026-05-24', pending: false }],
  pending: [{ id: 'p1', merchant: 'Donki', amount: -82.4, currency: 'SGD', date: '2026-05-24', account: 'a', reason: 'verify', source: 'import' }],
  budgetOverrides: { food: 800 },
  verifiedExtra: ['cp-04'],
  aliasExtra: { 'cp-04': ['DDD'] },
  recurring: [],
};

test('export → import round-trips a .db byte array', async () => {
  const bytes = await exportStateToBytes(sample);
  expect(bytes.length).toBeGreaterThan(0);
  expect(bytes[0]).toBe(0x53); // SQLite files start with "SQLite format 3\0"
  const loaded = await importBytesToState(bytes);
  expect(loaded.transactions[0].amount).toBe(-6.75);
  expect(loaded.budgetOverrides.food).toBe(800);
  expect(loaded.aliasExtra['cp-04']).toEqual(['DDD']);
});
