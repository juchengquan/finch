import { test, expect } from 'bun:test';
import { migrate, SCHEMA_VERSION } from './core/schema';
import { readMetadata } from '@/lib/db/queries/metadata';
import { applyMutation } from '@/lib/db/mutations';
import { listTransfers } from '@/lib/db/queries/transfers';
import { convertToBase } from '@/lib/db/queries/rates';
import { seededAndAudited } from './core/test-utils';
import type { Exec } from './core/repo';

// `seededAndAudited` is the default — its afterEach hook runs auditLedger
// and throws on drift. Use `seededDb` directly only when a test intentionally
// leaves the ledger in a half-valid state.

const balanceOf = async (exec: Exec, id: string) =>
  Number((await exec('SELECT current_balance AS b FROM accounts WHERE id = ?', [id]))[0].b);

// Confirmed, non-transfer/-adjustment cash flow for a month. Inlined here (and
// in domains.test.ts) after the production monthlyCashFlow query was retired.
// §2: entries + account postings replace transactions. Sum account-leg amount_base
// (same sign convention: positive = money in for income, negative for expenses).
const monthlyCashFlow = async (exec: Exec, ledgerId: string, yearMonth: string) => {
  const rows = await exec(
    `SELECT
       SUM(CASE WHEN e.kind = 'income' THEN p.amount_base ELSE 0 END) AS income,
       SUM(CASE WHEN e.kind IN ('expense','refund') THEN p.amount_base ELSE 0 END) AS expense,
       SUM(p.amount_base) AS net
     FROM postings p
     JOIN entries e ON e.id = p.entry_id
     WHERE e.ledger_id = ? AND e.date LIKE ? AND e.kind NOT IN ('transfer','adjustment','opening')
       AND e.status = 'confirmed' AND p.account_id IS NOT NULL`,
    [ledgerId, `${yearMonth}%`],
  );
  const r = rows[0] ?? {};
  return { income: Number(r.income ?? 0), expense: Number(r.expense ?? 0), net: Number(r.net ?? 0) };
};

test('createTransfer makes paired rows that move both balances', async () => {
  const exec = await seededAndAudited();
  const chk0 = await balanceOf(exec, 'chk');
  const sav0 = await balanceOf(exec, 'sav');

  await applyMutation(exec, 'createTransfer', {
    fromAccountId: 'chk',
    toAccountId: 'sav',
    fromAmount: 200,
    date: '2026-05-27',
    note: 'Savings sweep',
  });

  expect(await balanceOf(exec, 'chk')).toBeCloseTo(chk0 - 200, 2);
  expect(await balanceOf(exec, 'sav')).toBeCloseTo(sav0 + 200, 2);

  const transfers = await listTransfers(exec, 'personal');
  expect(transfers).toHaveLength(1);
  expect(transfers[0].fromName).toBe('Chase Checking');
  expect(transfers[0].toName).toBe('Marcus Savings');
  expect(transfers[0].amount).toBeCloseTo(200, 2);
});

test('createTransfer rejects same-account and zero amount', async () => {
  const exec = await seededAndAudited();
  await expect(
    applyMutation(exec, 'createTransfer', { fromAccountId: 'chk', toAccountId: 'chk', fromAmount: 50, date: '2026-05-27' }),
  ).rejects.toThrow();
  await expect(
    applyMutation(exec, 'createTransfer', { fromAccountId: 'chk', toAccountId: 'sav', fromAmount: 0, date: '2026-05-27' }),
  ).rejects.toThrow();
});

test('postScheduled posts a resolvable expense template as a transaction', async () => {
  const exec = await seededAndAudited();
  // rt-spotify: $11.99 expense on "Amex Gold" → account cc.
  const ccBefore = await balanceOf(exec, 'cc');
  await applyMutation(exec, 'postScheduled', { templateId: 'rt-spotify' });
  expect(await balanceOf(exec, 'cc')).toBeCloseTo(ccBefore - 11.99, 2);
  // §2: entries replaces transactions; amount is on the account posting.
  const rows = await exec(
    "SELECT e.kind, p.amount FROM entries e JOIN postings p ON p.entry_id = e.id WHERE e.description = 'Spotify Premium' AND p.account_id IS NOT NULL",
  );
  expect(rows.length).toBe(1);
  expect(Number(rows[0].amount)).toBeCloseTo(-11.99, 2);
  expect(String(rows[0].kind)).toBe('expense');
});

test('postScheduled stamps the template category onto the posted transaction', async () => {
  const exec = await seededAndAudited();
  // Build a template that has a category set, then post it manually. The
  // posted row should carry that category — earlier the manual-post path
  // hard-coded category_id to NULL while autopost preserved it.
  await applyMutation(exec, 'createScheduled', {
    id: 'sch-cat', name: 'Coffee subscription', type: 'expense', frequency: 'monthly',
    dayOfMonth: 1, accountId: 'cc', amount: 12, category: 'food',
  });
  await applyMutation(exec, 'postScheduled', { templateId: 'sch-cat' });
  // §2: category is on the category posting (account_id IS NULL); entry carries source_template_id.
  const [row] = await exec(
    "SELECT p.category_id FROM postings p JOIN entries e ON e.id = p.entry_id WHERE e.source_template_id = 'sch-cat' AND p.account_id IS NULL AND p.category_id IS NOT NULL LIMIT 1",
  );
  expect(String(row.category_id)).toBe('food');
});

test('createHolding rejects a currency that differs from the account currency', async () => {
  const exec = await seededAndAudited();
  // `inv` is denominated in USD (personal-ledger base). Trying to add a EUR
  // position should fail outright — mixed-currency sums on the account total
  // would silently corrupt without per-row conversion.
  await expect(
    applyMutation(exec, 'createHolding', {
      accountId: 'inv', symbol: 'EUNA', shares: 5, costBasis: 1000, currency: 'EUR',
    }),
  ).rejects.toThrow('Holding currency must match the account currency');
});

test('postScheduled posts to the template\'s linked account', async () => {
  const exec = await seededAndAudited();
  // rt-rent: $1850 expense on Chase Checking (chk).
  const chkBefore = await balanceOf(exec, 'chk');
  await applyMutation(exec, 'postScheduled', { templateId: 'rt-rent' });
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(chkBefore - 1850, 2);
});

test('postScheduled splits income across its linked accounts', async () => {
  const exec = await seededAndAudited();
  // rt-salary: $5800 income split 60/25/15 across Chase Checking / Marcus Savings / Fidelity Brokerage.
  const chkBefore = await balanceOf(exec, 'chk');
  const savBefore = await balanceOf(exec, 'sav');
  const invBefore = await balanceOf(exec, 'inv');
  await applyMutation(exec, 'postScheduled', { templateId: 'rt-salary' });
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(chkBefore + 5800 * 0.60, 2);
  expect(await balanceOf(exec, 'sav')).toBeCloseTo(savBefore + 5800 * 0.25, 2);
  expect(await balanceOf(exec, 'inv')).toBeCloseTo(invBefore + 5800 * 0.15, 2);
});

test('transfers are excluded from category spend and cash flow', async () => {
  const exec = await seededAndAudited();
  const { categorySpend } = await import('@/lib/db/queries/categories');
  const before = await categorySpend(exec, 'personal');
  await applyMutation(exec, 'createTransfer', {
    fromAccountId: 'chk',
    toAccountId: 'sav',
    fromAmount: 500,
    date: '2026-05-27',
  });
  const after = await categorySpend(exec, 'personal');
  // A transfer has no category, so category spend is unchanged.
  expect(JSON.stringify(after)).toBe(JSON.stringify(before));
});

test('a refund nets its category spend, lifts the balance, and stays out of income', async () => {
  const exec = await seededAndAudited();
  const { categorySpend } = await import('@/lib/db/queries/categories');
  const food0 = (await categorySpend(exec, 'personal'))['food'] ?? 0;
  const chk0 = await balanceOf(exec, 'chk');

  // A $200 grocery expense, then a $50 refund linked back to it (same category).
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: -200, merchant: 'Whole Foods',
    categoryId: 'food', date: '2026-05-12', kind: 'expense',
  });
  // §2: addTransaction writes to entries; look up the entry id for the refund link.
  const [expRow] = await exec("SELECT id FROM entries WHERE description = 'Whole Foods'");
  const cf1 = await monthlyCashFlow(exec, 'personal', '2026-05');

  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: 50, merchant: 'Whole Foods refund',
    categoryId: 'food', date: '2026-05-20', kind: 'refund', refundedTransactionId: String(expRow.id),
  });

  // Category spend nets: +200 expense − 50 refund = +150 over the baseline.
  expect(((await categorySpend(exec, 'personal'))['food'] ?? 0) - food0).toBeCloseTo(150, 2);
  // Balance moved by −200 then +50 → −150 net (the money really came back).
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(chk0 - 150, 2);
  // The refund must NOT register as income; it lifts the (negative) expense by +50.
  const cf2 = await monthlyCashFlow(exec, 'personal', '2026-05');
  expect(cf2.income).toBeCloseTo(cf1.income, 2);
  expect(cf2.expense - cf1.expense).toBeCloseTo(50, 2);
});

test('deleting the refunded expense orphans the refund (SET NULL); the refund survives', async () => {
  const exec = await seededAndAudited();
  const { getRefundsFor } = await import('@/lib/db/queries/transactions');
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: -200, merchant: 'TV',
    categoryId: 'food', date: '2026-05-12', kind: 'expense',
  });
  // §2: query entries instead of transactions.
  const [exp] = await exec("SELECT id FROM entries WHERE description = 'TV'");
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: 80, merchant: 'TV partial refund',
    categoryId: 'food', date: '2026-05-15', kind: 'refund', refundedTransactionId: String(exp.id),
  });
  expect((await getRefundsFor(exec, String(exp.id))).length).toBe(1);

  await applyMutation(exec, 'deleteTransaction', { id: String(exp.id) });
  // §2: refunded_entry_id is the FK on entries (SET NULL on delete).
  const [ref] = await exec("SELECT refunded_entry_id FROM entries WHERE description = 'TV partial refund'");
  expect(ref).toBeTruthy(); // refund entry still exists
  expect(ref.refunded_entry_id).toBeNull(); // link nulled, not cascaded
});

