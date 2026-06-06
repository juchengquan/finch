import { test, expect } from 'bun:test';
import { listAccounts, netWorth, updateAccount, createAccount, archiveAccount } from '@/lib/db/queries/accounts';
import { listCategories, monthlyByCategory, categorySpend } from '@/lib/db/queries/categories';
import { listCounterparties, searchCounterparties, verifyCounterparty } from '@/lib/db/queries/counterparties';
import { seededDb } from '@/lib/db/test-utils';
import type { Exec } from '@/lib/db/repo';

// Confirmed, non-transfer/-adjustment cash flow for a month. Inlined here (and
// in mutations.test.ts) after the production monthlyCashFlow query was retired —
// no screen consumed it; it survives only as a test assertion of the amount_base
// + kind bookkeeping.
async function monthlyCashFlow(exec: Exec, ledgerId: string, yearMonth: string) {
  const rows = await exec(
    `SELECT
       SUM(CASE WHEN kind = 'income' THEN amount_base ELSE 0 END) AS income,
       SUM(CASE WHEN kind IN ('expense','refund') THEN amount_base ELSE 0 END) AS expense,
       SUM(amount_base) AS net
     FROM transactions
     WHERE ledger_id = ? AND date LIKE ? AND kind NOT IN ('transfer','adjustment') AND status = 'confirmed'`,
    [ledgerId, `${yearMonth}%`],
  );
  const r = rows[0] ?? {};
  return { income: Number(r.income ?? 0), expense: Number(r.expense ?? 0), net: Number(r.net ?? 0) };
}

async function seeded(): Promise<Exec> {
  const { exec } = await seededDb();
  return exec;
}

test('accounts: list, net worth, balance series, edit', async () => {
  const exec = await seeded();
  const accts = await listAccounts(exec, 'personal');
  expect(accts.length).toBe(4); // chk, sav, cc, inv
  const cc = accts.find((a) => a.id === 'cc')!;
  expect(cc.groupName).toBe('Credit Cards');
  expect(cc.includeInNetWorth).toBe(0); // credit_card type excluded by default

  // Net worth excludes the credit card group (-842.18), so it's assets only.
  const nw = await netWorth(exec, 'personal');
  expect(nw).toBeCloseTo(4218.5 + 8120 + 21430, 2);

  // Display columns are seeded from data/accounts.json.
  expect(cc.name).toBe('Amex Gold');
  expect(cc.color).toBe('#3a2d1f');

  await updateAccount(exec, 'cc', { name: 'Amex Platinum' });
  const updated = await listAccounts(exec, 'personal');
  const ccu = updated.find((a) => a.id === 'cc')!;
  expect(ccu.name).toBe('Amex Platinum');
});

test('accounts: create, then archive removes from the active list', async () => {
  const exec = await seeded();
  await createAccount(exec, {
    id: 'acct-new', ledgerId: 'personal', name: 'Wise USD', type: 'cash',
    currency: 'USD', groupId: 'cash', openingBalance: 500, color: '#123456',
  });
  let accts = await listAccounts(exec, 'personal');
  const created = accts.find((a) => a.id === 'acct-new')!;
  expect(created.name).toBe('Wise USD');
  expect(created.balance).toBeCloseTo(500, 2);

  await archiveAccount(exec, 'acct-new');
  accts = await listAccounts(exec, 'personal');
  expect(accts.find((a) => a.id === 'acct-new')).toBeUndefined();

  // archived_at is stamped so the audit trail survives the soft-delete.
  const [archived] = await exec("SELECT is_active, archived_at FROM accounts WHERE id = 'acct-new'");
  expect(Number(archived.is_active)).toBe(0);
  expect(archived.archived_at).not.toBeNull();
});

