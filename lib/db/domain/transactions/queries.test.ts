import { test, expect } from 'bun:test';
import {
  listTransactions,
  addTransaction,
  updateTransaction,
  deleteTransactionRow,
  confirmTransaction,
  getTransaction,
} from '@/lib/db/domain/transactions/queries';
import { seededDb } from '@/lib/db/core/test-utils';
import type { Exec } from '@/lib/db/core/repo';

const seeded = async (): Promise<Exec> => {
  const { exec } = await seededDb();
  return exec;
};

test('list scopes to ledger and excludes the other ledger', async () => {
  const exec = await seeded();
  const personal = await listTransactions(exec, { ledgerId: 'personal' });
  expect(personal.length).toBe(126);
  expect(personal.every((t) => t.ledgerId === 'personal')).toBe(true);
});

test('direction filter splits in vs out', async () => {
  const exec = await seeded();
  const out = await listTransactions(exec, { ledgerId: 'personal', direction: 'out' });
  const inc = await listTransactions(exec, { ledgerId: 'personal', direction: 'in' });
  expect(out.every((t) => t.amount < 0)).toBe(true);
  expect(inc.every((t) => t.amount > 0)).toBe(true);
  expect(inc.some((t) => t.merchant === 'Acme Payroll')).toBe(true);
});

test('search matches the merchant/description substring', async () => {
  const exec = await seeded();
  // Substring search returns all matches; with extended history the seed has
  // multiple Blue Bottle Coffee rows. Assert it works (≥ 1) and every hit is
  // a Coffee merchant.
  const res = await listTransactions(exec, { ledgerId: 'personal', query: 'coffee' });
  expect(res.length).toBeGreaterThan(0);
  expect(res.every((t) => /coffee/i.test(t.merchant))).toBe(true);
});

test('FTS5 search is case-folded and matches prefixes', async () => {
  const exec = await seeded();
  // SEED has rows like "Blue Bottle Coffee". A lowercase "BLUE" should still match.
  const upper = await listTransactions(exec, { ledgerId: 'personal', query: 'BLUE' });
  expect(upper.length).toBeGreaterThan(0);
  expect(upper.every((t) => /blue/i.test(t.merchant))).toBe(true);

  // Multi-word AND across description tokens — every hit has both "blue" and "bottle".
  const both = await listTransactions(exec, { ledgerId: 'personal', query: 'blue bottle' });
  expect(both.length).toBeGreaterThan(0);
  expect(both.every((t) => /blue/i.test(t.merchant) && /bottle/i.test(t.merchant))).toBe(true);
});

test('FTS5 search includes notes (not just description)', async () => {
  const exec = await seeded();
  const { addTransaction } = await import('@/lib/db/queries/transactions');
  await addTransaction(exec, {
    ledgerId: 'personal', accountId: 'chk', amount: -3,
    merchant: 'Unrelated Vendor', note: 'sticky cinnamon bun receipt',
    date: '2026-05-25',
  });
  const res = await listTransactions(exec, { ledgerId: 'personal', query: 'cinnamon' });
  expect(res.some((t) => t.merchant === 'Unrelated Vendor')).toBe(true);
});

test('FTS5 sync triggers: edits + deletes propagate to the index', async () => {
  const exec = await seeded();
  const { addTransaction, updateTransaction, deleteTransactionRow } =
    await import('@/lib/db/queries/transactions');

  // addTransaction returns entry id; Tx.id = account-posting id (§2).
  // Look up the posting id immediately so list-based assertions stay stable.
  const entryId = await addTransaction(exec, {
    ledgerId: 'personal', accountId: 'chk', amount: -5,
    merchant: 'Quirkbird Coffee Cooperative', date: '2026-05-25',
  });
  const [{ pid }] = await exec(
    'SELECT id AS pid FROM postings WHERE entry_id = ? AND account_id IS NOT NULL LIMIT 1',
    [entryId],
  ) as { pid: string }[];

  let res = await listTransactions(exec, { ledgerId: 'personal', query: 'quirkbird' });
  expect(res.some((t) => t.id === pid)).toBe(true);

  // Rename — old token shouldn't match the same row anymore.
  await updateTransaction(exec, entryId, { merchant: 'Renamed Hideout' });
  res = await listTransactions(exec, { ledgerId: 'personal', query: 'quirkbird' });
  expect(res.some((t) => t.id === pid)).toBe(false);
  res = await listTransactions(exec, { ledgerId: 'personal', query: 'hideout' });
  expect(res.some((t) => t.id === pid)).toBe(true);

  // Delete — fully gone from the index.
  await deleteTransactionRow(exec, entryId);
  res = await listTransactions(exec, { ledgerId: 'personal', query: 'hideout' });
  expect(res.some((t) => t.id === pid)).toBe(false);
});