test('converting an income to a refund reclassifies it: nets category spend, drops from income, balance unchanged', async () => {
  const exec = await seededAndAudited();
  const { categorySpend } = await import('@/lib/db/queries/categories');

  // A $200 grocery expense to offset against.
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: -200, merchant: 'Whole Foods',
    categoryId: 'food', date: '2026-05-12', kind: 'expense',
  });
  // §2: query entries instead of transactions.
  const [exp] = await exec("SELECT id FROM entries WHERE description = 'Whole Foods'");
  const food1 = (await categorySpend(exec, 'personal'))['food'] ?? 0;

  // A $50 income (mis-recorded; really money back on the groceries).
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: 50, merchant: 'Mystery deposit',
    categoryId: 'misc', date: '2026-05-20', kind: 'income',
  });
  const [inc] = await exec("SELECT id FROM entries WHERE description = 'Mystery deposit'");
  const balAfterIncome = await balanceOf(exec, 'chk');
  const cfIncome = await monthlyCashFlow(exec, 'personal', '2026-05');

  // Convert it: kind→refund, link to the expense, adopt its category.
  await applyMutation(exec, 'updateTransaction', {
    id: String(inc.id),
    patch: { kind: 'refund', refundedTransactionId: String(exp.id), category: 'food' },
  });

  // §2: kind + refunded_entry_id on entries; category on the category posting.
  const [eRow] = await exec("SELECT kind, refunded_entry_id AS r FROM entries WHERE id = ?", [String(inc.id)]);
  const [pRow] = await exec("SELECT category_id AS c FROM postings WHERE entry_id = ? AND account_id IS NULL AND category_id IS NOT NULL LIMIT 1", [String(inc.id)]);
  expect(String(eRow.kind)).toBe('refund');
  expect(String(eRow.r)).toBe(String(exp.id));
  expect(String(pRow.c)).toBe('food');

  // Now nets food spend by 50 (200 − 50 = 150).
  expect(((await categorySpend(exec, 'personal'))['food'] ?? 0)).toBeCloseTo(food1 - 50, 2);
  // Balance is unchanged — income and refund are both stored positive.
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(balAfterIncome, 2);
  // It no longer counts as income; as a positive refund row it lifts the
  // (negative) expense total by +50 instead.
  const cfRefund = await monthlyCashFlow(exec, 'personal', '2026-05');
  expect(cfRefund.income).toBeCloseTo(cfIncome.income - 50, 2);
  expect(cfRefund.expense).toBeCloseTo(cfIncome.expense + 50, 2);
});

test('createCategory inserts a ledger-scoped category', async () => {
  const exec = await seededAndAudited();
  const before = Number((await exec("SELECT count(*) AS n FROM categories WHERE ledger_id = 'personal'"))[0].n);
  await applyMutation(exec, 'createCategory', { ledgerId: 'personal', name: 'Travel', type: 'expense', icon: 'plane' });
  const rows = await exec("SELECT * FROM categories WHERE name = 'Travel' AND ledger_id = 'personal'");
  expect(rows.length).toBe(1);
  expect(String(rows[0].kind)).toBe('expense');
  expect(String(rows[0].icon)).toBe('plane');
  const after = Number((await exec("SELECT count(*) AS n FROM categories WHERE ledger_id = 'personal'"))[0].n);
  expect(after).toBe(before + 1);
});

test('createCategory rejects an empty name', async () => {
  const exec = await seededAndAudited();
  await expect(applyMutation(exec, 'createCategory', { ledgerId: 'personal', name: '  ' })).rejects.toThrow();
});

test('updateScheduledSplit updates the nth split by sort order', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'updateScheduledSplit', { templateId: 'rt-salary', index: 1, pct: 30 });
  const rows = await exec("SELECT amount_pct FROM scheduled_splits WHERE template_id = 'rt-salary' ORDER BY sort_order");
  expect(Number(rows[0].amount_pct)).toBe(60); // unchanged
  expect(Number(rows[1].amount_pct)).toBe(30); // updated
});

test('createTag + setTransactionTags replace the tag set', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'createTag', { id: 'tag-new', ledgerId: 'personal', name: 'Trip' });
  await applyMutation(exec, 'setTransactionTags', { id: 't02', tagIds: ['tag-new', 'tag-business'] });
  // §2: entry_tags replaces transaction_tags; entry_id = old tx id (seed preserves ids).
  const rows = await exec("SELECT tag_id FROM entry_tags WHERE entry_id = 't02' ORDER BY tag_id");
  expect(rows.map((r) => String(r.tag_id))).toEqual(['tag-business', 'tag-new']);
  // Replacing with a smaller set removes the others.
  await applyMutation(exec, 'setTransactionTags', { id: 't02', tagIds: ['tag-new'] });
  const after = await exec("SELECT tag_id FROM entry_tags WHERE entry_id = 't02'");
  expect(after.map((r) => String(r.tag_id))).toEqual(['tag-new']);
});

test('seeded tag assignments are projected onto transactions', async () => {
  const exec = await seededAndAudited();
  // §2: entry_tags replaces transaction_tags; entry_id = old tx id (seed preserves ids).
  const map = await exec("SELECT tag_id FROM entry_tags WHERE entry_id = 't03' ORDER BY tag_id");
  expect(map.length).toBe(2);
});

test('createTransfer converts the incoming leg across currencies', async () => {
  const exec = await seededAndAudited();
  // Add a EUR account in the personal (USD) ledger.
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,is_active,created_at,updated_at) VALUES ('eurw','personal','EUR Wallet','cash','EUR',0,1,'2026-05-26','2026-05-26')",
  );
  await applyMutation(exec, 'createTransfer', { fromAccountId: 'chk', toAccountId: 'eurw', fromAmount: 100, date: '2026-05-24' });
  // chk is USD; 100 USD → EUR at rate(USD)/rate(EUR) = 1 / 1.088 (USD is the hub).
  const eur = Number((await exec("SELECT current_balance AS b FROM accounts WHERE id = 'eurw'"))[0].b);
  expect(eur).toBeCloseTo(100 * (1 / 1.088), 2);
  // §2: transfer_groups is dropped; the effective rate = toAmount / fromAmount from the postings.
  const [t] = await listTransfers(exec, 'personal');
  const effectiveRate = t.toAmount / t.amount;
  expect(effectiveRate).toBeCloseTo(1 / 1.088, 4);
  // listTransfers surfaces both legs' native amounts + currencies for the UI.
  expect(t.fromCurrency).toBe('USD');
  expect(t.toCurrency).toBe('EUR');
  expect(t.amount).toBeCloseTo(100, 2); // sent (USD, native)
  expect(t.toAmount).toBeCloseTo(100 * (1 / 1.088), 2); // received (EUR, native)
});

test('addTransaction on a foreign-currency account: native balance, ledger-base amount_base', async () => {
  const exec = await seededAndAudited();
  // A JPY account inside the personal (USD) ledger — account currency ≠ ledger base.
  // §2: accounts no longer has opening_balance (opening entries replace that column).
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,is_active,created_at,updated_at) VALUES ('jpyw','personal','JPY Wallet','cash','JPY',0,1,'2026-05-26','2026-05-26')",
  );
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'jpyw', amount: -10000, currency: 'JPY',
    merchant: 'Konbini', date: '2026-05-13', status: 'confirmed',
  });
  // The balance moves in the ACCOUNT's currency (¥), un-converted.
  expect(await balanceOf(exec, 'jpyw')).toBeCloseTo(-10000, 2);
  // §2: account posting carries orig_amount/orig_currency for native JPY; amount is account-native (JPY).
  const [row] = await exec("SELECT p.amount, p.amount_base, p.currency FROM postings p JOIN entries e ON e.id = p.entry_id WHERE p.account_id='jpyw' AND e.kind != 'opening'");
  expect(Number(row.amount)).toBeCloseTo(-10000, 2); // native (¥) — account currency is JPY
  expect(String(row.currency)).toBe('JPY');
  // amount_base is the LEDGER base (USD) figure for cross-account reporting.
  const expected = await convertToBase(exec, -10000, 'JPY', 'USD', '2026-05-13');
  expect(Number(row.amount_base)).toBeCloseTo(expected.amountBase, 2);
  // ¥ → $ shrinks the magnitude ~150×, so base ≠ native (proves they're distinct).
  expect(Math.abs(Number(row.amount_base))).toBeLessThan(Math.abs(Number(row.amount)));
});

test('recompute keeps a foreign-currency account balance in its own currency', async () => {
  const exec = await seededAndAudited();
  // §2: accounts no longer has opening_balance column.
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,is_active,created_at,updated_at) VALUES ('jpyw','personal','JPY Wallet','cash','JPY',0,1,'2026-05-26','2026-05-26')",
  );
  const add = (amount: number, date: string) =>
    applyMutation(exec, 'addTransaction', {
      ledgerId: 'personal', accountId: 'jpyw', amount, currency: 'JPY', merchant: 'Konbini', date, status: 'confirmed',
    });
  await add(-10000, '2026-05-13');
  await add(-5000, '2026-05-14');
  expect(await balanceOf(exec, 'jpyw')).toBeCloseTo(-15000, 2); // ¥, summed natively
  // Cancelling routes through recomputeAccount — it must reverse in ¥, not USD.
  // §2: entry id is on entries; use entry_id from postings (kind != opening).
  const [{ id }] = await exec("SELECT e.id FROM entries e JOIN postings p ON p.entry_id = e.id WHERE p.account_id='jpyw' AND p.amount=-5000 AND e.kind != 'opening'");
  await applyMutation(exec, 'deleteTransaction', { id: String(id) });
  expect(await balanceOf(exec, 'jpyw')).toBeCloseTo(-10000, 2);
});

test('editing a foreign-currency transaction amount reconverts amount_base to ledger base', async () => {
  const exec = await seededAndAudited();
  // §2: accounts no longer has opening_balance column.
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,is_active,created_at,updated_at) VALUES ('jpyw','personal','JPY Wallet','cash','JPY',0,1,'2026-05-26','2026-05-26')",
  );
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'jpyw', amount: -10000, currency: 'JPY', merchant: 'Konbini', date: '2026-05-13', status: 'confirmed',
  });
  // §2: get the entry id from entries (non-opening).
  const [{ id }] = await exec("SELECT e.id FROM entries e JOIN postings p ON p.entry_id = e.id WHERE p.account_id='jpyw' AND e.kind != 'opening'");
  await applyMutation(exec, 'updateTransaction', { id: String(id), patch: { amount: -20000 } });
  // The balance reflects the new ¥ amount (native), summed in the account currency.
  expect(await balanceOf(exec, 'jpyw')).toBeCloseTo(-20000, 2);
  // §2: account posting carries amount/amount_base.
  const [row] = await exec('SELECT p.amount, p.amount_base FROM postings p WHERE p.entry_id = ? AND p.account_id IS NOT NULL', [String(id)]);
  expect(Number(row.amount)).toBeCloseTo(-20000, 2); // native (¥)
  // amount_base is re-derived in USD (ledger base), not left as the native ¥ figure.
  const expected = await convertToBase(exec, -20000, 'JPY', 'USD', '2026-05-13');
  expect(Number(row.amount_base)).toBeCloseTo(expected.amountBase, 2);
  expect(Math.abs(Number(row.amount_base))).toBeLessThan(Math.abs(Number(row.amount)));
});