test('accounts: createAccount assigns an incrementing sort_order within the same group', async () => {
  const exec = await seeded();
  await createAccount(exec, {
    id: 'acct-a', ledgerId: 'personal', name: 'A', type: 'cash',
    currency: 'USD', groupId: 'cash', openingBalance: 0, color: null,
  });
  await createAccount(exec, {
    id: 'acct-b', ledgerId: 'personal', name: 'B', type: 'cash',
    currency: 'USD', groupId: 'cash', openingBalance: 0, color: null,
  });
  const accts = await listAccounts(exec, 'personal');
  const a = accts.find((x) => x.id === 'acct-a')!;
  const b = accts.find((x) => x.id === 'acct-b')!;
  expect(b.sortOrder).toBeGreaterThan(a.sortOrder);
});

test('categories: list + monthly spend', async () => {
  const exec = await seeded();
  expect((await listCategories(exec, 'personal')).length).toBe(15); // 8 top-level + 7 demo subcategories
  const spend = await monthlyByCategory(exec, 'personal', '2026-05');
  const food = spend.find((c) => c.id === 'food')!;
  expect(food.spent).toBeGreaterThan(0);
  // Food spend should equal the sum of confirmed food expenses.
  expect(food.spent).toBeCloseTo(6.75 + 84.32 + 42.18 + 14.2 + 29.84, 2);

  // All-time map spans the full seed history — the prior-year `h*` rows
  // (groceries + dining) push the total well above the original Mar/Apr/May
  // sum; assert at least that minimum so it stays a meaningful regression test.
  const map = await categorySpend(exec, 'personal');
  expect(map.food).toBeGreaterThanOrEqual(6.75 + 84.32 + 42.18 + 14.2 + 29.84 + 132.8 + 96.5);
});

test('categories: 2-level tree — parent_id wires children, build+rollup behave', async () => {
  const exec = await seeded();
  const { buildCategoryTree, rollupCategorySpend } = await import('@/lib/db/queries/categories');
  const cats = await listCategories(exec, 'personal');

  // Seeded demo children carry their parent id.
  const groceries = cats.find((c) => c.id === 'food-groceries')!;
  expect(groceries.parentId).toBe('food');
  const food = cats.find((c) => c.id === 'food')!;
  expect(food.parentId).toBeNull();

  // Tree groups children under their parent; childless parents come back with [].
  const tree = buildCategoryTree(cats);
  const foodNode = tree.find((n) => n.parent.id === 'food')!;
  expect(foodNode.children.map((c) => c.id).sort()).toEqual(
    ['food-coffee', 'food-groceries', 'food-restaurants'].sort(),
  );
  expect(tree.find((n) => n.parent.id === 'rent')!.children).toEqual([]);

  // rollupCategorySpend folds child totals into the parent bucket.
  const rolled = rollupCategorySpend({ food: 10, 'food-groceries': 30, 'food-coffee': 5 }, cats);
  expect(rolled.food).toBe(10 + 30 + 5);
  expect(rolled['food-groceries']).toBe(30); // children keep their own line too
});

test('createCategory rejects nesting under a row that already has a parent (no 3-level)', async () => {
  const exec = await seeded();
  const { applyMutation } = await import('@/lib/db/mutations');
  await expect(
    applyMutation(exec, 'createCategory', {
      ledgerId: 'personal', name: 'Espresso', parentId: 'food-coffee',
    }),
  ).rejects.toThrow(/two levels/i);
});

test('deleteCategory promotes children to top-level (ON DELETE SET NULL)', async () => {
  const exec = await seeded();
  const { applyMutation } = await import('@/lib/db/mutations');
  // 'food' has demo children. Delete it; the children should survive as top-level.
  await applyMutation(exec, 'deleteCategory', { id: 'food' });
  const after = await listCategories(exec, 'personal');
  const groceries = after.find((c) => c.id === 'food-groceries')!;
  expect(groceries).toBeTruthy();
  expect(groceries.parentId).toBeNull();
});