test('counterparty resolver matches via COLLATE NOCASE (no LOWER in WHERE)', async () => {
  const exec = await seeded();
  const { resolveCounterpartyIdByName } = await import('@/lib/db/queries/counterparties');
  // Seed has "Grab" (cp-02); mixed-case + leading/trailing space should still resolve.
  expect(await resolveCounterpartyIdByName(exec, '  gRAb  ')).toBe('cp-02');
  expect(await resolveCounterpartyIdByName(exec, 'GRAB')).toBe('cp-02');
  expect(await resolveCounterpartyIdByName(exec, 'NoSuchMerchant')).toBeNull();
});

test('filter by account and category', async () => {
  const exec = await seeded();
  const food = await listTransactions(exec, { ledgerId: 'personal', categoryId: 'food' });
  expect(food.length).toBeGreaterThan(0);
  expect(food.every((t) => t.category === 'food')).toBe(true);

  const chk = await listTransactions(exec, { ledgerId: 'personal', accountId: 'chk' });
  expect(chk.every((t) => t.account === 'chk')).toBe(true);
});

test('add inserts a confirmed transaction and updates the account balance', async () => {
  const exec = await seeded();
  const before = Number((await exec('SELECT current_balance AS b FROM accounts WHERE id = ?', ['cc']))[0].b);
  const id = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'cc',
    amount: -25.5,
    merchant: 'Test Cafe',
    categoryId: 'food',
    date: '2026-05-26',
  });
  const after = Number((await exec('SELECT current_balance AS b FROM accounts WHERE id = ?', ['cc']))[0].b);
  expect(after).toBeCloseTo(before - 25.5, 2);

  const tx = await getTransaction(exec, id);
  expect(tx?.merchant).toBe('Test Cafe');
  expect(tx?.pending).toBe(false);

  const list = await listTransactions(exec, { ledgerId: 'personal', query: 'Test Cafe' });
  expect(list.length).toBe(1);
});

test('update edits fields', async () => {
  const exec = await seeded();
  await updateTransaction(exec, 't01', { merchant: 'Blue Bottle ☕', note: 'updated' });
  const tx = await getTransaction(exec, 't01');
  expect(tx?.merchant).toBe('Blue Bottle ☕');
  expect(tx?.note).toBe('updated');
});

test('delete removes a transaction from the list', async () => {
  const exec = await seeded();
  const acctId = await deleteTransactionRow(exec, 't01');
  expect(acctId).toBeTruthy();
  const list = await listTransactions(exec, { ledgerId: 'personal' });
  // t01 posting id = t01 (seed preserves ids); the deleted entry + all its postings cascade.
  expect(list.find((t) => t.id === 't01')).toBeUndefined();
  // §2: the entry is really gone (hard delete via CASCADE).
  expect((await exec("SELECT COUNT(*) AS n FROM entries WHERE id = 't01'"))[0].n).toBe(0);
});

test('confirm flips a pending transaction and feeds the summary', async () => {
  const exec = await seeded();
  // t03 (Lyft) is seeded pending.
  const pendingBefore = await listTransactions(exec, { ledgerId: 'personal', status: 'pending' });
  expect(pendingBefore.some((t) => t.id === 't03')).toBe(true);

  await confirmTransaction(exec, 't03');
  const tx = await getTransaction(exec, 't03');
  expect(tx?.pending).toBe(false);
});