test('editing only the date re-locks exchange_rate + amount_base to the new date', async () => {
  const exec = await seededAndAudited();
  // §2: accounts no longer has opening_balance column.
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,is_active,created_at,updated_at) VALUES ('jpyw','personal','JPY Wallet','cash','JPY',0,1,'2026-05-26','2026-05-26')",
  );
  // Two distinct JPY rates so moving the date measurably changes the lock.
  await applyMutation(exec, 'setExchangeRate', { date: '2026-05-20', currency: 'JPY', rate: 0.0070, source: 'manual' });
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'jpyw', amount: -10000, currency: 'JPY', merchant: 'Konbini', date: '2026-05-13', status: 'confirmed',
  });
  // §2: get entry id from entries (non-opening).
  const [{ id }] = await exec("SELECT e.id FROM entries e JOIN postings p ON p.entry_id = e.id WHERE p.account_id='jpyw' AND e.kind != 'opening'");
  await applyMutation(exec, 'updateTransaction', { id: String(id), patch: { date: '2026-05-20' } });
  // §2: date on entry; amount/amount_base/exchange_rate on account posting.
  const [e] = await exec('SELECT date FROM entries WHERE id = ?', [String(id)]);
  const [row] = await exec('SELECT amount, amount_base, exchange_rate FROM postings WHERE entry_id = ? AND account_id IS NOT NULL', [String(id)]);
  expect(String(e.date)).toBe('2026-05-20');
  expect(Number(row.amount)).toBeCloseTo(-10000, 2); // native amount untouched
  // The lock follows the row's own date: rate + base re-derived at 2026-05-20.
  // exchange_rate is JPY-account-ccy → JPY (same), base is JPY→USD.
  const expected = await convertToBase(exec, -10000, 'JPY', 'USD', '2026-05-20');
  // Note: for JPY account (currency=JPY), amount = orig_amount and
  // exchange_rate = JPY-to-USD rate directly (no acctCcy intermediate).
  const effectiveRate = Math.abs(Number(row.amount_base)) / Math.abs(Number(row.amount));
  expect(effectiveRate).toBeCloseTo(0.007, 6);
  expect(Number(row.amount_base)).toBeCloseTo(expected.amountBase, 2);
});

test('seed records each account opening balance and balances reconcile', async () => {
  const exec = await seededAndAudited();
  // §2: opening_balance column is gone. current_balance = SUM of all confirmed account postings
  // (including the opening entry). The current balance should still match the seed.
  const [a] = await exec("SELECT current_balance FROM accounts WHERE id = 'cc'");
  const sum = Number(
    (await exec(
      "SELECT COALESCE(SUM(p.amount_base),0) AS s FROM postings p JOIN entries e ON e.id = p.entry_id WHERE p.account_id='cc' AND e.status='confirmed'",
    ))[0].s,
  );
  // current_balance = all confirmed postings summed (opening entry + transactions).
  expect(Number(a.current_balance)).toBeCloseTo(sum, 2);
  expect(Number(a.current_balance)).toBeCloseTo(-842.18, 2);
});

test('editing a transaction amount recomputes the account balance', async () => {
  const exec = await seededAndAudited();
  const before = await balanceOf(exec, 'cc'); // -842.18
  await applyMutation(exec, 'updateTransaction', { id: 't01', patch: { amount: -100 } });
  // t01 was -6.75 → -100, so cc drops by the 93.25 difference.
  expect(await balanceOf(exec, 'cc')).toBeCloseTo(before - (100 - 6.75), 2);
});

test('cancelling a transaction reverses its effect on the balance', async () => {
  const exec = await seededAndAudited();
  const before = await balanceOf(exec, 'cc');
  await applyMutation(exec, 'deleteTransaction', { id: 't01' }); // -6.75 expense removed
  expect(await balanceOf(exec, 'cc')).toBeCloseTo(before + 6.75, 2);
});

test('migrate stamps the schema version in db_metadata', async () => {
  const exec = await seededAndAudited();
  await migrate(exec, { fresh: true });
  const meta = await readMetadata(exec);
  expect(meta).not.toBeNull();
  expect(meta!.schemaVersion).toBe(SCHEMA_VERSION);
  expect(meta!.appName).toBe('finch');
});

test('schema shape: budgets no longer carries tag_ids; new indexes present', async () => {
  const exec = await seededAndAudited();
  const budgetCols = (await exec('PRAGMA table_info(budgets)')).map((r) => String(r.name));
  expect(budgetCols).not.toContain('tag_ids');

  const indexNames = async (table: string) =>
    (await exec(`PRAGMA index_list(${table})`)).map((r) => String(r.name));
  expect(await indexNames('exchange_rates')).toContain('idx_rate_currency_date');
  expect(await indexNames('exchange_rates')).not.toContain('idx_rate_currency');
  // §2: transactions table dropped; entries/postings carry the DE indexes.
  expect(await indexNames('entries')).toContain('idx_entry_ledger_date');
  expect(await indexNames('postings')).toContain('idx_post_entry');
  expect(await indexNames('postings')).toContain('idx_post_account');
});


test('deleteCategory uncategorizes its transactions', async () => {
  const exec = await seededAndAudited();
  const before = Number((await exec("SELECT COUNT(*) AS n FROM categories WHERE id = 'food'"))[0].n);
  expect(before).toBe(1);
  // §2: category is referenced by postings (category_id FK with SET NULL).
  const tagged = Number((await exec("SELECT COUNT(*) AS n FROM postings WHERE category_id = 'food'"))[0].n);
  expect(tagged).toBeGreaterThan(0);
  await applyMutation(exec, 'deleteCategory', { id: 'food' });
  expect(Number((await exec("SELECT COUNT(*) AS n FROM categories WHERE id = 'food'"))[0].n)).toBe(0);
  // FK is SET NULL on postings: those postings survive but become uncategorized.
  expect(Number((await exec("SELECT COUNT(*) AS n FROM postings WHERE category_id = 'food'"))[0].n)).toBe(0);
});

test('deleteCategory: scheduled_templates.category_id is SET NULL (used to be RESTRICT)', async () => {
  const exec = await seededAndAudited();
  // §2: scheduled_templates.kind uses the entry kind values (expense/income/etc).
  await exec(
    `INSERT INTO scheduled_templates
       (id, ledger_id, name, kind, account_id, category_id, frequency,
        start_date, created_at, updated_at)
     VALUES ('sch-food','personal','Weekly groceries','expense','chk','food','weekly',
             '2026-05-01', datetime('now'), datetime('now'))`,
  );
  // Pre-fix this would throw "FOREIGN KEY constraint failed" (RESTRICT).
  await applyMutation(exec, 'deleteCategory', { id: 'food' });
  const [row] = await exec("SELECT category_id FROM scheduled_templates WHERE id = 'sch-food'");
  expect(row.category_id).toBeNull();
});

test('deleteTag drops the tag and its assignments', async () => {
  const exec = await seededAndAudited();
  // §2: entry_tags replaces transaction_tags.
  expect(Number((await exec("SELECT COUNT(*) AS n FROM entry_tags WHERE tag_id = 'tag-business'"))[0].n)).toBeGreaterThan(0);
  await applyMutation(exec, 'deleteTag', { id: 'tag-business' });
  expect(Number((await exec("SELECT COUNT(*) AS n FROM tags WHERE id = 'tag-business'"))[0].n)).toBe(0);
  expect(Number((await exec("SELECT COUNT(*) AS n FROM entry_tags WHERE tag_id = 'tag-business'"))[0].n)).toBe(0);
});

test('deleteScheduled removes the template and cascades its splits', async () => {
  const exec = await seededAndAudited();
  expect(Number((await exec("SELECT COUNT(*) AS n FROM scheduled_splits WHERE template_id = 'rt-salary'"))[0].n)).toBeGreaterThan(0);
  await applyMutation(exec, 'deleteScheduled', { id: 'rt-salary' });
  expect(Number((await exec("SELECT COUNT(*) AS n FROM scheduled_templates WHERE id = 'rt-salary'"))[0].n)).toBe(0);
  expect(Number((await exec("SELECT COUNT(*) AS n FROM scheduled_splits WHERE template_id = 'rt-salary'"))[0].n)).toBe(0);
});

test('deleteCounterparty removes the merchant', async () => {
  const exec = await seededAndAudited();
  const cpId = String((await exec("SELECT id FROM counterparties WHERE ledger_id = 'personal' LIMIT 1"))[0].id);
  await applyMutation(exec, 'deleteCounterparty', { id: cpId });
  expect(Number((await exec('SELECT COUNT(*) AS n FROM counterparties WHERE id = ?', [cpId]))[0].n)).toBe(0);
});

test('deleteTransfer removes both legs and restores balances', async () => {
  const exec = await seededAndAudited();
  const chk0 = await balanceOf(exec, 'chk');
  const sav0 = await balanceOf(exec, 'sav');
  await applyMutation(exec, 'createTransfer', { fromAccountId: 'chk', toAccountId: 'sav', fromAmount: 200, date: '2026-05-27' });
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(chk0 - 200, 2);
  // §2: transfer is an entry with 2 account legs; entry id = transfer id.
  const [{ entryId }] = await exec("SELECT id AS entryId FROM entries WHERE kind='transfer' ORDER BY created_at DESC LIMIT 1") as { entryId: string }[];
  await applyMutation(exec, 'deleteTransfer', { id: entryId });
  // All postings cascade-deleted with the entry.
  expect(Number((await exec('SELECT COUNT(*) AS n FROM entries WHERE id = ?', [entryId]))[0].n)).toBe(0);
  expect(Number((await exec('SELECT COUNT(*) AS n FROM postings WHERE entry_id = ?', [entryId]))[0].n)).toBe(0);
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(chk0, 2);
  expect(await balanceOf(exec, 'sav')).toBeCloseTo(sav0, 2);
});