test('counterparties: list, search, verify, alias', async () => {
  const exec = await seeded();
  expect((await listCounterparties(exec, 'personal')).length).toBeGreaterThan(0);

  const grab = await searchCounterparties(exec, 'personal', 'GRAB');
  expect(grab.some((c) => c.name === 'Grab')).toBe(true);

  const donki = (await listCounterparties(exec, 'personal')).find((c) => c.id === 'cp-04')!;
  expect(donki.verified).toBe(false);
  await verifyCounterparty(exec, 'cp-04');
  const after = (await listCounterparties(exec, 'personal')).find((c) => c.id === 'cp-04')!;
  expect(after.verified).toBe(true);
});

test('counterparty FK: addTransaction links exact name (case-insensitive), null on no match', async () => {
  const exec = await seeded();
  const { addTransaction } = await import('@/lib/db/queries/transactions');

  const matched = await addTransaction(exec, {
    ledgerId: 'personal', accountId: 'chk', amount: -10,
    merchant: 'grab', // lowercase — exists as 'Grab' (cp-02)
    date: '2026-05-25',
  });
  const [m] = await exec('SELECT counterparty_id FROM transactions WHERE id = ?', [matched]);
  expect(String(m.counterparty_id)).toBe('cp-02');

  const unmatched = await addTransaction(exec, {
    ledgerId: 'personal', accountId: 'chk', amount: -10,
    merchant: 'Random Shop That Has No Catalog Entry',
    date: '2026-05-25',
  });
  const [u] = await exec('SELECT counterparty_id FROM transactions WHERE id = ?', [unmatched]);
  expect(u.counterparty_id).toBeNull();
});

test('counterparty FK: renaming a counterparty makes projectState surface the canonical name', async () => {
  const exec = await seeded();
  const { addTransaction } = await import('@/lib/db/queries/transactions');
  const { applyMutation } = await import('@/lib/db/mutations');
  const { projectState } = await import('@/lib/db/state');

  // Insert a row that links to Grab (cp-02).
  await addTransaction(exec, {
    ledgerId: 'personal', accountId: 'chk', amount: -8,
    merchant: 'Grab', date: '2026-05-25',
  });

  // Rename the catalog entry; projected merchant should follow the new name
  // even though `transactions.description` is unchanged.
  await applyMutation(exec, 'updateCounterparty', { id: 'cp-02', patch: { name: 'Grab Mobility' } });
  const projected = await projectState(exec);
  const tx = projected.transactions.find((t) => t.counterpartyId === 'cp-02')!;
  expect(tx).toBeTruthy();
  expect(tx.merchant).toBe('Grab Mobility');
});

test('counterparty FK: updateTransaction re-resolves when merchant text changes', async () => {
  const exec = await seeded();
  const { addTransaction, updateTransaction } = await import('@/lib/db/queries/transactions');

  // Start with a row linked to Grab (cp-02).
  const txId = await addTransaction(exec, {
    ledgerId: 'personal', accountId: 'chk', amount: -8,
    merchant: 'Grab', date: '2026-05-25',
  });
  let [row] = await exec('SELECT counterparty_id FROM transactions WHERE id = ?', [txId]);
  expect(String(row.counterparty_id)).toBe('cp-02');

  // Rename merchant to a non-catalog string; link should drop to NULL.
  await updateTransaction(exec, txId, { merchant: 'Some One-off Vendor' });
  [row] = await exec('SELECT counterparty_id FROM transactions WHERE id = ?', [txId]);
  expect(row.counterparty_id).toBeNull();

  // Rename to a known catalog name; link should re-establish.
  await updateTransaction(exec, txId, { merchant: 'Apple' }); // cp-05
  [row] = await exec('SELECT counterparty_id FROM transactions WHERE id = ?', [txId]);
  expect(String(row.counterparty_id)).toBe('cp-05');
});