test('listTransactions filters by minAmount / maxAmount on absolute amount', async () => {
  const exec = await seeded();
  const all = await listTransactions(exec, { ledgerId: 'personal' });
  const big = await listTransactions(exec, { ledgerId: 'personal', minAmount: 100 });
  expect(big.every((t) => Math.abs(t.amount) >= 100)).toBe(true);
  expect(big.length).toBeGreaterThan(0);
  expect(big.length).toBeLessThan(all.length);

  const window = await listTransactions(exec, { ledgerId: 'personal', minAmount: 20, maxAmount: 50 });
  expect(window.every((t) => Math.abs(t.amount) >= 20 && Math.abs(t.amount) <= 50)).toBe(true);
});

test("insertTxRow: defaults currency to the account's, derives amount_base via convertToBase, looks up counterparty", async () => {
  const { insertTxRow } = await import('@/lib/db/queries/transactions');
  const exec = await seeded();
  // Verify each default resolution fires when the caller leaves the field out.
  // `inv` is USD; the personal-ledger base is USD too, so amount_base == amount.
  // insertTxRow returns entry id; query via entries + postings (§2).
  const entryId = await insertTxRow(exec, {
    ledgerId: 'personal',
    accountId: 'inv',
    date: '2026-05-26',
    amount: -100,
    description: 'Blue Bottle Coffee',
    kind: 'expense',
  });
  const [e] = await exec('SELECT * FROM entries WHERE id = ?', [entryId]);
  const [p] = await exec('SELECT * FROM postings WHERE entry_id = ? AND account_id IS NOT NULL', [entryId]);
  expect(String(p.currency)).toBe('USD');               // defaulted from account
  expect(Number(p.amount_base)).toBeCloseTo(-100, 2);   // convertToBase ran
  expect(Number(p.exchange_rate)).toBeCloseTo(1, 6);
  expect(String(e.status)).toBe('confirmed');           // default status
  expect(e.confirmed_at).not.toBeNull();                // stamped on confirmed rows
  expect(e.source_template_id).toBeNull();
});

test('insertTxRow: pending status leaves confirmed_at NULL and skips the balance trigger', async () => {
  const { insertTxRow } = await import('@/lib/db/queries/transactions');
  const exec = await seeded();
  const before = Number(
    (await exec("SELECT current_balance AS b FROM accounts WHERE id = 'chk'"))[0].b,
  );
  const entryId = await insertTxRow(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    date: '2026-05-26',
    amount: -42,
    description: 'Pending charge',
    kind: 'expense',
    status: 'pending',
  });
  // §2: confirmed_at lives on entries; query by entry id (returned by insertTxRow).
  const [row] = await exec('SELECT confirmed_at FROM entries WHERE id = ?', [entryId]);
  expect(row.confirmed_at).toBeNull();
  const after = Number(
    (await exec("SELECT current_balance AS b FROM accounts WHERE id = 'chk'"))[0].b,
  );
  expect(after).toBeCloseTo(before, 2); // pending didn't move the balance
});