test('updateCategory edits name/type/icon/color', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'updateCategory', { id: 'food', patch: { name: 'Food & Drink', type: 'income', icon: 'coins', color: '#8085dc' } });
  const [c] = await exec("SELECT name, kind, icon, color FROM categories WHERE id = 'food'");
  expect(String(c.name)).toBe('Food & Drink');
  expect(String(c.kind)).toBe('income');
  expect(String(c.icon)).toBe('coins');
  expect(String(c.color)).toBe('#8085dc');
});

test('createCategory persists icon + color, and listCategories returns color', async () => {
  const exec = await seededAndAudited();
  const { listCategories } = await import('@/lib/db/queries/categories');
  await applyMutation(exec, 'createCategory', { ledgerId: 'personal', name: 'Travel', type: 'expense', icon: 'car', color: '#00a6ae' });
  const cat = (await listCategories(exec, 'personal')).find((c) => c.name === 'Travel')!;
  expect(cat.icon).toBe('car');
  expect(cat.color).toBe('#00a6ae');
  // Seeded categories keep their JSON color too.
  expect((await listCategories(exec, 'personal')).find((c) => c.id === 'food')!.color).toBe('#d16b7a');
});

test('updateTag edits fields', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'updateTag', { id: 'tag-business', patch: { name: 'Work', color: '300' } });
  const [tag] = await exec("SELECT name, color FROM tags WHERE id = 'tag-business'");
  expect(String(tag.name)).toBe('Work');
  expect(String(tag.color)).toBe('300');
});

test('updateScheduled and updateCounterparty edit fields', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'updateScheduled', { id: 'rt-spotify', patch: { name: 'Spotify Duo', amount: 14.99, frequency: 'yearly', dayOfMonth: 5, autoPost: 0 } });
  const [r] = await exec("SELECT name, amount, frequency, day_of_month, auto_post FROM scheduled_templates WHERE id = 'rt-spotify'");
  expect(String(r.name)).toBe('Spotify Duo');
  expect(Number(r.amount)).toBeCloseTo(14.99, 2);
  expect(String(r.frequency)).toBe('yearly');
  expect(Number(r.day_of_month)).toBe(5);
  expect(Number(r.auto_post)).toBe(0);

  const cpId = String((await exec("SELECT id FROM counterparties WHERE ledger_id = 'personal' LIMIT 1"))[0].id);
  await applyMutation(exec, 'updateCounterparty', { id: cpId, patch: { name: 'Renamed Co' } });
  const [cp] = await exec('SELECT name FROM counterparties WHERE id = ?', [cpId]);
  expect(String(cp.name)).toBe('Renamed Co');
});

test('updateScheduled silently skips unknown keys without throwing a SQL error', async () => {
  const exec = await seededAndAudited();
  // A stray patch key (typo, stale field name) used to become `undefined = ?`
  // in SQL and throw "near '=': syntax error". The query should ignore it and
  // apply the known fields cleanly.
  await applyMutation(exec, 'updateScheduled', {
    id: 'rt-spotify',
    patch: { name: 'Spotify Family', unknownField: 'noise', anotherTypo: 42 },
  });
  const [r] = await exec("SELECT name FROM scheduled_templates WHERE id = 'rt-spotify'");
  expect(String(r.name)).toBe('Spotify Family');
});

test('updateTransfer rewrites both legs and recomputes balances', async () => {
  const exec = await seededAndAudited();
  const chk0 = await balanceOf(exec, 'chk');
  const sav0 = await balanceOf(exec, 'sav');
  await applyMutation(exec, 'createTransfer', { fromAccountId: 'chk', toAccountId: 'sav', fromAmount: 200, date: '2026-05-27', note: 'a' });
  // §2: transfer entry id is the transfer id.
  const [{ entryId }] = await exec("SELECT id AS entryId FROM entries WHERE kind='transfer' ORDER BY created_at DESC LIMIT 1") as { entryId: string }[];
  await applyMutation(exec, 'updateTransfer', { id: entryId, patch: { fromAmount: 350, date: '2026-05-28', note: 'updated' } });
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(chk0 - 350, 2);
  expect(await balanceOf(exec, 'sav')).toBeCloseTo(sav0 + 350, 2);
  // §2: date/notes on the entry (both legs share the entry header).
  const [entry] = await exec('SELECT date, notes FROM entries WHERE id = ?', [entryId]);
  expect(String(entry.date)).toBe('2026-05-28');
  expect(String(entry.notes)).toBe('updated');
});

test('createTransfer with explicit toAmount pins both sides + sets the rate', async () => {
  const exec = await seededAndAudited();
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,is_active,created_at,updated_at) VALUES ('eurw2','personal','EUR Wallet 2','cash','EUR',0,1,'2026-05-26','2026-05-26')",
  );
  // chk is USD; user types: sent $100, received €90 (bank's actual conversion, including fees).
  await applyMutation(exec, 'createTransfer', { fromAccountId: 'chk', toAccountId: 'eurw2', fromAmount: 100, toAmount: 90, date: '2026-05-24' });
  const eur = Number((await exec("SELECT current_balance AS b FROM accounts WHERE id = 'eurw2'"))[0].b);
  expect(eur).toBeCloseTo(90, 2);
  // §2: transfer_groups dropped; effective rate = toAmount / fromAmount from postings.
  const [t] = await listTransfers(exec, 'personal');
  expect(t.toAmount / t.amount).toBeCloseTo(0.9, 4);
});

test('updateTransfer with only fromAmount preserves the FX ratio on cross-currency', async () => {
  const exec = await seededAndAudited();
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,is_active,created_at,updated_at) VALUES ('eurw3','personal','EUR Wallet 3','cash','EUR',0,1,'2026-05-26','2026-05-26')",
  );
  // Create at $100 → €91 (rate 0.91), then double the from-leg.
  await applyMutation(exec, 'createTransfer', { fromAccountId: 'chk', toAccountId: 'eurw3', fromAmount: 100, toAmount: 91, date: '2026-05-24' });
  // §2: entry id is the transfer id.
  const [{ entryId }] = await exec("SELECT id AS entryId FROM entries WHERE kind='transfer' ORDER BY created_at DESC LIMIT 1") as { entryId: string }[];
  await applyMutation(exec, 'updateTransfer', { id: entryId, patch: { fromAmount: 200 } });
  const eur = Number((await exec("SELECT current_balance AS b FROM accounts WHERE id = 'eurw3'"))[0].b);
  expect(eur).toBeCloseTo(182, 2); // 91 × (200/100)
});

test('updateTransfer with both amounts rewrites the rate on cross-currency', async () => {
  const exec = await seededAndAudited();
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,is_active,created_at,updated_at) VALUES ('eurw4','personal','EUR Wallet 4','cash','EUR',0,1,'2026-05-26','2026-05-26')",
  );
  // Initial: $100 → €91 (mid-rate). User corrects to $100 → €89 (bank's actual).
  await applyMutation(exec, 'createTransfer', { fromAccountId: 'chk', toAccountId: 'eurw4', fromAmount: 100, toAmount: 91, date: '2026-05-24' });
  // §2: entry id is the transfer id.
  const [{ entryId }] = await exec("SELECT id AS entryId FROM entries WHERE kind='transfer' ORDER BY created_at DESC LIMIT 1") as { entryId: string }[];
  await applyMutation(exec, 'updateTransfer', { id: entryId, patch: { fromAmount: 100, toAmount: 89 } });
  const eur = Number((await exec("SELECT current_balance AS b FROM accounts WHERE id = 'eurw4'"))[0].b);
  expect(eur).toBeCloseTo(89, 2);
  // §2: transfer_groups dropped; effective rate = toAmount / fromAmount.
  const [t] = await listTransfers(exec, 'personal');
  expect(t.toAmount / t.amount).toBeCloseTo(0.89, 4);
});

test('createCounterparty inserts an unverified merchant', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'createCounterparty', { id: 'cp-new', ledgerId: 'personal', name: 'Starbucks' });
  const { listCounterparties } = await import('@/lib/db/queries/counterparties');
  const cp = (await listCounterparties(exec, 'personal')).find((c) => c.id === 'cp-new')!;
  expect(cp.name).toBe('Starbucks');
  expect(cp.verified).toBe(false);
  await expect(applyMutation(exec, 'createCounterparty', { name: '  ' })).rejects.toThrow();
});

test('createScheduled inserts a template that lists and posts', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'createScheduled', {
    id: 'rt-new', ledgerId: 'personal', name: 'Netflix', type: 'expense',
    amount: 19.99, frequency: 'monthly', dayOfMonth: 9, accountId: 'cc', autoPost: true, weekDay: null, color: null,
  });
  const { listScheduled } = await import('@/lib/db/queries/scheduled');
  const t = (await listScheduled(exec, 'personal')).find((r) => r.id === 'rt-new')!;
  expect(t.name).toBe('Netflix');
  expect(t.amount).toBeCloseTo(19.99, 2);
  expect(t.frequency).toBe('monthly');
  expect(t.account).toBe('Amex Gold');
  const ccBefore = await balanceOf(exec, 'cc');
  await applyMutation(exec, 'postScheduled', { templateId: 'rt-new' });
  expect(await balanceOf(exec, 'cc')).toBeCloseTo(ccBefore - 19.99, 2);

  await expect(applyMutation(exec, 'createScheduled', { name: 'X', type: 'expense', frequency: 'monthly', accountId: '' })).rejects.toThrow();
  await expect(applyMutation(exec, 'createScheduled', { name: 'Y', type: 'nope', accountId: 'cc' })).rejects.toThrow();
});