test('counterparty FK: deleting a counterparty leaves linked transactions intact (SET NULL)', async () => {
  const exec = await seeded();
  const { addTransaction } = await import('@/lib/db/queries/transactions');
  const { applyMutation } = await import('@/lib/db/mutations');

  const txId = await addTransaction(exec, {
    ledgerId: 'personal', accountId: 'chk', amount: -8,
    merchant: 'Grab', date: '2026-05-25',
  });
  await applyMutation(exec, 'deleteCounterparty', { id: 'cp-02' });
  const [row] = await exec('SELECT counterparty_id, description FROM transactions WHERE id = ?', [txId]);
  expect(row.counterparty_id).toBeNull();
  expect(String(row.description)).toBe('Grab');
});

test('changeLedgerBase: rewrites amount_base under the new base using each txn date', async () => {
  const exec = await seeded();
  const { applyMutation } = await import('@/lib/db/mutations');
  const { convertToBase } = await import('@/lib/db/queries/rates');
  const { listLedgers } = await import('@/lib/db/queries/ledgers');

  // The personal ledger seeds with USD base. Switch to SGD and verify each
  // transaction's amount_base now equals convertToBase(native, currency, SGD, date).
  const beforeLedger = (await listLedgers(exec)).find((l) => l.id === 'personal')!;
  expect(beforeLedger.base).toBe('USD');

  await applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'SGD' });

  const afterLedger = (await listLedgers(exec)).find((l) => l.id === 'personal')!;
  expect(afterLedger.base).toBe('SGD');

  // Spot-check the foreign JPY seed row (t-jpy-1, native ¥-3820 on 2026-05-13).
  const [jpy] = await exec("SELECT amount, currency, date, amount_base, exchange_rate FROM transactions WHERE id = 't-jpy-1'");
  const expected = await convertToBase(exec, Number(jpy.amount), String(jpy.currency), 'SGD', String(jpy.date));
  expect(Number(jpy.amount_base)).toBeCloseTo(expected.amountBase, 2);
  expect(Number(jpy.exchange_rate)).toBeCloseTo(expected.rate, 6);

  // Spot-check a same-currency row (any USD row) — rate should be 1, base = native.
  const [usd] = await exec("SELECT id, amount, amount_base, exchange_rate FROM transactions WHERE ledger_id = 'personal' AND currency = 'SGD' LIMIT 1");
  if (usd) {
    expect(Number(usd.amount_base)).toBeCloseTo(Number(usd.amount), 2);
    expect(Number(usd.exchange_rate)).toBeCloseTo(1, 6);
  }
});

test('changeLedgerBase: same-base call is a no-op', async () => {
  const exec = await seeded();
  const { applyMutation } = await import('@/lib/db/mutations');
  const before = await exec("SELECT id, amount_base, exchange_rate FROM transactions WHERE ledger_id = 'personal' ORDER BY id");
  await applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'USD' });
  const after = await exec("SELECT id, amount_base, exchange_rate FROM transactions WHERE ledger_id = 'personal' ORDER BY id");
  expect(JSON.stringify(after)).toBe(JSON.stringify(before));
});

test('changeLedgerBase: rejects malformed currency codes', async () => {
  const exec = await seeded();
  const { applyMutation } = await import('@/lib/db/mutations');
  await expect(applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'usd' }))
    .resolves.toBeUndefined(); // case-insensitive: lowercased input is accepted (validator uppercases)
  await expect(applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'US' }))
    .rejects.toThrow(/3-letter/);
  await expect(applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'usd1' }))
    .rejects.toThrow(/3-letter/);
});

test('reports: monthly cash flow', async () => {
  const exec = await seeded();
  const cf = await monthlyCashFlow(exec, 'personal', '2026-05');
  expect(cf.income).toBeCloseTo(2900, 2);
  expect(cf.expense).toBeLessThan(0);
  expect(cf.net).toBeCloseTo(cf.income + cf.expense, 2);
});

