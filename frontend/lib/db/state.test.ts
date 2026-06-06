import { test, expect } from 'bun:test';
import { buildState, projectState } from '@/lib/db/state';
import { applyMutation } from '@/lib/db/mutations';
import { listCounterparties } from '@/lib/db/queries/counterparties';
import { freshDb, seededDb } from '@/lib/db/test-utils';
import type { PersistState } from '@/lib/db/repo';

const sample: PersistState = {
  transactions: [
    { id: 't01', merchant: 'Blue Bottle', category: 'food', amount: -6.75, account: 'cc', date: '2026-05-24', time: '08:14', note: 'Cortado', pending: false },
    { id: 't03', merchant: 'Lyft', category: 'trans', amount: -18.4, account: 'cc', date: '2026-05-23', time: '14:01', pending: true },
    { id: 't05', merchant: 'Acme Payroll', category: null, amount: 2900, account: 'chk', date: '2026-05-22', time: '00:00', pending: false, kind: 'income' },
    { id: 'f01', merchant: 'FairPrice', category: 'f-grocery', amount: -128.4, account: 'f-dbs', date: '2026-05-24', pending: false, ledgerId: 'family' },
  ],
};

test('buildState + projectState recover the persisted transactions', async () => {
  const { exec } = await freshDb();
  await buildState(exec, sample);
  const loaded = await projectState(exec);
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

  // Seeded goals project as one-shot income budgets.
  expect(loaded.budgets.some((b) => b.type === 'income')).toBe(true);
  // Counterparty verify state lives on the table (no app_state shim).
  const cp04 = loaded.counterparties.find((c) => c.id === 'cp-04')!;
  expect(cp04.verified).toBe(false);
  expect(loaded.scheduled[0].splits?.[0].pct).toBe(60);
});

test('projected state carries accounts / categories / counterparties', async () => {
  const { exec } = await freshDb();
  await buildState(exec, sample);
  const loaded = await projectState(exec);
  expect(loaded.accounts.length).toBe(6);
  expect(loaded.accounts.find((a) => a.id === 'cc')?.name).toBe('Amex Gold');
  expect(typeof loaded.accounts[0].balance).toBe('number');
  expect(loaded.categories.length).toBe(19);
  expect(loaded.counterparties.length).toBeGreaterThan(0);
});

test('account balance reflects the live transaction set (not just the seed)', async () => {
  const { exec } = await freshDb();
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

test('counterparty verify + alias edits write the table (no app_state shim)', async () => {
  const { exec } = await seededDb();
  // cp-04 (Don Don Donki) is seeded unverified; flip it.
  await applyMutation(exec, 'verifyCounterparty', { id: 'cp-04' });
  let donki = (await listCounterparties(exec, 'personal')).find((c) => c.id === 'cp-04')!;
  expect(donki.verified).toBe(true);
  await applyMutation(exec, 'unverifyCounterparty', { id: 'cp-04' });
  donki = (await listCounterparties(exec, 'personal')).find((c) => c.id === 'cp-04')!;
  expect(donki.verified).toBe(false);
});

test('mobile bottom-bar tab ids round-trip through app_state', async () => {
  const { exec } = await seededDb();

  // Unset → projects as empty (the client applies its own default).
  expect((await projectState(exec)).mobileTabIds).toEqual([]);

  // Set → persists and projects back in order; non-string entries are dropped.
  await applyMutation(exec, 'setMobileTabIds', { ids: ['insights', 'goals', 'budgets', 7] });
  expect((await projectState(exec)).mobileTabIds).toEqual(['insights', 'goals', 'budgets']);

  // Overwrite replaces the prior value (single app_state row).
  await applyMutation(exec, 'setMobileTabIds', { ids: ['activity'] });
  expect((await projectState(exec)).mobileTabIds).toEqual(['activity']);
});

test('per-ledger display currency round-trips through app_state', async () => {
  const { exec } = await seededDb();

  // Unset → projects as an empty map (the client falls back to each ledger's base).
  expect((await projectState(exec)).displayCurrencyByLedger).toEqual({});

  // Setting one ledger persists just that entry.
  await applyMutation(exec, 'setDisplayCurrency', { ledgerId: 'personal', currency: 'EUR' });
  expect((await projectState(exec)).displayCurrencyByLedger).toEqual({ personal: 'EUR' });

  // A second ledger merges in without clobbering the first.
  await applyMutation(exec, 'setDisplayCurrency', { ledgerId: 'family', currency: 'JPY' });
  expect((await projectState(exec)).displayCurrencyByLedger).toEqual({ personal: 'EUR', family: 'JPY' });

  // Re-setting an existing ledger overwrites only that entry.
  await applyMutation(exec, 'setDisplayCurrency', { ledgerId: 'personal', currency: 'GBP' });
  expect((await projectState(exec)).displayCurrencyByLedger).toEqual({ personal: 'GBP', family: 'JPY' });
});