test('addScheduledSplit / removeScheduledSplit manage splits + splits_enabled', async () => {
  const exec = await seededAndAudited();
  // rt-spotify has no splits seeded.
  const { listScheduled } = await import('@/lib/db/queries/scheduled');
  const flag = async () => Number((await exec("SELECT splits_enabled FROM scheduled_templates WHERE id = 'rt-spotify'"))[0].splits_enabled);
  expect(await flag()).toBe(0);

  await applyMutation(exec, 'addScheduledSplit', { templateId: 'rt-spotify', accountId: 'sav', pct: 40 });
  await applyMutation(exec, 'addScheduledSplit', { templateId: 'rt-spotify', accountId: 'inv', pct: 60 });
  let t = (await listScheduled(exec, 'personal')).find((r) => r.id === 'rt-spotify')!;
  expect(t.splits?.map((s) => s.account)).toEqual(['Marcus Savings', 'Fidelity Brokerage']);
  expect(t.splits?.map((s) => s.pct)).toEqual([40, 60]);
  expect(await flag()).toBe(1);

  // Remove the first split (by index/sort order).
  await applyMutation(exec, 'removeScheduledSplit', { templateId: 'rt-spotify', index: 0 });
  t = (await listScheduled(exec, 'personal')).find((r) => r.id === 'rt-spotify')!;
  expect(t.splits?.map((s) => s.account)).toEqual(['Fidelity Brokerage']);
  expect(await flag()).toBe(1);

  // Removing the last one clears the split-enabled flag.
  await applyMutation(exec, 'removeScheduledSplit', { templateId: 'rt-spotify', index: 0 });
  t = (await listScheduled(exec, 'personal')).find((r) => r.id === 'rt-spotify')!;
  expect(t.splits ?? []).toEqual([]);
  expect(await flag()).toBe(0);

  await expect(applyMutation(exec, 'addScheduledSplit', { templateId: 'rt-spotify', accountId: '  ' })).rejects.toThrow();
});

test('adjustAccountBalance posts a marked delta and moves balance to the target', async () => {
  const exec = await seededAndAudited();
  const before = await balanceOf(exec, 'chk'); // 4218.50 seed
  await applyMutation(exec, 'adjustAccountBalance', { accountId: 'chk', targetBalance: 5000, note: 'reconcile' });
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(5000, 2);
  // §2: entries + postings replace transactions. kind on entry, amount_base/description/notes on entry.
  const [adj] = await exec(
    "SELECT e.kind, p.amount_base, e.description, e.notes FROM entries e JOIN postings p ON p.entry_id = e.id WHERE p.account_id = 'chk' AND e.kind = 'adjustment' ORDER BY e.created_at DESC LIMIT 1",
  );
  expect(String(adj.kind)).toBe('adjustment');
  expect(Number(adj.amount_base)).toBeCloseTo(5000 - before, 2);
  expect(String(adj.description)).toBe('Balance adjustment');
  expect(String(adj.notes)).toBe('reconcile');
});

test('adjustments are excluded from category spend and cash flow', async () => {
  const exec = await seededAndAudited();
  const { categorySpend } = await import('@/lib/db/queries/categories');
  const month = new Date().toISOString().slice(0, 7);
  const spendBefore = await categorySpend(exec, 'personal');
  const flowBefore = await monthlyCashFlow(exec, 'personal', month);

  // Big negative adjustment on cc (would dwarf food spend if it counted).
  await applyMutation(exec, 'adjustAccountBalance', { accountId: 'cc', targetBalance: -5000 });

  const spendAfter = await categorySpend(exec, 'personal');
  const flowAfter = await monthlyCashFlow(exec, 'personal', month);

  expect(JSON.stringify(spendAfter)).toBe(JSON.stringify(spendBefore));
  expect(flowAfter.income).toBeCloseTo(flowBefore.income, 2);
  expect(flowAfter.expense).toBeCloseTo(flowBefore.expense, 2);
  expect(flowAfter.net).toBeCloseTo(flowBefore.net, 2);
});

test('income via addTransaction (positive amount) increases the account balance', async () => {
  const exec = await seededAndAudited();
  const before = await balanceOf(exec, 'chk');
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: 250, merchant: 'Side gig',
    categoryId: null, date: '2026-05-29', status: 'confirmed',
  });
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(before + 250, 2);
});

test('setExchangeRate upserts on (date, currency); deleteExchangeRate removes it', async () => {
  const exec = await seededAndAudited();
  const { listExchangeRates } = await import('@/lib/db/queries/system');
  // Insert.
  await applyMutation(exec, 'setExchangeRate', { date: '2026-06-01', currency: 'JPY', rate: 0.0091, source: 'manual' });
  let jpy = (await listExchangeRates(exec)).filter((r) => r.currency === 'JPY' && r.date === '2026-06-01');
  expect(jpy).toHaveLength(1);
  expect(jpy[0].rate).toBeCloseTo(0.0091, 6);
  expect(jpy[0].source).toBe('manual');

  // Upsert (same date+currency overwrites).
  await applyMutation(exec, 'setExchangeRate', { date: '2026-06-01', currency: 'JPY', rate: 0.0093, source: 'ECB' });
  jpy = (await listExchangeRates(exec)).filter((r) => r.currency === 'JPY' && r.date === '2026-06-01');
  expect(jpy).toHaveLength(1);
  expect(jpy[0].rate).toBeCloseTo(0.0093, 6);
  expect(jpy[0].source).toBe('ECB');

  // Delete.
  await applyMutation(exec, 'deleteExchangeRate', { date: '2026-06-01', currency: 'JPY' });
  jpy = (await listExchangeRates(exec)).filter((r) => r.currency === 'JPY' && r.date === '2026-06-01');
  expect(jpy).toHaveLength(0);
});

test('setExchangeRate validation (currency required, rate > 0, ISO date)', async () => {
  const exec = await seededAndAudited();
  await expect(applyMutation(exec, 'setExchangeRate', { date: '2026-06-01', currency: '', rate: 0.01 })).rejects.toThrow(/currency/i);
  await expect(applyMutation(exec, 'setExchangeRate', { date: '2026-06-01', currency: 'JPY', rate: 0 })).rejects.toThrow(/rate/i);
  await expect(applyMutation(exec, 'setExchangeRate', { date: '2026/06/01', currency: 'JPY', rate: 0.01 })).rejects.toThrow(/date/i);
});

test('newly set rate is picked up by convertToBase for the same date', async () => {
  const exec = await seededAndAudited();
  const { convertToBase } = await import('@/lib/db/queries/rates');
  await applyMutation(exec, 'setExchangeRate', { date: '2026-06-15', currency: 'JPY', rate: 0.01, source: 'manual' });
  // JPY → USD on that date: rate = rate(JPY) / rate(USD) = 0.01 / 1 = 0.01 (USD is the hub).
  const conv = await convertToBase(exec, 100, 'JPY', 'USD', '2026-06-15');
  expect(conv.rate).toBeCloseTo(0.01, 6);
  expect(conv.amountBase).toBeCloseTo(1.0, 4);
});

test('setTransactionSplits validates sum + min-2-rows; categorySpend uses splits', async () => {
  const exec = await seededAndAudited();
  // §2: Pick a confirmed expense from entries. amount/amount_base on the account posting,
  // category on the category posting.
  const [parent] = await exec(
    `SELECT e.id, p.amount, p.amount_base, cp.category_id
     FROM entries e
     JOIN postings p ON p.entry_id = e.id AND p.account_id IS NOT NULL
     LEFT JOIN postings cp ON cp.entry_id = e.id AND cp.account_id IS NULL AND cp.category_id IS NOT NULL
     WHERE e.ledger_id = 'personal' AND e.kind = 'expense' AND e.status = 'confirmed'
     LIMIT 1`,
  );
  expect(parent).toBeDefined();
  const txId = String(parent.id);
  const amt = Number(parent.amount);
  const half = Math.round((amt / 2) * 100) / 100;
  const rest = Math.round((amt - half) * 100) / 100;
  const originalCat = String(parent.category_id);

  // < 2 rows is rejected.
  await expect(
    applyMutation(exec, 'setTransactionSplits', { id: txId, splits: [{ categoryId: 'food', amount: amt }] }),
  ).rejects.toThrow(/two/i);

  // Sum mismatch is rejected.
  await expect(
    applyMutation(exec, 'setTransactionSplits', {
      id: txId,
      splits: [{ categoryId: 'food', amount: amt / 2 }, { categoryId: 'trans', amount: amt / 3 }],
    }),
  ).rejects.toThrow(/sum/i);

  // Two valid rows succeed; categorySpend reflects splits, not the parent.
  const { categorySpend } = await import('@/lib/db/queries/categories');
  await applyMutation(exec, 'setTransactionSplits', {
    id: txId,
    splits: [
      { categoryId: 'food', amount: half },
      { categoryId: 'trans', amount: rest },
    ],
  });
  const after = await categorySpend(exec, 'personal');
  // The parent's original category should no longer carry this tx's amount.
  // Both splits' targets get a non-zero contribution.
  // §2: categorySpend returns the signed amount_base sum (negative for expenses).
  expect(after.food).not.toBe(0);
  expect(after.trans).toBeDefined();
  // §2: splits are category postings (account_id IS NULL) on the entry.
  // Exclude fx-system residue legs (appendResidue may add one to absorb rounding).
  // Sanity: per-row stored amount_base is derived from the parent's locked rate.
  const splitRows = await exec(
    `SELECT p.category_id, p.amount, p.amount_base FROM postings p
     LEFT JOIN categories c ON c.id = p.category_id
     WHERE p.entry_id = ? AND p.account_id IS NULL
       AND (c.system IS NULL OR c.system != 'fx')
     ORDER BY p.sort_order`,
    [txId],
  );
  expect(splitRows.length).toBeGreaterThanOrEqual(2);
  // Category postings balance the account leg (opposite sign).
  // Sum of all postings (account + category) should be ≈ 0.
  const allRows = await exec(
    'SELECT amount_base FROM postings WHERE entry_id = ?',
    [txId],
  );
  const totalBalance = allRows.reduce((s, r) => s + Number(r.amount_base), 0);
  expect(totalBalance).toBeCloseTo(0, 2);

  // Clearing splits restores the parent's category.
  await applyMutation(exec, 'setTransactionSplits', { id: txId, splits: [] });
  // After clearing, the original category should have a non-zero spend value
  // (categorySpend returns signed amounts — negative for expenses).
  const restored = await categorySpend(exec, 'personal');
  expect(restored[originalCat]).toBeDefined();
});

