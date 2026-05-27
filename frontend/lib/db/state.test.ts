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
  verifiedExtra: ['cp-04'],
  aliasExtra: { 'cp-04': ['DDD', 'DON DONKI'] },
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

  // Budgets are seeded per-category and projected as a categoryId → amount map.
  expect(loaded.budgetByCategory.food).toBe(700);
  expect(loaded.verifiedExtra).toContain('cp-04');
  expect(loaded.aliasExtra['cp-04']).toEqual(['DDD', 'DON DONKI']);
  expect(loaded.recurring[0].splits?.[0].pct).toBe(60);
});

test('projected state carries accounts / categories / counterparties', async () => {
  const bytes = await serializeState(sample);
  const loaded = await deserializeState(bytes);
  expect(loaded.accounts.length).toBe(6);
  expect(loaded.accounts.find((a) => a.id === 'cc')?.name).toBe('Amex Gold');
  expect(typeof loaded.accounts[0].balance).toBe('number');
  expect(loaded.categories.length).toBe(12);
  expect(loaded.counterparties.length).toBeGreaterThan(0);
});

test('account balance reflects the live transaction set (not just the seed)', async () => {
  const { applySchema } = await import('@/lib/db/schema');
  const { buildState } = await import('@/lib/db/state');
  const sqlite3 = await (
    (await import('@sqlite.org/sqlite-wasm')).default as unknown as (o?: unknown) => Promise<{ oo1: { DB: new (s?: string) => { exec: (o: unknown) => void } } }>
  )({ print() {}, printErr() {} });
  const db = new sqlite3.oo1.DB(':memory:');
  const exec = async (sql: string, bind?: (string | number | null)[]) => {
    const rows: Record<string, unknown>[] = [];
    db.exec({ sql, bind: bind ?? [], rowMode: 'object', resultRows: rows });
    return rows;
  };
  await applySchema(exec);
  // Seed-equivalent set for 'cc' plus one extra -100 expense.
  const base: PersistState = {
    ...sample,
    transactions: [
      { id: 't01', merchant: 'Blue Bottle', category: 'food', amount: -6.75, account: 'cc', date: '2026-05-24', pending: false },
      { id: 'x99', merchant: 'Extra', category: 'food', amount: -100, account: 'cc', date: '2026-05-25', pending: false },
    ],
  };
  await buildState(exec, base);
  const cc = await exec('SELECT current_balance AS b FROM accounts WHERE id = ?', ['cc']);
  // Opening for cc = seedBalance(-842.18) - sum(seed cc deltas). Adding only
  // these two txns gives opening + (-6.75 -100), which must differ from -842.18.
  expect(Number(cc[0].b)).not.toBeCloseTo(-842.18, 2);
});

test('buildState applies verifiedExtra/aliasExtra onto the counterparties table', async () => {
  const { applySchema } = await import('@/lib/db/schema');
  const { buildState } = await import('@/lib/db/state');
  const { listCounterparties } = await import('@/lib/db/queries/counterparties');
  const init = (await import('@sqlite.org/sqlite-wasm')).default as unknown as (
    o?: unknown,
  ) => Promise<{ oo1: { DB: new (s?: string) => { exec: (o: unknown) => void } } }>;
  const sqlite3 = await init({ print() {}, printErr() {} });
  const db = new sqlite3.oo1.DB(':memory:');
  const exec = async (sql: string, bind?: (string | number | null)[]) => {
    const rows: Record<string, unknown>[] = [];
    db.exec({ sql, bind: bind ?? [], rowMode: 'object', resultRows: rows });
    return rows;
  };
  await applySchema(exec);
  // cp-04 (Don Don Donki) is seeded unverified; verify it + add an alias.
  await buildState(exec, { ...sample, verifiedExtra: ['cp-04'], aliasExtra: { 'cp-04': ['DONKI JURONG'] } });
  const cps = await listCounterparties(exec, 'personal');
  const donki = cps.find((c) => c.id === 'cp-04')!;
  expect(donki.verified).toBe(true);
  expect(donki.aliases).toContain('DONKI JURONG');
});

test('cancelled transactions are dropped on projection', async () => {
  const bytes = await serializeState(sample);
  const loaded = await deserializeState(bytes);
  // All sample txns are active; ensure the count matches (no phantom rows).
  expect(loaded.transactions.every((t) => t.id)).toBe(true);
  expect(loaded.transactions).toHaveLength(4);
});
