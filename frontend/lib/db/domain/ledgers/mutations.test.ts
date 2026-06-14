import { test, expect } from 'bun:test';
import { applyMutation } from '@/lib/db/mutate';
import { seededAndAudited, bareDb } from '@/lib/db/core/test-utils';
import { applySchema } from '@/lib/db/core/schema';
import { I18nError } from '@/lib/i18n-error';
import { convertToBase } from '@/lib/db/queries/rates';
import { listLedgers, deleteLedger } from '@/lib/db/queries/ledgers';

test('changeLedgerBase: rewrites amount_base under the new base using each txn date', async () => {
  const exec = await seededAndAudited();

  // The personal ledger seeds with USD base. Switch to SGD and verify each
  // transaction's amount_base now equals convertToBase(native, currency, SGD, date).
  const beforeLedger = (await listLedgers(exec)).find((l) => l.id === 'personal')!;
  expect(beforeLedger.base).toBe('USD');

  await applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'SGD' });

  const afterLedger = (await listLedgers(exec)).find((l) => l.id === 'personal')!;
  expect(afterLedger.base).toBe('SGD');

  // Spot-check the foreign JPY seed row (t-jpy-1, native ¥-3820 on 2026-05-13).
  // §2: amount/currency/amount_base/exchange_rate on the account posting.
  const [jpy] = await exec(
    "SELECT p.amount, p.currency, e.date, p.amount_base, p.exchange_rate FROM postings p JOIN entries e ON p.entry_id = e.id WHERE e.id = 't-jpy-1' AND p.account_id IS NOT NULL",
  );
  const expected = await convertToBase(exec, Number(jpy.amount), String(jpy.currency), 'SGD', String(jpy.date));
  expect(Number(jpy.amount_base)).toBeCloseTo(expected.amountBase, 2);
  expect(Number(jpy.exchange_rate)).toBeCloseTo(expected.rate, 6);

  // Spot-check a same-currency (SGD) row — rate should be 1, base = native.
  const [sgd] = await exec(
    "SELECT p.amount, p.amount_base, p.exchange_rate FROM postings p JOIN entries e ON p.entry_id = e.id WHERE e.ledger_id = 'personal' AND p.currency = 'SGD' AND p.account_id IS NOT NULL LIMIT 1",
  );
  if (sgd) {
    expect(Number(sgd.amount_base)).toBeCloseTo(Number(sgd.amount), 2);
    expect(Number(sgd.exchange_rate)).toBeCloseTo(1, 6);
  }
});

test('changeLedgerBase: same-base call is a no-op', async () => {
  const exec = await seededAndAudited();
  // §2: check postings (which carry amount_base, exchange_rate) instead of transactions.
  const before = await exec(
    "SELECT p.id, p.amount_base, p.exchange_rate FROM postings p JOIN entries e ON p.entry_id = e.id WHERE e.ledger_id = 'personal' ORDER BY p.id",
  );
  await applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'USD' });
  const after = await exec(
    "SELECT p.id, p.amount_base, p.exchange_rate FROM postings p JOIN entries e ON p.entry_id = e.id WHERE e.ledger_id = 'personal' ORDER BY p.id",
  );
  expect(JSON.stringify(after)).toBe(JSON.stringify(before));
});

test('changeLedgerBase: rejects malformed currency codes', async () => {
  const exec = await seededAndAudited();
  await expect(applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'usd' }))
    .resolves.toBeUndefined(); // case-insensitive: lowercased input is accepted (validator uppercases)
  await expect(applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'US' }))
    .rejects.toThrow(/3-letter/);
  await expect(applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'usd1' }))
    .rejects.toThrow(/3-letter/);
});

test('deleteLedger throws I18nError when ledger is not found', async () => {
  const exec = await seededAndAudited();
  await expect(deleteLedger(exec, 'ledger-nonexistent')).rejects.toThrow(I18nError);
});