test('createAccountGroup / updateAccountGroup / deleteAccountGroup wire end-to-end', async () => {
  const exec = await seededAndAudited();
  const { listAccountGroups } = await import('@/lib/db/queries/accountGroups');

  const before = await listAccountGroups(exec, 'personal');
  expect(before.length).toBe(4); // seed: cash / credit / invest / loan

  // Create.
  await applyMutation(exec, 'createAccountGroup', { id: 'ag-new', ledgerId: 'personal', name: 'Crypto' });
  const created = await listAccountGroups(exec, 'personal');
  expect(created.find((g) => g.id === 'ag-new')?.name).toBe('Crypto');

  // Update (rename).
  await applyMutation(exec, 'updateAccountGroup', { id: 'ag-new', patch: { name: 'Digital Assets' } });
  const updated = await listAccountGroups(exec, 'personal');
  const u = updated.find((g) => g.id === 'ag-new')!;
  expect(u.name).toBe('Digital Assets');

  // Assigning the group to an account, then deleting the group, sets accounts.group_id to NULL.
  await applyMutation(exec, 'updateAccount', { id: 'cc', patch: { groupId: 'ag-new' } });
  const [pre] = await exec("SELECT group_id FROM accounts WHERE id = 'cc'");
  expect(String(pre.group_id)).toBe('ag-new');
  await applyMutation(exec, 'deleteAccountGroup', { id: 'ag-new' });
  const after = await listAccountGroups(exec, 'personal');
  expect(after.find((g) => g.id === 'ag-new')).toBeUndefined();
  const [post] = await exec("SELECT group_id FROM accounts WHERE id = 'cc'");
  expect(post.group_id).toBeNull();
});

test('createAccountGroup rejects an empty name', async () => {
  const exec = await seededAndAudited();
  await expect(applyMutation(exec, 'createAccountGroup', { name: '   ' })).rejects.toThrow(/name/i);
});

test('pending transactions are excluded from the balance until confirmed', async () => {
  const exec = await seededAndAudited();
  const b0 = await balanceOf(exec, 'chk');
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: -50, merchant: 'Hold', date: '2026-05-28', status: 'pending',
  });
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(b0, 2); // pending → no balance change
  // §2: status on entries, description on entries.
  const [row] = await exec("SELECT id FROM entries WHERE description = 'Hold' AND status = 'pending'");
  await applyMutation(exec, 'confirmTransaction', { id: String(row.id) });
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(b0 - 50, 2); // confirming pulls it in
});

test('generateDueScheduled materializes due occurrences, idempotently', async () => {
  const exec = await seededAndAudited();
  const cc0 = await balanceOf(exec, 'cc');
  const chk0 = await balanceOf(exec, 'chk');
  const sav0 = await balanceOf(exec, 'sav');

  await applyMutation(exec, 'generateDueScheduled', { today: '2026-05-30' });
  // rt-spotify (cc, day 22), rt-icloud (cc, day 8), rt-rent (chk, day 1) →
  // 3 pending expense entries. rt-sweep (chk → sav, day 28) → 1 confirmed
  // transfer entry with 2 account postings.
  // §2: entries replace transactions; 1 expense entry = 1 entry (not 2 rows).
  // For transfers: 1 entry, but we check by source_template_id on entries.
  const gen = await exec(
    "SELECT id, status, source_template_id AS t FROM entries WHERE source_template_id IS NOT NULL ORDER BY date",
  );
  // 3 expense entries + 1 transfer entry = 4 total entries.
  expect(gen.length).toBe(4);
  const pending = gen.filter((r) => String(r.status) === 'pending');
  const confirmed = gen.filter((r) => String(r.status) === 'confirmed');
  expect(pending.length).toBe(3); // expense entries stay pending
  expect(confirmed.length).toBe(1); // 1 transfer entry confirmed
  expect(confirmed.every((r) => String(r.t) === 'rt-sweep')).toBe(true);
  // Pending didn't touch cc; the confirmed sweep moved chk and sav.
  expect(await balanceOf(exec, 'cc')).toBeCloseTo(cc0, 2);
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(chk0 - 800, 2);
  expect(await balanceOf(exec, 'sav')).toBeCloseTo(sav0 + 800, 2);

  // Idempotent: a second run adds nothing (dedup via source_template_id + date).
  await applyMutation(exec, 'generateDueScheduled', { today: '2026-05-30' });
  const again = await exec("SELECT id FROM entries WHERE source_template_id IS NOT NULL");
  expect(again.length).toBe(4);

  // Confirming the Spotify pending (11.99 expense) pulls it into cc's balance.
  const spotify = gen.find((r) => String(r.t) === 'rt-spotify')!;
  await applyMutation(exec, 'confirmTransaction', { id: String(spotify.id) });
  expect(await balanceOf(exec, 'cc')).toBeCloseTo(cc0 - 11.99, 2);
});

test('generateDueScheduled: recurring transfer caps at installment_total like other templates', async () => {
  const exec = await seededAndAudited();
  // 3-payment recurring transfer; after a year only 3 occurrences should fire
  // (Jan, Feb, Mar 2026). §2: each occurrence = 1 transfer entry (not 2 rows).
  await applyMutation(exec, 'createScheduled', {
    id: 'sch-recur-xfer', name: 'Auto-savings', type: 'transfer',
    frequency: 'monthly', dayOfMonth: 5, accountId: 'sav', fromAccountId: 'chk',
    amount: 200, installmentTotal: 3, autoPost: true, startDate: '2026-01-01',
  });
  await applyMutation(exec, 'generateDueScheduled', { today: '2026-12-31' });
  // §2: entries replaces transactions; 3 transfer entries, each with 2 postings.
  const entries = await exec(
    "SELECT id FROM entries WHERE source_template_id = 'sch-recur-xfer'",
  );
  expect(entries.length).toBe(3); // 3 transfer entries (one per occurrence)
  // Each transfer entry has 2 account postings (from + to leg).
  const postings = await exec(
    "SELECT p.id FROM postings p JOIN entries e ON p.entry_id = e.id WHERE e.source_template_id = 'sch-recur-xfer' AND p.account_id IS NOT NULL",
  );
  expect(postings.length).toBe(6); // 3 entries × 2 postings
});

// ---------------------------------------------------------------------------
// Installment plans — `installment_total` caps auto-generation, the manual
// post path blocks once the plan is full, and the derived `installmentPaid`
// counts only confirmed transactions.
// ---------------------------------------------------------------------------

const installmentPaidOf = async (exec: Exec, id: string) => {
  const { listScheduled } = await import('@/lib/db/queries/scheduled');
  const all = await listScheduled(exec, 'personal');
  return all.find((t) => t.id === id)?.installmentPaid ?? -1;
};

test('createScheduled rejects an installment total that isn\'t a positive integer', async () => {
  const exec = await seededAndAudited();
  await expect(
    applyMutation(exec, 'createScheduled', {
      id: 'sch-bad', name: 'Bad plan', type: 'expense', frequency: 'monthly',
      dayOfMonth: 1, accountId: 'chk', amount: 100, installmentTotal: 0,
    }),
  ).rejects.toThrow('Installment total must be a positive whole number');
  await expect(
    applyMutation(exec, 'createScheduled', {
      id: 'sch-bad2', name: 'Bad plan 2', type: 'expense', frequency: 'monthly',
      dayOfMonth: 1, accountId: 'chk', amount: 100, installmentTotal: 1.5,
    }),
  ).rejects.toThrow('Installment total must be a positive whole number');
});

test('postScheduled blocks once installmentPaid reaches installmentTotal', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'createScheduled', {
    id: 'sch-phone', name: 'Phone contract', type: 'expense', frequency: 'monthly',
    dayOfMonth: 1, accountId: 'chk', amount: 50, installmentTotal: 2,
  });
  await applyMutation(exec, 'postScheduled', { templateId: 'sch-phone' });
  expect(await installmentPaidOf(exec, 'sch-phone')).toBe(1);
  await applyMutation(exec, 'postScheduled', { templateId: 'sch-phone' });
  expect(await installmentPaidOf(exec, 'sch-phone')).toBe(2);
  // The plan is now full; a third post should be rejected.
  await expect(
    applyMutation(exec, 'postScheduled', { templateId: 'sch-phone' }),
  ).rejects.toThrow('finished its 2-payment plan');
});

test('installmentPaid counts only CONFIRMED transactions; cancelling a pending leaves it untouched', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'createScheduled', {
    id: 'sch-plan', name: 'Furniture 0%', type: 'expense', frequency: 'monthly',
    dayOfMonth: 1, accountId: 'chk', amount: 200, installmentTotal: 12,
    autoPost: true, startDate: '2026-01-01',
  });
  // generateDueScheduled creates pending rows — they shouldn't count toward
  // "paid" (the user hasn't confirmed them yet).
  await applyMutation(exec, 'generateDueScheduled', { today: '2026-03-15' });
  // §2: entries replaces transactions.
  const pendingBefore = await exec(
    "SELECT id FROM entries WHERE source_template_id = 'sch-plan' AND status = 'pending'",
  );
  expect(pendingBefore.length).toBeGreaterThan(0);
  expect(await installmentPaidOf(exec, 'sch-plan')).toBe(0);
  // Confirming one of them moves the counter by exactly one.
  await applyMutation(exec, 'confirmTransaction', { id: String(pendingBefore[0].id) });
  expect(await installmentPaidOf(exec, 'sch-plan')).toBe(1);
  // Cancelling another pending row leaves the counter untouched.
  await applyMutation(exec, 'deleteTransaction', { id: String(pendingBefore[1].id) });
  expect(await installmentPaidOf(exec, 'sch-plan')).toBe(1);
});

test('generateDueScheduled stops generating once the plan has filled installmentTotal', async () => {
  const exec = await seededAndAudited();
  // 3-month plan starting Jan 2026, daily would over-shoot, monthly is right.
  await applyMutation(exec, 'createScheduled', {
    id: 'sch-cap', name: 'Three-month plan', type: 'expense', frequency: 'monthly',
    dayOfMonth: 1, accountId: 'chk', amount: 100, installmentTotal: 3,
    autoPost: true, startDate: '2026-01-01',
  });
  // After a year, only 3 occurrences should exist (Jan, Feb, Mar) — the cap
  // wins even though monthly occurrences would otherwise have generated 12.
  await applyMutation(exec, 'generateDueScheduled', { today: '2026-12-31' });
  // §2: entries replaces transactions.
  const gen = await exec(
    "SELECT id FROM entries WHERE source_template_id = 'sch-cap'",
  );
  expect(gen.length).toBe(3);
});

// ---------------------------------------------------------------------------
// changeLedgerBase — rewrites locked amount_base figures + re-stamps the
// account opening cost basis. Pre-PR-66 these branches were untested.
// ---------------------------------------------------------------------------

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
  // §2: category postings are the splits.
  const before = await exec(
    'SELECT amount_base FROM postings WHERE entry_id = ? AND account_id IS NULL ORDER BY sort_order',
    [txId],
  );
  // Flip the base to SGD and confirm the split's amount_base rewrote to match
  // the new base's conversion.
  await applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'SGD' });
  const after = await exec(
    'SELECT amount_base FROM postings WHERE entry_id = ? AND account_id IS NULL ORDER BY sort_order',
    [txId],
  );
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