test('§10.4 categoryId filter matches split entries where one leg has that category', async () => {
  // The legacy parent-only filter would have matched only the single category_id
  // on the transactions row. The new filter uses EXISTS over all category postings,
  // so a split entry (≥2 category legs) is found even when neither single leg
  // is the "primary" category. §10.4
  const exec = await seeded();

  // Add a transaction that we will then manually split at the postings level.
  // addTransaction creates one account leg + one category leg (food).
  const entryId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -60,
    merchant: 'Split Purchase',
    categoryId: 'food',
    date: '2026-05-27',
  });

  // Find the auto-created category posting (food leg) and the account posting id.
  const [foodLeg] = await exec(
    'SELECT id FROM postings WHERE entry_id = ? AND account_id IS NULL AND category_id = ?',
    [entryId, 'food'],
  ) as { id: string }[];
  const [acctPostingRow] = await exec(
    'SELECT id FROM postings WHERE entry_id = ? AND account_id IS NOT NULL LIMIT 1',
    [entryId],
  ) as { id: string }[];
  const acctPostingId = String(acctPostingRow.id);

  // Unseal so we can modify postings.
  await exec(`UPDATE entries SET sealed = 0 WHERE id = ?`, [entryId]);
  // Delete the original single-category leg.
  await exec('DELETE FROM postings WHERE id = ?', [foodLeg.id]);
  // Insert two category legs: food (-30) and shop (-30).
  await exec(
    `INSERT INTO postings (id, entry_id, account_id, category_id, amount, currency, amount_base, exchange_rate, sort_order)
     VALUES ('sp-food', ?, NULL, 'food', 30, 'USD', 30, 1, 1),
            ('sp-shop', ?, NULL, 'shop', 30, 'USD', 30, 1, 2)`,
    [entryId, entryId],
  );
  // Re-seal.
  await exec(`UPDATE entries SET sealed = 1 WHERE id = ?`, [entryId]);

  // listTransactions with categoryId: 'food' must include this split entry.
  const foodResults = await listTransactions(exec, { ledgerId: 'personal', categoryId: 'food' });
  expect(foodResults.some((t) => t.id === acctPostingId)).toBe(true);

  // listTransactions with categoryId: 'shop' must also include it (second leg).
  const shopResults = await listTransactions(exec, { ledgerId: 'personal', categoryId: 'shop' });
  expect(shopResults.some((t) => t.id === acctPostingId)).toBe(true);

  // The entry must NOT appear under a category it has no leg for.
  const otherResults = await listTransactions(exec, { ledgerId: 'personal', categoryId: 'utilities' });
  expect(otherResults.some((t) => t.id === acctPostingId)).toBe(false);
});

test('addTransaction: forwards sourceTemplateId/occurrenceDate on the same-currency (postSimple) path', async () => {
  const exec = await seeded();
  const entryId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -40,
    merchant: 'Gym',
    date: '2026-07-21',
    sourceTemplateId: 's1',
    occurrenceDate: '2026-07-15',
  });
  const [row] = await exec(
    'SELECT source_template_id, occurrence_date FROM entries WHERE id = ?',
    [entryId],
  );
  expect(String(row.source_template_id)).toBe('s1');
  expect(String(row.occurrence_date)).toBe('2026-07-15');
});

test('addTransaction: forwards sourceTemplateId/occurrenceDate on the foreign-currency (postEntry) path', async () => {
  const exec = await seeded();
  // 'chk' is a USD account; passing currency: 'EUR' forces the foreign-currency branch.
  const entryId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    currency: 'EUR',
    amount: -40,
    merchant: 'Gym EUR',
    date: '2026-07-21',
    sourceTemplateId: 's1',
    occurrenceDate: '2026-07-15',
  });
  const [row] = await exec(
    'SELECT source_template_id, occurrence_date FROM entries WHERE id = ?',
    [entryId],
  );
  expect(String(row.source_template_id)).toBe('s1');
  expect(String(row.occurrence_date)).toBe('2026-07-15');
});

test("FTS5 search matches tokens with internal punctuation (O'Reilly, AT&T)", async () => {
  const exec = await seeded();
  // FTS5's unicode61 tokenizer splits "O'Reilly" into `o` + `reilly`; our
  // toFts5Query must match that split, not collapse the string to `oreilly`.
  await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'cc',
    amount: -42.5,
    merchant: "O'Reilly Auto Parts",
    date: '2026-05-22',
    categoryId: 'food',
  });
  await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'cc',
    amount: -29.99,
    merchant: 'AT&T Wireless',
    date: '2026-05-22',
    categoryId: 'food',
  });
  const reilly = await listTransactions(exec, { ledgerId: 'personal', query: 'reilly' });
  expect(reilly.some((t) => t.merchant === "O'Reilly Auto Parts")).toBe(true);
  const att = await listTransactions(exec, { ledgerId: 'personal', query: 'at&t' });
  expect(att.some((t) => t.merchant === 'AT&T Wireless')).toBe(true);
  const apostrophe = await listTransactions(exec, { ledgerId: 'personal', query: "O'Reilly" });
  expect(apostrophe.some((t) => t.merchant === "O'Reilly Auto Parts")).toBe(true);
});
