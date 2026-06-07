import { test, expect } from 'bun:test';
import { listAccounts, netWorth, updateAccount, createAccount, archiveAccount } from '@/lib/db/queries/accounts';
import { listCategories, monthlyByCategory, categorySpend } from '@/lib/db/queries/categories';
import { listCounterparties, searchCounterparties, verifyCounterparty } from '@/lib/db/queries/counterparties';
import { seededDb } from '@/lib/db/test-utils';
import type { Exec } from '@/lib/db/repo';

// Confirmed, non-transfer/-adjustment cash flow for a month. §2: uses entries + postings.
async function monthlyCashFlow(exec: Exec, ledgerId: string, yearMonth: string) {
  const rows = await exec(
    `SELECT
       SUM(CASE WHEN e.kind = 'income' THEN p.amount_base ELSE 0 END) AS income,
       SUM(CASE WHEN e.kind IN ('expense','refund') THEN p.amount_base ELSE 0 END) AS expense,
       SUM(p.amount_base) AS net
     FROM postings p JOIN entries e ON e.id = p.entry_id
     WHERE e.ledger_id = ? AND e.date LIKE ? AND e.kind NOT IN ('transfer','adjustment','opening')
       AND e.status = 'confirmed' AND p.account_id IS NOT NULL`,
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

// CATEGORIES_LEVEL3_PLAN: depth-3 is now allowed; the cap is at 3.
test('createCategory allows depth-3 (parent under a child) but rejects depth-4', async () => {
  const exec = await seeded();
  const { applyMutation } = await import('@/lib/db/mutations');

  // Depth 3 OK: food (1) -> food-coffee (2) -> Espresso (3)
  await applyMutation(exec, 'createCategory', {
    ledgerId: 'personal', name: 'Espresso', parentId: 'food-coffee',
  });
  const cats = await listCategories(exec, 'personal');
  const espresso = cats.find((c) => c.name === 'Espresso')!;
  expect(espresso.parentId).toBe('food-coffee');

  // Depth 4 rejected.
  await expect(
    applyMutation(exec, 'createCategory', {
      ledgerId: 'personal', name: 'Doppio', parentId: espresso.id,
    }),
  ).rejects.toThrow(/three levels/i);
});

test('updateCategory subtree move: depth-3 subtree fits only under a top-level parent', async () => {
  const exec = await seeded();
  const { applyMutation } = await import('@/lib/db/mutations');

  // Build a depth-3 chain under food: food -> food-coffee -> Espresso.
  await applyMutation(exec, 'createCategory', {
    ledgerId: 'personal', name: 'Espresso', parentId: 'food-coffee',
  });

  // Try to move food-coffee (depth 2, with a depth-3 child) under
  // food-groceries (also depth 2). Would push Espresso to depth 4 -> reject.
  await expect(
    applyMutation(exec, 'updateCategory', {
      id: 'food-coffee', patch: { parentId: 'food-groceries' },
    }),
  ).rejects.toThrow(/three levels/i);

  // Same subtree under a TOP-LEVEL parent (rent) is fine — chain becomes
  // rent -> food-coffee -> Espresso, depth 3.
  await applyMutation(exec, 'updateCategory', {
    id: 'food-coffee', patch: { parentId: 'rent' },
  });
  const cats = await listCategories(exec, 'personal');
  expect(cats.find((c) => c.id === 'food-coffee')!.parentId).toBe('rent');
});

test('updateCategory rejects moving a node under its own descendant (cycle)', async () => {
  const exec = await seeded();
  const { applyMutation } = await import('@/lib/db/mutations');
  await expect(
    applyMutation(exec, 'updateCategory', {
      id: 'food', patch: { parentId: 'food-coffee' },
    }),
  ).rejects.toThrow(/descendant/i);
});

test('rollupCategorySpend folds grandchild → child → parent (3-level)', async () => {
  // Synthetic 3-level tree so the test is independent of the seed.
  const cats = [
    { id: 'food',  parentId: null },
    { id: 'rest',  parentId: 'food' },
    { id: 'japan', parentId: 'rest' },
  ];
  const { rollupCategorySpend } = await import('@/lib/db/queries/categories');
  const rolled = rollupCategorySpend({ food: 10, rest: 20, japan: 30 }, cats);
  expect(rolled.japan).toBe(30);          // leaf stays alone
  expect(rolled.rest).toBe(20 + 30);       // child = own + grandchild
  expect(rolled.food).toBe(10 + 20 + 30);  // root = own + child + grandchild
});

test('expandDescendants returns the configured ids plus every descendant', async () => {
  const cats = [
    { id: 'food',     parentId: null },
    { id: 'rest',     parentId: 'food' },
    { id: 'japan',    parentId: 'rest' },
    { id: 'thai',     parentId: 'rest' },
    { id: 'grocery',  parentId: 'food' },
    { id: 'rent',     parentId: null },
  ];
  const { expandDescendants } = await import('@/lib/db/queries/categories');
  const set = expandDescendants(['food'], cats);
  expect(set).toEqual(new Set(['food', 'rest', 'japan', 'thai', 'grocery']));
  // Already-deep ids stay (no double-add).
  expect(expandDescendants(['japan'], cats)).toEqual(new Set(['japan']));
  // Multiple roots merge.
  expect(expandDescendants(['food', 'rent'], cats)).toEqual(
    new Set(['food', 'rest', 'japan', 'thai', 'grocery', 'rent']),
  );
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
  // §2: counterparty_id, description on entries.
  const [m] = await exec('SELECT counterparty_id FROM entries WHERE id = ?', [matched]);
  expect(String(m.counterparty_id)).toBe('cp-02');

  const unmatched = await addTransaction(exec, {
    ledgerId: 'personal', accountId: 'chk', amount: -10,
    merchant: 'Random Shop That Has No Catalog Entry',
    date: '2026-05-25',
  });
  const [u] = await exec('SELECT counterparty_id FROM entries WHERE id = ?', [unmatched]);
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
  let [row] = await exec('SELECT counterparty_id FROM entries WHERE id = ?', [txId]);
  expect(String(row.counterparty_id)).toBe('cp-02');

  // Rename merchant to a non-catalog string; link should drop to NULL.
  await updateTransaction(exec, txId, { merchant: 'Some One-off Vendor' });
  [row] = await exec('SELECT counterparty_id FROM entries WHERE id = ?', [txId]);
  expect(row.counterparty_id).toBeNull();

  // Rename to a known catalog name; link should re-establish.
  await updateTransaction(exec, txId, { merchant: 'Apple' }); // cp-05
  [row] = await exec('SELECT counterparty_id FROM entries WHERE id = ?', [txId]);
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
  const [row] = await exec('SELECT counterparty_id, description FROM entries WHERE id = ?', [txId]);
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
  const exec = await seeded();
  const { applyMutation } = await import('@/lib/db/mutations');
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
  const entryId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -3,
    merchant: 'Grab',
    date: '2026-05-25',
  });
  const [row] = await exec('SELECT description, counterparty_id FROM entries WHERE id = ?', [entryId]);
  expect(String(row.description)).toBe('Grab');
  expect(String(row.counterparty_id)).toBe('cp-02');
  // §2: Tx.id = account posting id (≠ entry id); find by counterparty_id + merchant.
  const projected = await projectState(exec);
  const tx = projected.transactions.find((t) => t.counterpartyId === 'cp-02' && t.amount === -3)!;
  expect(tx).toBeTruthy();
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
  await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -3,
    merchant: 'Grab',
    date: '2026-05-25',
  });
  await updateCounterparty(exec, 'cp-02', { name: 'Grab Holdings' });
  // §2: Tx.id = account posting id; find by counterparty_id.
  const projected = await projectState(exec);
  const tx = projected.transactions.find((t) => t.counterpartyId === 'cp-02' && t.amount === -3)!;
  expect(tx).toBeTruthy();
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
  const [row] = await exec('SELECT description, counterparty_id FROM entries WHERE id = ?', [txId]);
  expect(String(row.description)).toBe('BLUE BOTTLE COFFEE');
  expect(row.counterparty_id).toBeNull();
});