test('deleteLedger throws I18nError when target is the last ledger', async () => {
  // Start from a minimal schema+ledger (the seed ships 4 ledgers; we can't
  // easily delete the others due to cascading FKs).
  const { exec, close } = await bareDb();
  try {
    await applySchema(exec);
    await exec(
      `INSERT INTO ledgers (id, name, base_currency, is_default, created_at, updated_at)
       VALUES ('solo', 'Solo', 'USD', 1, datetime('now'), datetime('now'))`,
    );
    await expect(deleteLedger(exec, 'solo')).rejects.toThrow(I18nError);
  } finally {
    close();
  }
});

test('changeLedgerBase re-stamps opening_balance_base for a foreign-currency account', async () => {
  const exec = await seededAndAudited();
  // §2: opening_balance/opening_balance_base columns are dropped from accounts.
  // Opening balances are stored as 'opening' entries + postings.
  // Use createAccount mutation to properly create the JPY account with an opening entry.
  // The seed's exchange_rates table has a JPY row on 2026-05-24 (0.0065 USD per JPY).
  await applyMutation(exec, 'createAccount', {
    id: 'jpyw', ledgerId: 'personal', name: 'JPY Wallet', type: 'cash', currency: 'JPY',
    openingBalance: 100000, openingDate: '2026-05-24', color: null,
  });
  // Verify the opening entry was created with a reasonable amount_base.
  const [acctPosting] = await exec(
    "SELECT p.amount_base FROM postings p JOIN entries e ON p.entry_id = e.id WHERE p.account_id = 'jpyw' AND e.kind = 'opening'",
  );
  // At 0.0065 USD/JPY, 100000 JPY ≈ 650 USD.
  expect(Number(acctPosting.amount_base)).toBeCloseTo(650, 0);
  // Flip the base to SGD. JPY → SGD via the USD pivot at the same creation
  // date should produce a new amount_base that's roughly
  // 100000 * 0.0065 / 0.7457 ≈ 871.7 SGD.
  await applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'SGD' });
  const [p] = await exec(
    "SELECT p.amount_base FROM postings p JOIN entries e ON p.entry_id = e.id WHERE p.account_id = 'jpyw' AND e.kind = 'opening'",
  );
  expect(Number(p.amount_base)).toBeCloseTo(871.7, 0); // ±1 SGD tolerance
  const [l] = await exec("SELECT base_currency FROM ledgers WHERE id = 'personal'");
  expect(String(l.base_currency)).toBe('SGD');
});

test('changeLedgerBase rewrites transaction_splits.amount_base under the new base', async () => {
  const exec = await seededAndAudited();
  // §2: splits are category postings (account_id IS NULL) on entries.
  // Pick any seed entry with a known account posting amount.
  const [tx] = await exec(
    "SELECT e.id, p.amount FROM entries e JOIN postings p ON p.entry_id = e.id AND p.account_id IS NOT NULL WHERE e.ledger_id = 'personal' AND e.kind = 'expense' AND e.status = 'confirmed' LIMIT 1",
  );
  const txId = String(tx.id);
  const amt = Number(tx.amount);
  await applyMutation(exec, 'setTransactionSplits', {
    id: txId,
    splits: [
      { categoryId: 'food', amount: amt / 2 },
      { categoryId: 'food', amount: amt / 2 },
    ],
  });
  // §2: category postings are the splits. Exclude any fx-system residue leg
  // (independent per-leg reconversion under the new base can add a rounding one).
  const splitLegs = (id: string) => exec(
    `SELECT p.amount_base FROM postings p LEFT JOIN categories c ON c.id = p.category_id
     WHERE p.entry_id = ? AND p.account_id IS NULL AND (c.system IS NULL OR c.system != 'fx')
     ORDER BY p.sort_order`,
    [id],
  );
  const before = await splitLegs(txId);
  // Flip the base to SGD and confirm the split's amount_base rewrote to match
  // the new base's conversion.
  await applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'SGD' });
  const after = await splitLegs(txId);
  expect(after.length).toBe(before.length);
  for (let i = 0; i < after.length; i++) {
    expect(Number(after[i].amount_base)).not.toBeCloseTo(Number(before[i].amount_base), 4);
  }
});