test('addTransaction: exact-name match sets counterparty_id, projection rewrites merchant to canonical', async () => {
  const exec = await seeded();
  const { addTransaction } = await import('@/lib/db/queries/transactions');
  const { projectState } = await import('@/lib/db/state');
  // A raw "Grab" description links to cp-02 at insert time. The projection
  // then surfaces the canonical name on `merchant` (overriding the raw
  // description), and the FK is preserved.
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -3,
    merchant: 'Grab',
    date: '2026-05-25',
  });
  const [row] = await exec('SELECT description, counterparty_id FROM transactions WHERE id = ?', [txId]);
  expect(String(row.description)).toBe('Grab');
  expect(String(row.counterparty_id)).toBe('cp-02');
  const projected = await projectState(exec);
  const tx = projected.transactions.find((t) => t.id === txId)!;
  expect(tx.counterpartyId).toBe('cp-02');
  expect(tx.merchant).toBe('Grab'); // canonical name == the raw here
});

test('addTransaction: catalog rename rewrites all linked rows on the next projection', async () => {
  const exec = await seeded();
  const { addTransaction } = await import('@/lib/db/queries/transactions');
  const { updateCounterparty } = await import('@/lib/db/queries/counterparties');
  const { projectState } = await import('@/lib/db/state');
  // Insert a row, then rename the counterparty. The row's stored description
  // is untouched (the catalog is the source of truth, not transactions).
  // The projection overrides merchant with the new canonical name on read.
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -3,
    merchant: 'Grab',
    date: '2026-05-25',
  });
  await updateCounterparty(exec, 'cp-02', { name: 'Grab Holdings' });
  const projected = await projectState(exec);
  const tx = projected.transactions.find((t) => t.id === txId)!;
  expect(tx.merchant).toBe('Grab Holdings');
  expect(tx.counterpartyId).toBe('cp-02');
});

test('addTransaction: unknown name leaves counterparty_id null (no auto-create)', async () => {
  const exec = await seeded();
  const { addTransaction } = await import('@/lib/db/queries/transactions');
  // A brand-new name like "BLUE BOTTLE COFFEE" doesn't match the catalog, so
  // the row is inserted unlinked. The matcher/picker is responsible for
  // creating the counterparty and linking it later (via
  // confirmPendingWithMerchant or a future Add-Expense pre-link).
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -12.5,
    merchant: 'BLUE BOTTLE COFFEE',
    date: '2026-05-25',
  });
  const [row] = await exec('SELECT description, counterparty_id FROM transactions WHERE id = ?', [txId]);
  expect(String(row.description)).toBe('BLUE BOTTLE COFFEE');
  expect(row.counterparty_id).toBeNull();
});

test('addTransaction: explicit counterpartyId links the row to that counterparty', async () => {
  const exec = await seeded();
  const { addTransaction } = await import('@/lib/db/queries/transactions');
  // Pass a raw merchant string that wouldn't match by name. The explicit
  // counterpartyId forces the link, and the projection surfaces the canonical
  // name on `merchant` regardless of the raw description.
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -8,
    merchant: 'APPLE.COM/BILL',
    date: '2026-05-25',
    counterpartyId: 'cp-05', // Apple (verified, seeded)
  });
  const [row] = await exec('SELECT description, counterparty_id FROM transactions WHERE id = ?', [txId]);
  expect(String(row.description)).toBe('APPLE.COM/BILL');
  expect(String(row.counterparty_id)).toBe('cp-05');
  // Projection surfaces the canonical name on the merchant field.
  const { projectState } = await import('@/lib/db/state');
  const projected = await projectState(exec);
  const tx = projected.transactions.find((t) => t.id === txId)!;
  expect(tx.merchant).toBe('Apple');
  expect(tx.counterpartyId).toBe('cp-05');
});