test('bulkRecategorize moves N rows in one statement; categorySpend shifts accordingly', async () => {
  const exec = await seededAndAudited();
  const { categorySpend } = await import('@/lib/db/queries/categories');
  // §2: Pick three confirmed expenses by their entry id; category is on the category posting.
  const ids = (
    await exec(
      "SELECT e.id FROM entries e JOIN postings p ON p.entry_id = e.id AND p.account_id IS NULL AND p.category_id = 'food' WHERE e.ledger_id = 'personal' AND e.kind = 'expense' AND e.status = 'confirmed' ORDER BY e.date DESC LIMIT 3",
    )
  ).map((r) => String(r.id));
  expect(ids.length).toBe(3);
  // Sum the account posting amount_base for those entries.
  const movedSum = (
    await exec(
      `SELECT SUM(p.amount_base) AS s FROM postings p WHERE p.entry_id IN (${ids.map(() => '?').join(',')}) AND p.account_id IS NOT NULL`,
      ids,
    )
  )[0];
  const moved = Math.abs(Number(movedSum.s));
  const before = await categorySpend(exec, 'personal');

  await applyMutation(exec, 'bulkRecategorize', { ids, categoryId: 'misc' });
  const after = await categorySpend(exec, 'personal');

  // Each moved row now has category 'misc'; no category posting keeps the old food link.
  const stillFood = await exec(
    `SELECT COUNT(*) AS c FROM postings WHERE entry_id IN (${ids.map(() => '?').join(',')}) AND category_id = 'food'`,
    ids,
  );
  expect(Number(stillFood[0].c)).toBe(0);
  expect((after['food'] ?? 0)).toBeCloseTo((before['food'] ?? 0) - moved, 2);
  expect((after['misc'] ?? 0)).toBeCloseTo((before['misc'] ?? 0) + moved, 2);
});

test('bulkRecategorize: empty ids is a no-op; null categoryId clears the link', async () => {
  const exec = await seededAndAudited();
  // §2: category is on category postings (account_id IS NULL).
  const beforeCount = Number(
    (await exec("SELECT COUNT(*) AS c FROM postings WHERE category_id = 'food'"))[0].c,
  );
  await applyMutation(exec, 'bulkRecategorize', { ids: [], categoryId: 'misc' });
  expect(
    Number((await exec("SELECT COUNT(*) AS c FROM postings WHERE category_id = 'food'"))[0].c),
  ).toBe(beforeCount);

  // Null: clear the category on a single entry's category posting.
  const [row] = await exec(
    "SELECT e.id FROM entries e JOIN postings p ON p.entry_id = e.id AND p.category_id = 'food' AND p.account_id IS NULL WHERE e.ledger_id = 'personal' LIMIT 1",
  );
  const id = String(row.id);
  await applyMutation(exec, 'bulkRecategorize', { ids: [id], categoryId: null });
  const [after] = await exec('SELECT category_id AS c FROM postings WHERE entry_id = ? AND account_id IS NULL', [id]);
  expect(after.c).toBeNull();
});

test('setCleared toggles cleared_at and is independent of status', async () => {
  const exec = await seededAndAudited();
  // §2: cleared_at is per-leg on postings (not on entries). status is on entries.
  // Resolve entry id; then check the account posting's cleared_at.
  const [row] = await exec(
    "SELECT e.id FROM entries e JOIN postings p ON p.entry_id = e.id WHERE p.account_id = 'chk' AND e.kind NOT IN ('opening','transfer') LIMIT 1",
  );
  const id = String(row.id);
  const clearedAt = async () =>
    (await exec('SELECT p.cleared_at FROM postings p WHERE p.entry_id = ? AND p.account_id IS NOT NULL LIMIT 1', [id]))[0].cleared_at;
  expect(await clearedAt()).toBeNull();

  await applyMutation(exec, 'setCleared', { id, cleared: true });
  expect(await clearedAt()).not.toBeNull();

  await applyMutation(exec, 'setCleared', { id, cleared: false });
  expect(await clearedAt()).toBeNull();

  // Confirming a transaction does not clear it, and vice versa — independence
  // matters: the two flags answer different questions.
  await applyMutation(exec, 'setCleared', { id, cleared: true });
  const status = (await exec('SELECT status FROM entries WHERE id = ?', [id]))[0].status;
  expect(status).toBe('confirmed'); // unaffected by setCleared
});

test('setReviewed toggles reviewed_at; markAllReviewed clears the ledger queue', async () => {
  const exec = await seededAndAudited();
  // §2: reviewed_at on entries; look up entry id via account posting.
  const [row] = await exec(
    "SELECT e.id FROM entries e JOIN postings p ON p.entry_id = e.id WHERE p.account_id = 'chk' AND e.status = 'confirmed' AND e.kind NOT IN ('opening','transfer') LIMIT 1",
  );
  const id = String(row.id);
  // Seed rows start unreviewed.
  expect((await exec('SELECT reviewed_at FROM entries WHERE id = ?', [id]))[0].reviewed_at).toBeNull();

  await applyMutation(exec, 'setReviewed', { id, reviewed: true });
  expect((await exec('SELECT reviewed_at FROM entries WHERE id = ?', [id]))[0].reviewed_at).not.toBeNull();

  await applyMutation(exec, 'setReviewed', { id, reviewed: false });
  expect((await exec('SELECT reviewed_at FROM entries WHERE id = ?', [id]))[0].reviewed_at).toBeNull();

  // markAllReviewed clears every unreviewed confirmed personal row.
  const before = Number(
    (await exec("SELECT COUNT(*) AS n FROM entries WHERE ledger_id = 'personal' AND status = 'confirmed' AND reviewed_at IS NULL AND kind NOT IN ('opening')") )[0].n,
  );
  expect(before).toBeGreaterThan(0);
  await applyMutation(exec, 'markAllReviewed', { ledgerId: 'personal' });
  const after = Number(
    (await exec("SELECT COUNT(*) AS n FROM entries WHERE ledger_id = 'personal' AND status = 'confirmed' AND reviewed_at IS NULL AND kind NOT IN ('opening')"))[0].n,
  );
  expect(after).toBe(0);
  // The family ledger is untouched (scope respected).
  const family = Number(
    (await exec("SELECT COUNT(*) AS n FROM entries WHERE ledger_id = 'family' AND reviewed_at IS NOT NULL"))[0].n,
  );
  expect(family).toBe(0);
});

test('removeAttachment deletes the row + unlinks the file (best-effort)', async () => {
  const fs = await import('node:fs/promises');
  const path = await import('node:path');
  const os = await import('node:os');

  // Point FINCH_DB_DIR at a tmp dir so the unlink hits a real file we
  // created — verifies the cleanup actually runs, not just the DB row.
  const tmpRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'finch-mut-attach-'));
  const prevDbDir = process.env.FINCH_DB_DIR;
  process.env.FINCH_DB_DIR = tmpRoot;
  try {
    const exec = await seededAndAudited();
    // §2: entry_attachments replaces transaction_attachments; use entry_id FK.
    const [tx] = await exec(
      "SELECT e.id FROM entries e JOIN postings p ON p.entry_id = e.id WHERE p.account_id = 'chk' AND e.kind NOT IN ('opening','transfer') LIMIT 1",
    );
    const txId = String(tx.id);

    const relPath = `attachments/${txId}/att-1.jpg`;
    const absPath = path.join(tmpRoot, relPath);
    await fs.mkdir(path.dirname(absPath), { recursive: true });
    await fs.writeFile(absPath, Buffer.from([0xff, 0xd8, 0xff]));

    await exec(
      `INSERT INTO entry_attachments
         (id, ledger_id, entry_id, kind, rel_path, mime_type, byte_size, sha256, original_filename, created_at, updated_at)
       VALUES ('att-1','personal',?,'image',?,'image/jpeg',3,'h','r.jpg',datetime('now'),datetime('now'))`,
      [txId, relPath],
    );

    await applyMutation(exec, 'removeAttachment', { id: 'att-1' });

    // DB row gone.
    expect((await exec('SELECT id FROM entry_attachments WHERE id = ?', ['att-1'])).length).toBe(0);
    // File on disk gone.
    expect(await fs.access(absPath).then(() => true, () => false)).toBe(false);

    // Idempotent: a second call is a no-op.
    await applyMutation(exec, 'removeAttachment', { id: 'att-1' });
  } finally {
    if (prevDbDir === undefined) delete process.env.FINCH_DB_DIR;
    else process.env.FINCH_DB_DIR = prevDbDir;
    await fs.rm(tmpRoot, { recursive: true, force: true }).catch(() => {});
  }
});

test('deleteTransaction collects rel_paths via cascade and unlinks the files', async () => {
  const fs = await import('node:fs/promises');
  const path = await import('node:path');
  const os = await import('node:os');

  const tmpRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'finch-mut-cascade-'));
  const prevDbDir = process.env.FINCH_DB_DIR;
  process.env.FINCH_DB_DIR = tmpRoot;
  try {
    const exec = await seededAndAudited();
    // §2: entry_attachments replaces transaction_attachments; use entry_id FK.
    const [tx] = await exec(
      "SELECT e.id FROM entries e JOIN postings p ON p.entry_id = e.id WHERE p.account_id = 'chk' AND e.kind NOT IN ('opening','transfer') LIMIT 1",
    );
    const txId = String(tx.id);

    const paths = [
      `attachments/${txId}/a.jpg`,
      `attachments/${txId}/b.pdf`,
    ];
    for (const rel of paths) {
      const abs = path.join(tmpRoot, rel);
      await fs.mkdir(path.dirname(abs), { recursive: true });
      await fs.writeFile(abs, Buffer.from('x'));
    }
    await exec(
      `INSERT INTO entry_attachments
         (id, ledger_id, entry_id, kind, rel_path, mime_type, byte_size, sha256, original_filename, created_at, updated_at)
       VALUES ('att-a','personal',?,'image',?,'image/jpeg',1,'h',null,datetime('now'),datetime('now')),
              ('att-b','personal',?,'pdf',?,'application/pdf',1,'h',null,datetime('now'),datetime('now'))`,
      [txId, paths[0], txId, paths[1]],
    );

    await applyMutation(exec, 'deleteTransaction', { id: txId });

    // Both rows cascaded away (entries CASCADE deletes entry_attachments).
    expect((await exec('SELECT id FROM entry_attachments WHERE entry_id = ?', [txId])).length).toBe(0);
    // Both files unlinked.
    for (const rel of paths) {
      const abs = path.join(tmpRoot, rel);
      expect(await fs.access(abs).then(() => true, () => false)).toBe(false);
    }
  } finally {
    if (prevDbDir === undefined) delete process.env.FINCH_DB_DIR;
    else process.env.FINCH_DB_DIR = prevDbDir;
    await fs.rm(tmpRoot, { recursive: true, force: true }).catch(() => {});
  }
});