test('changeLedgerBase same-base call is a no-op (no row changes)', async () => {
  const exec = await seededAndAudited();
  // §2: check postings (which carry amount_base) instead of transactions.
  const before = await exec(
    "SELECT p.id, p.amount_base FROM postings p JOIN entries e ON p.entry_id = e.id WHERE e.ledger_id = 'personal' ORDER BY p.id",
  );
  await applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'USD' });
  const after = await exec(
    "SELECT p.id, p.amount_base FROM postings p JOIN entries e ON p.entry_id = e.id WHERE e.ledger_id = 'personal' ORDER BY p.id",
  );
  expect(after.length).toBe(before.length);
  for (let i = 0; i < after.length; i++) {
    expect(Number(after[i].amount_base)).toBeCloseTo(Number(before[i].amount_base), 6);
  }
});

test('createLedger appears in listLedgers with zero counts; new rows update counts', async () => {
  const exec = await seededAndAudited();

  await applyMutation(exec, 'createLedger', {
    id: 'studio', name: 'Studio', base: 'USD', color: '#8a6ba8', tagline: 'side projects',
  });
  let rows = await listLedgers(exec);
  const studio = rows.find((r) => r.id === 'studio');
  expect(studio).toBeTruthy();
  expect(studio!.name).toBe('Studio');
  expect(studio!.base).toBe('USD');
  expect(studio!.color).toBe('#8a6ba8');
  expect(studio!.accounts).toBe(0);
  expect(studio!.txns).toBe(0);

  // Add an account + a transaction under it; counts should reflect.
  await applyMutation(exec, 'createAccount', {
    id: 'st-chk', ledgerId: 'studio', name: 'Studio Checking', type: 'savings', currency: 'USD',
    openingBalance: 1000, color: null,
  });
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'studio', accountId: 'st-chk', amount: -10, amountBase: -10,
    currency: 'USD', merchant: 'coffee', categoryId: null, date: '2026-05-15', status: 'confirmed', kind: 'expense',
  });
  rows = await listLedgers(exec);
  const after = rows.find((r) => r.id === 'studio')!;
  expect(after.accounts).toBe(1);
  expect(after.txns).toBe(1);
});

test('createLedger rejects duplicate id, empty name, bad base', async () => {
  const exec = await seededAndAudited();
  await expect(
    applyMutation(exec, 'createLedger', { id: 'personal', name: 'Dup', base: 'USD' }),
  ).rejects.toThrow(/already exists/i);
  await expect(
    applyMutation(exec, 'createLedger', { id: 'x', name: '   ', base: 'USD' }),
  ).rejects.toThrow(/required/i);
  await expect(
    applyMutation(exec, 'createLedger', { id: 'x', name: 'Bad', base: 'us-d' }),
  ).rejects.toThrow(/3-letter/i);
});

test('updateLedger renames + recolors; changeLedgerBase still works after', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'updateLedger', {
    id: 'family', patch: { name: 'Household', color: '#3d6b46', tagline: 'shared' },
  });
  const [row] = await exec('SELECT name, color, tagline FROM ledgers WHERE id = ?', ['family']);
  expect(String(row.name)).toBe('Household');
  expect(String(row.color)).toBe('#3d6b46');
  expect(String(row.tagline)).toBe('shared');

  // Base change still works (and uses the new name in any logging).
  await applyMutation(exec, 'changeLedgerBase', { ledgerId: 'family', newBase: 'USD' });
  const [after] = await exec('SELECT base_currency FROM ledgers WHERE id = ?', ['family']);
  expect(String(after.base_currency)).toBe('USD');
});