test('addTransaction: explicit counterpartyId is rejected if it belongs to a different ledger', async () => {
  const exec = await seeded();
  const { addTransaction } = await import('@/lib/db/queries/transactions');
  // Spin up a second ledger + counterparty; passing its id to an
  // addTransaction for the 'personal' ledger must not link.
  await exec(
    "INSERT INTO ledgers (id, name, base_currency, is_default, created_at, updated_at) VALUES ('biz', 'Business', 'SGD', 0, datetime('now'), datetime('now'))",
  );
  const otherCpId = 'cp-other-ledger';
  await exec(
    "INSERT INTO counterparties (id, ledger_id, name, is_verified, created_at, updated_at) VALUES (?, 'biz', ?, 1, datetime('now'), datetime('now'))",
    [otherCpId, 'Foreign Ledger Merchant'],
  );
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -5,
    merchant: 'Raw Merchant String',
    date: '2026-05-25',
    counterpartyId: otherCpId,
  });
  const [row] = await exec('SELECT description, counterparty_id FROM transactions WHERE id = ?', [txId]);
  expect(row.counterparty_id).toBeNull();
  expect(String(row.description)).toBe('Raw Merchant String');
});

test('addTransaction: no counterpartyId + exact name match → auto-resolve', async () => {
  const exec = await seeded();
  const { addTransaction } = await import('@/lib/db/queries/transactions');
  // "Grab" (capitalised) still auto-resolves to cp-02 the legacy way when
  // counterpartyId is omitted.
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -3,
    merchant: 'Grab',
    date: '2026-05-25',
  });
  const [row] = await exec('SELECT description, counterparty_id FROM transactions WHERE id = ?', [txId]);
  expect(String(row.description)).toBe('Grab');
  expect(String(row.counterparty_id)).toBe('cp-02');
});

test('confirmPendingWithMerchant: links + rewrites description in one round-trip', async () => {
  const exec = await seeded();
  const { addTransaction, confirmPendingWithMerchant } = await import('@/lib/db/queries/transactions');
  // Insert a pending row with a raw, munged merchant name.
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -8,
    merchant: 'NETFLIX.COM*SUB',
    date: '2026-05-25',
    status: 'pending',
  });
  // Confirm + link to Apple (cp-05). The matcher would never suggest Apple
  // for "NETFLIX.COM*SUB" but the test exercises the wiring directly.
  await confirmPendingWithMerchant(exec, txId, { counterpartyId: 'cp-05' });
  const [row] = await exec(
    'SELECT status, description, counterparty_id, confirmed_at FROM transactions WHERE id = ?',
    [txId],
  );
  expect(String(row.status)).toBe('confirmed');
  expect(String(row.description)).toBe('Apple'); // canonical name, not raw
  expect(String(row.counterparty_id)).toBe('cp-05');
  expect(row.confirmed_at).not.toBeNull();
});

test('confirmPendingWithMerchant: newCounterpartyName creates unverified + links', async () => {
  const exec = await seeded();
  const { addTransaction, confirmPendingWithMerchant } = await import('@/lib/db/queries/transactions');
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -4.5,
    merchant: 'BLUE BOTTLE COFFEE',
    date: '2026-05-25',
    status: 'pending',
  });
  await confirmPendingWithMerchant(exec, txId, { newCounterpartyName: 'Blue Bottle Coffee' });
  const [row] = await exec('SELECT status, description, counterparty_id FROM transactions WHERE id = ?', [txId]);
  expect(String(row.status)).toBe('confirmed');
  expect(String(row.description)).toBe('Blue Bottle Coffee');
  const cpId = String(row.counterparty_id);
  expect(cpId).toMatch(/^cp-/);
  const [cp] = await exec('SELECT name, is_verified FROM counterparties WHERE id = ?', [cpId]);
  expect(String(cp.name)).toBe('Blue Bottle Coffee');
  expect(Number(cp.is_verified)).toBe(0);
});

test('confirmPendingWithMerchant: with no resolution leaves the row confirmed but unlinked', async () => {
  const exec = await seeded();
  const { addTransaction, confirmPendingWithMerchant } = await import('@/lib/db/queries/transactions');
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -2,
    merchant: 'ONE OFF MERCHANT',
    date: '2026-05-25',
    status: 'pending',
  });
  await confirmPendingWithMerchant(exec, txId, {});
  const [row] = await exec('SELECT status, description, counterparty_id FROM transactions WHERE id = ?', [txId]);
  expect(String(row.status)).toBe('confirmed');
  expect(String(row.description)).toBe('ONE OFF MERCHANT');
  expect(row.counterparty_id).toBeNull();
});