test('addTransaction: explicit counterpartyId links the row to that counterparty', async () => {
  const exec = await seeded();
  const { addTransaction } = await import('@/lib/db/queries/transactions');
  // Pass a raw merchant string that wouldn't match by name. The explicit
  // counterpartyId forces the link, and the projection surfaces the canonical
  // name on `merchant` regardless of the raw description.
  const entryId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -8,
    merchant: 'APPLE.COM/BILL',
    date: '2026-05-25',
    counterpartyId: 'cp-05', // Apple (verified, seeded)
  });
  const [row] = await exec('SELECT description, counterparty_id FROM entries WHERE id = ?', [entryId]);
  expect(String(row.description)).toBe('APPLE.COM/BILL');
  expect(String(row.counterparty_id)).toBe('cp-05');
  // Projection surfaces the canonical name on the merchant field.
  // §2: Tx.id = account posting id (≠ entry id); find by counterparty_id.
  const { projectState } = await import('@/lib/db/state');
  const projected = await projectState(exec);
  const tx = projected.transactions.find((t) => t.counterpartyId === 'cp-05' && t.amount === -8)!;
  expect(tx).toBeTruthy();
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
  const [row] = await exec('SELECT description, counterparty_id FROM entries WHERE id = ?', [txId]);
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
  const [row] = await exec('SELECT description, counterparty_id FROM entries WHERE id = ?', [txId]);
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
    'SELECT status, description, counterparty_id, confirmed_at FROM entries WHERE id = ?',
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
  const [row] = await exec('SELECT status, description, counterparty_id FROM entries WHERE id = ?', [txId]);
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
  const [row] = await exec('SELECT status, description, counterparty_id FROM entries WHERE id = ?', [txId]);
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
  // §2: account_id on the posting.
  const [row] = await exec('SELECT p.account_id FROM postings p WHERE p.entry_id = ? AND p.account_id IS NOT NULL LIMIT 1', [txId]);
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
  // §2: account_id on postings, notes on entries.
  const [prow] = await exec('SELECT p.account_id FROM postings p WHERE p.entry_id = ? AND p.account_id IS NOT NULL LIMIT 1', [txId]);
  const [erow] = await exec('SELECT notes FROM entries WHERE id = ?', [txId]);
  expect(String(prow.account_id)).toBe('chk');
  expect(String(erow.notes)).toBe('updated');
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
  // §2: updateTransaction with currency='SGD' on a USD account means the input
  // is in SGD; the posting stores currency='USD' (account currency) and the
  // amount_base is recomputed treating the input as SGD.
  await updateTransaction(exec, txId, { currency: 'SGD' });
  // §5.2: currency='SGD' on a USD account → foreign-currency input path.
  // Posting stores: currency=USD (account), amount=SGD→USD conversion,
  // amount_base=USD (ledger base=USD so same), orig_amount=-100, orig_currency='SGD'.
  const [row] = await exec('SELECT p.amount, p.currency, p.amount_base, p.exchange_rate, p.orig_amount, p.orig_currency FROM postings p WHERE p.entry_id = ? AND p.account_id IS NOT NULL LIMIT 1', [txId]);
  // currency stays USD (account currency), amount is the converted USD figure.
  expect(String(row.currency)).toBe('USD');
  const convToUsd = await convertToBase(exec, -100, 'SGD', 'USD', '2026-05-25');
  expect(Number(row.amount)).toBeCloseTo(convToUsd.amountBase, 2);
  // amount_base = converted to USD (=ledger base); same figure since acct ccy == ledger base.
  expect(Number(row.amount_base)).toBeCloseTo(convToUsd.amountBase, 2);
  // §5.2: orig_amount + orig_currency carry the typed foreign input.
  expect(Number(row.orig_amount)).toBe(-100);
  expect(String(row.orig_currency)).toBe('SGD');
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
  const [confirmed] = await exec('SELECT status, confirmed_at FROM entries WHERE id = ?', [txId]);
  expect(String(confirmed.status)).toBe('confirmed');
  expect(confirmed.confirmed_at).not.toBeNull();
  // Demote back to pending. confirmed_at clears; the recompute drops the row
  // from the balance sum, so chk's balance rises back to pendingBal.
  await applyMutation(exec, 'updateTransaction', { id: txId, patch: { status: 'pending' } });
  const demotedBal = Number((await listAccounts(exec, 'personal')).find((a) => a.id === 'chk')!.balance);
  expect(demotedBal).toBeCloseTo(pendingBal, 2);
  const [demoted] = await exec('SELECT status, confirmed_at FROM entries WHERE id = ?', [txId]);
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
  // The row's account is unchanged. §2: account_id on postings.
  const [row] = await exec('SELECT p.account_id FROM postings p WHERE p.entry_id = ? AND p.account_id IS NOT NULL LIMIT 1', [txId]);
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