test('updateLedger rejects empty name', async () => {
  const exec = await seededAndAudited();
  await expect(
    applyMutation(exec, 'updateLedger', { id: 'family', patch: { name: '   ' } }),
  ).rejects.toThrow(/empty/i);
});

test('setDefaultLedger flips exactly one is_default', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'setDefaultLedger', { id: 'business' });
  const rows = await exec('SELECT id, is_default FROM ledgers');
  const defaults = rows.filter((r) => Number(r.is_default) === 1);
  expect(defaults.length).toBe(1);
  expect(String(defaults[0].id)).toBe('business');
});

test('deleteLedger removes every ledger-scoped row and leaves siblings untouched', async () => {
  const exec = await seededAndAudited();
  // §2: entries replaces transactions as the ledger-scoped journal table.
  const beforePersonal = Number((await exec(
    "SELECT COUNT(*) AS n FROM entries WHERE ledger_id = 'personal'",
  ))[0].n);

  await applyMutation(exec, 'deleteLedger', { id: 'family' });

  // Every per-ledger table is empty for family. §2: entries/postings replace
  // transactions/transfer_groups/transaction_attachments.
  const tables = [
    'entries','scheduled_templates','budgets','budget_groups',
    'accounts','account_groups','categories','tags','counterparties',
    'rules','holdings',
  ];
  for (const t of tables) {
    const n = Number(
      (await exec(`SELECT COUNT(*) AS n FROM ${t} WHERE ledger_id = ?`, ['family']))[0].n,
    );
    expect(n).toBe(0);
  }
  // postings cascade from entries, not ledger-scoped directly — verify via entries.
  const familyPostings = Number(
    (await exec("SELECT COUNT(*) AS n FROM postings p JOIN entries e ON p.entry_id = e.id WHERE e.ledger_id = 'family'"))[0].n,
  );
  expect(familyPostings).toBe(0);
  // Other ledgers' data is untouched.
  const afterPersonal = Number((await exec(
    "SELECT COUNT(*) AS n FROM entries WHERE ledger_id = 'personal'",
  ))[0].n);
  expect(afterPersonal).toBe(beforePersonal);
  // The ledger row itself is gone.
  const ledgerLeft = await exec('SELECT id FROM ledgers WHERE id = ?', ['family']);
  expect(ledgerLeft.length).toBe(0);
});

test('deleteLedger of the default ledger promotes the first remaining by name', async () => {
  const exec = await seededAndAudited();
  // Seed has personal as default. The remaining ledger NAMES (not ids) sort:
  // "Family" (id=family), "Japan '26" (id=travel), "Side studio" (id=business).
  // First by name is "Family" -> id=family.
  await applyMutation(exec, 'deleteLedger', { id: 'personal' });
  const defaults = (await exec('SELECT id FROM ledgers WHERE is_default = 1')) as { id: string }[];
  expect(defaults.length).toBe(1);
  expect(String(defaults[0].id)).toBe('family');
});

test('deleteLedger cleans the displayCurrencyByLedger key', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'setDisplayCurrency', { ledgerId: 'business', currency: 'USD' });
  await applyMutation(exec, 'setDisplayCurrency', { ledgerId: 'family', currency: 'SGD' });
  await applyMutation(exec, 'deleteLedger', { id: 'business' });

  const { getAppState } = await import('@/lib/db/queries/appState');
  const raw = await getAppState(exec, 'displayCurrencyByLedger');
  expect(raw).toBeTruthy();
  const map = JSON.parse(raw!) as Record<string, string>;
  expect(map.business).toBeUndefined();
  expect(map.family).toBe('SGD');
});

test('deleteLedger refuses the last ledger', async () => {
  const exec = await seededAndAudited();
  // Reduce to a single ledger.
  for (const id of ['family', 'business', 'travel']) {
    await applyMutation(exec, 'deleteLedger', { id });
  }
  await expect(applyMutation(exec, 'deleteLedger', { id: 'personal' })).rejects.toThrow(/last ledger/i);
});