test('updateTransaction: account change moves the row and recomputes both source + destination balances', async () => {
  const exec = await seeded();
  const { addTransaction } = await import('@/lib/db/queries/transactions');
  const { applyMutation } = await import('@/lib/db/mutations');
  const { recomputeAccount, listAccounts } = await import('@/lib/db/queries/accounts');
  // Establish a known starting balance.
  await recomputeAccount(exec, 'chk');
  await recomputeAccount(exec, 'sav');
  const startChk = Number((await listAccounts(exec, 'personal')).find((a) => a.id === 'chk')!.balance);
  const startSav = Number((await listAccounts(exec, 'personal')).find((a) => a.id === 'sav')!.balance);
  // Insert a confirmed $50 expense on chk.
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -50,
    merchant: 'Moving target',
    date: '2026-05-25',
  });
  await recomputeAccount(exec, 'chk');
  const afterAddChk = Number((await listAccounts(exec, 'personal')).find((a) => a.id === 'chk')!.balance);
  expect(afterAddChk).toBeCloseTo(startChk - 50, 2);
  // Move it to sav via the dispatcher. Both the source and the destination
  // account should be recomputed; chk's balance rises back to startChk and
  // sav's drops by 50.
  await applyMutation(exec, 'updateTransaction', { id: txId, patch: { account: 'sav' } });
  const finalChk = Number((await listAccounts(exec, 'personal')).find((a) => a.id === 'chk')!.balance);
  const finalSav = Number((await listAccounts(exec, 'personal')).find((a) => a.id === 'sav')!.balance);
  expect(finalChk).toBeCloseTo(startChk, 2);
  expect(finalSav).toBeCloseTo(startSav - 50, 2);
  const [row] = await exec('SELECT account_id FROM transactions WHERE id = ?', [txId]);
  expect(String(row.account_id)).toBe('sav');
});

test('updateTransaction: same-account edit returns null oldAccountId', async () => {
  const exec = await seeded();
  const { addTransaction, updateTransaction } = await import('@/lib/db/queries/transactions');
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -10,
    merchant: 'Note change',
    date: '2026-05-25',
  });
  // Patch only the note — the row stays in chk, so oldAccountId is null and
  // the dispatcher's "recompute source account" branch is a no-op.
  const result = await updateTransaction(exec, txId, { note: 'updated' });
  expect(result.oldAccountId).toBeNull();
  const [row] = await exec('SELECT account_id, notes FROM transactions WHERE id = ?', [txId]);
  expect(String(row.account_id)).toBe('chk');
  expect(String(row.notes)).toBe('updated');
});

test('updateTransaction: currency change re-derives amount_base + locks a new rate', async () => {
  const exec = await seeded();
  const { addTransaction, updateTransaction } = await import('@/lib/db/queries/transactions');
  const { convertToBase } = await import('@/lib/db/queries/rates');
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -100,
    merchant: 'Currency switch',
    date: '2026-05-25',
  });
  // Same-magnitude form, new currency label. amount_base should be re-derived
  // against the new currency at the same date; the rate is locked.
  await updateTransaction(exec, txId, { currency: 'SGD' });
  const [row] = await exec('SELECT amount, currency, amount_base, exchange_rate FROM transactions WHERE id = ?', [txId]);
  expect(Number(row.amount)).toBe(-100);
  expect(String(row.currency)).toBe('SGD');
  const expected = await convertToBase(exec, -100, 'SGD', 'USD', '2026-05-25');
  expect(Number(row.amount_base)).toBeCloseTo(expected.amountBase, 2);
  expect(Number(row.exchange_rate)).toBeCloseTo(expected.rate, 6);
});