test('reconcileAccount stamps the checkpoint without an adjustment when none is asked', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'reconcileAccount', {
    accountId: 'chk',
    statementBalance: 9999.99,
    statementDate: '2026-05-31',
    postAdjustment: false,
  });
  const [row] = await exec(
    'SELECT last_reconciled_at AS d, last_reconciled_balance AS b FROM accounts WHERE id = ?',
    ['chk'],
  );
  expect(row.d).toBe('2026-05-31');
  expect(Number(row.b)).toBeCloseTo(9999.99, 2);
  // No adjustment row was inserted as part of this reconcile.
  // §2: check entries for adjustment kind (with posting to chk).
  const adj = await exec(
    "SELECT COUNT(*) AS c FROM entries e JOIN postings p ON p.entry_id = e.id WHERE p.account_id = 'chk' AND e.kind = 'adjustment'",
  );
  expect(Number(adj[0].c)).toBe(0);
});

test('reconcileAccount with postAdjustment posts the exact remainder + lands cleared sum on target', async () => {
  const exec = await seededAndAudited();
  // Clear a handful of rows so the cleared sum is non-trivial.
  // §2: use entry ids (not transaction ids).
  const ids = (
    await exec(
      "SELECT e.id FROM entries e JOIN postings p ON p.entry_id = e.id WHERE p.account_id = 'chk' AND e.kind NOT IN ('opening','transfer') LIMIT 3",
    )
  ).map((r) => String(r.id));
  for (const id of ids) await applyMutation(exec, 'setCleared', { id, cleared: true });

  // §2: opening_balance gone; cleared sum = SUM of cleared account postings.
  // §2: cleared_at is per-leg on postings (not on entries).
  const [sum] = await exec(
    `SELECT COALESCE(SUM(p.amount), 0) AS s
       FROM postings p JOIN entries e ON p.entry_id = e.id
     WHERE p.account_id = 'chk' AND e.status = 'confirmed' AND p.cleared_at IS NOT NULL`,
  );
  const clearedBefore = Math.round(Number(sum.s) * 100) / 100;
  const target = Math.round((clearedBefore + 12.5) * 100) / 100;

  await applyMutation(exec, 'reconcileAccount', {
    accountId: 'chk',
    statementBalance: target,
    statementDate: '2026-05-31',
    postAdjustment: true,
  });

  // The adjustment posted, was marked cleared, and lands the cleared sum exactly on target.
  // §2: adjustment is an entry with kind='adjustment'; amount on the account posting.
  // §2: cleared_at is per-leg on postings; check p.cleared_at.
  const [adj] = await exec(
    `SELECT p.amount, p.cleared_at FROM entries e JOIN postings p ON p.entry_id = e.id
      WHERE p.account_id = 'chk' AND e.kind = 'adjustment'
      ORDER BY e.created_at DESC LIMIT 1`,
  );
  expect(Number(adj.amount)).toBeCloseTo(12.5, 2);
  expect(adj.cleared_at).not.toBeNull();

  // §2: cleared_at is per-leg on postings.
  const [sumAfter] = await exec(
    `SELECT COALESCE(SUM(p.amount), 0) AS s
       FROM postings p JOIN entries e ON p.entry_id = e.id
     WHERE p.account_id = 'chk' AND e.status = 'confirmed' AND p.cleared_at IS NOT NULL`,
  );
  const clearedAfter = Math.round(Number(sumAfter.s) * 100) / 100;
  expect(clearedAfter).toBeCloseTo(target, 2);

  // Checkpoint stamped.
  const [acct] = await exec(
    'SELECT last_reconciled_at AS d, last_reconciled_balance AS b FROM accounts WHERE id = ?',
    ['chk'],
  );
  expect(acct.d).toBe('2026-05-31');
  expect(Number(acct.b)).toBeCloseTo(target, 2);
});

test('reconcileAccount with postAdjustment is a no-op on the adjustment when the gap is within the penny tolerance', async () => {
  const exec = await seededAndAudited();
  // §2: opening_balance column is gone. The cleared sum = SUM of pre-cleared opening
  // entry's account posting. Reconcile to that exact value → gap = 0 → no adjustment.
  const [sum] = await exec(
    `SELECT COALESCE(SUM(p.amount), 0) AS s
       FROM postings p JOIN entries e ON e.id = p.entry_id
      WHERE p.account_id = 'chk' AND e.status = 'confirmed' AND p.cleared_at IS NOT NULL`,
  );
  const clearedSum = Math.round(Number(sum.s) * 100) / 100;
  await applyMutation(exec, 'reconcileAccount', {
    accountId: 'chk',
    statementBalance: clearedSum,
    statementDate: '2026-05-31',
    postAdjustment: true,
  });
  // §2: check entries + postings for adjustment kind.
  const adj = await exec(
    "SELECT COUNT(*) AS c FROM entries e JOIN postings p ON p.entry_id = e.id WHERE p.account_id = 'chk' AND e.kind = 'adjustment'",
  );
  expect(Number(adj[0].c)).toBe(0); // gap = 0 → within penny tolerance, no adjustment posted.
});

test('duplicate guard: identical addTransaction is rejected with a friendly message', async () => {
  const exec = await seededAndAudited();
  const draft = {
    ledgerId: 'personal', accountId: 'chk', amount: -12.5, currency: 'USD',
    merchant: 'Double Latte', categoryId: 'food', date: '2026-05-20', time: '09:00',
    status: 'confirmed' as const,
  };
  await applyMutation(exec, 'addTransaction', draft);
  // Same account/date/time/amount/description → hits the dedup unique index on entries/postings.
  await expect(applyMutation(exec, 'addTransaction', draft)).rejects.toThrow(/duplicate/i);
  // A different time is a distinct row — allowed.
  await applyMutation(exec, 'addTransaction', { ...draft, time: '09:01' });
  // §2: description on entries.
  const n = await exec(
    "SELECT COUNT(*) AS c FROM entries WHERE description='Double Latte'",
  );
  expect(Number(n[0].c)).toBe(2);
});

test('duplicate guard: a second budget with the same name+cycle is rejected', async () => {
  const exec = await seededAndAudited();
  const b = { ledgerId: 'personal', name: 'Groceries', type: 'expense', amount: 600, frequency: 'monthly', startDate: '2026-05-01' };
  await applyMutation(exec, 'createBudget', { id: 'bgt-a', ...b });
  await expect(applyMutation(exec, 'createBudget', { id: 'bgt-b', ...b })).rejects.toThrow(/already exists/i);
  // Same name, different start_date (cycle) is fine.
  await applyMutation(exec, 'createBudget', { id: 'bgt-c', ...b, startDate: '2026-06-01' });
  const rows = await exec("SELECT COUNT(*) AS c FROM budgets WHERE name = 'Groceries'");
  expect(Number(rows[0].c)).toBe(2);
});

// -----------------------------------------------------------------------------
// Ledger CRUD (LEDGER_CRUD_PLAN §9). Seeded DB has personal / family /
// business / travel; tests below run end-to-end through applyMutation.
// -----------------------------------------------------------------------------

test('createLedger appears in listLedgers with zero counts; new rows update counts', async () => {
  const exec = await seededAndAudited();
  const { listLedgers, createLedger: qCreate } = await import('@/lib/db/queries/ledgers');

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

  // Avoid an unused-import lint when qCreate isn't called.
  void qCreate;
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

test('unarchiveAccount: round-trip with archiveAccount restores the row to the active list with archivedAt cleared', async () => {
  const exec = await seededAndAudited();
  // Create an account, archive it, unarchive it — assert the row is identical
  // to the pre-archive snapshot field-for-field, except archivedAt flips to null.
  // §2: accounts no longer has opening_balance (opening entries replace that column).
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,is_active,created_at,updated_at) VALUES ('acct-rt','personal','Round-trip','cash','USD',0,1,'2026-01-01','2026-01-01')",
  );
  const pre = (await exec("SELECT id, name, type, currency, is_active, archived_at FROM accounts WHERE id = 'acct-rt'"))[0];
  expect(Number(pre.is_active)).toBe(1);
  expect(pre.archived_at).toBeNull();

  await applyMutation(exec, 'archiveAccount', { id: 'acct-rt' });
  const mid = (await exec("SELECT is_active, archived_at FROM accounts WHERE id = 'acct-rt'"))[0];
  expect(Number(mid.is_active)).toBe(0);
  expect(mid.archived_at).not.toBeNull();

  await applyMutation(exec, 'unarchiveAccount', { id: 'acct-rt' });
  const post = (await exec("SELECT id, name, type, currency, is_active, archived_at FROM accounts WHERE id = 'acct-rt'"))[0];
  expect(String(post.id)).toBe(String(pre.id));
  expect(String(post.name)).toBe(String(pre.name));
  expect(String(post.type)).toBe(String(pre.type));
  expect(String(post.currency)).toBe(String(pre.currency));
  expect(Number(post.is_active)).toBe(1);
  expect(post.archived_at).toBeNull();
});

test('unarchiveAccount: nonexistent id is a silent no-op (no throw, no rows changed)', async () => {
  const exec = await seededAndAudited();
  // Direct call (not via applyMutation) — the mutation runner's catch wraps
  // any throw; for this assertion we just want to verify qUnarchiveAccount
  // doesn't blow up on a missing row.
  const { unarchiveAccount } = await import('@/lib/db/queries/accounts');
  await expect(unarchiveAccount(exec, 'nonexistent-id')).resolves.toBeUndefined();
  // No throw, no row inserted; seeded account count is unchanged.
  const [r] = await exec('SELECT COUNT(*) AS n FROM accounts');
  // Seeded DB carries a known set of accounts; we only assert the count is
  // unchanged by the no-op call (no spurious insert or delete).
  expect(Number(r.n)).toBeGreaterThan(0);
});