test('updateTransaction: status flip sets/clears confirmed_at and moves the balance', async () => {
  const exec = await seeded();
  const { addTransaction } = await import('@/lib/db/queries/transactions');
  const { applyMutation } = await import('@/lib/db/mutations');
  const { recomputeAccount, listAccounts } = await import('@/lib/db/queries/accounts');
  // Insert a $25 pending expense on chk. Pending rows are excluded from the
  // balance sum, so chk's balance is unchanged after add.
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -25,
    merchant: 'Pending expense',
    date: '2026-05-25',
    status: 'pending',
  });
  await recomputeAccount(exec, 'chk');
  const pendingBal = Number((await listAccounts(exec, 'personal')).find((a) => a.id === 'chk')!.balance);
  // Confirm via the dispatcher. confirmed_at gets stamped; the dispatch
  // recomputes the account, so the balance drops by 25.
  await applyMutation(exec, 'updateTransaction', { id: txId, patch: { status: 'confirmed' } });
  const confirmedBal = Number((await listAccounts(exec, 'personal')).find((a) => a.id === 'chk')!.balance);
  expect(confirmedBal).toBeCloseTo(pendingBal - 25, 2);
  const [confirmed] = await exec('SELECT status, confirmed_at FROM transactions WHERE id = ?', [txId]);
  expect(String(confirmed.status)).toBe('confirmed');
  expect(confirmed.confirmed_at).not.toBeNull();
  // Demote back to pending. confirmed_at clears; the recompute drops the row
  // from the balance sum, so chk's balance rises back to pendingBal.
  await applyMutation(exec, 'updateTransaction', { id: txId, patch: { status: 'pending' } });
  const demotedBal = Number((await listAccounts(exec, 'personal')).find((a) => a.id === 'chk')!.balance);
  expect(demotedBal).toBeCloseTo(pendingBal, 2);
  const [demoted] = await exec('SELECT status, confirmed_at FROM transactions WHERE id = ?', [txId]);
  expect(String(demoted.status)).toBe('pending');
  expect(demoted.confirmed_at).toBeNull();
});

test('updateTransaction: cross-ledger account change is rejected', async () => {
  const exec = await seeded();
  const { addTransaction, updateTransaction } = await import('@/lib/db/queries/transactions');
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -5,
    merchant: 'Cross-ledger attempt',
    date: '2026-05-25',
  });
  // f-dbs is a family-ledger account (the seed has it under ledger='family').
  // The patch must not silently migrate the row across ledgers — it should
  // throw so the UI surfaces a clear error.
  await expect(updateTransaction(exec, txId, { account: 'f-dbs' })).rejects.toThrow(/different ledger/i);
  // The row's account is unchanged.
  const [row] = await exec('SELECT account_id FROM transactions WHERE id = ?', [txId]);
  expect(String(row.account_id)).toBe('chk');
});

test('export: transactionExportRows scopes by ledger and month', async () => {
  const { transactionExportRows } = await import('@/lib/db/queries/export');
  const exec = await seeded();

  const all = await transactionExportRows(exec);
  expect(all.length).toBeGreaterThan(0);

  // Ledger scope: every row belongs to the asked-for ledger.
  const personal = await transactionExportRows(exec, { ledgerId: 'personal' });
  expect(personal.length).toBeGreaterThan(0);
  expect(personal.every((r) => r.ledger === 'personal')).toBe(true);
  expect(personal.length).toBeLessThanOrEqual(all.length);

  // Month scope: every row's date is inside the asked-for month.
  const may = await transactionExportRows(exec, { ledgerId: 'personal', month: '2026-05' });
  expect(may.every((r) => r.date.startsWith('2026-05'))).toBe(true);
  expect(may.length).toBeLessThanOrEqual(personal.length);

  // A month with no data yields an empty export, not an error.
  const none = await transactionExportRows(exec, { ledgerId: 'personal', month: '1999-01' });
  expect(none).toEqual([]);
});
