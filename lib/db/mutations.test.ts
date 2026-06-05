import { test, expect } from 'bun:test';
import sqlite3InitModule from '@sqlite.org/sqlite-wasm';
import type { SqlValue } from '@sqlite.org/sqlite-wasm';
import { applySchema, migrate, SCHEMA_VERSION } from '@/lib/db/schema';
import { readMetadata } from '@/lib/db/queries/metadata';
import { seedDatabase } from '@/lib/db/seed';
import { applyMutation } from '@/lib/db/mutations';
import { listTransfers } from '@/lib/db/queries/transfers';
import { convertToBase } from '@/lib/db/queries/rates';
import type { Exec } from '@/lib/db/repo';

const initSqlite = sqlite3InitModule as unknown as (
  opts?: { print?: () => void; printErr?: () => void },
) => ReturnType<typeof sqlite3InitModule>;

async function seeded(): Promise<Exec> {
  const sqlite3 = await initSqlite({ print() {}, printErr() {} });
  const db = new sqlite3.oo1.DB(':memory:');
  const exec: Exec = async (sql, bind) => {
    const rows: Record<string, SqlValue>[] = [];
    db.exec({ sql, bind: (bind ?? []) as SqlValue[], rowMode: 'object', resultRows: rows });
    return rows;
  };
  await applySchema(exec);
  await seedDatabase(exec);
  return exec;
}

const balanceOf = async (exec: Exec, id: string) =>
  Number((await exec('SELECT current_balance AS b FROM accounts WHERE id = ?', [id]))[0].b);

test('createTransfer makes paired rows that move both balances', async () => {
  const exec = await seeded();
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
  const exec = await seeded();
  await expect(
    applyMutation(exec, 'createTransfer', { fromAccountId: 'chk', toAccountId: 'chk', fromAmount: 50, date: '2026-05-27' }),
  ).rejects.toThrow();
  await expect(
    applyMutation(exec, 'createTransfer', { fromAccountId: 'chk', toAccountId: 'sav', fromAmount: 0, date: '2026-05-27' }),
  ).rejects.toThrow();
});

test('postScheduled posts a resolvable expense template as a transaction', async () => {
  const exec = await seeded();
  // rt-spotify: $11.99 expense on "Amex Gold" → account cc.
  const ccBefore = await balanceOf(exec, 'cc');
  await applyMutation(exec, 'postScheduled', { templateId: 'rt-spotify' });
  expect(await balanceOf(exec, 'cc')).toBeCloseTo(ccBefore - 11.99, 2);
  const rows = await exec("SELECT * FROM transactions WHERE description = 'Spotify Premium'");
  expect(rows.length).toBe(1);
  expect(Number(rows[0].amount)).toBeCloseTo(-11.99, 2);
  expect(String(rows[0].kind)).toBe('expense');
});

test('postScheduled stamps the template category onto the posted transaction', async () => {
  const exec = await seeded();
  // Build a template that has a category set, then post it manually. The
  // posted row should carry that category — earlier the manual-post path
  // hard-coded category_id to NULL while autopost preserved it.
  await applyMutation(exec, 'createScheduled', {
    id: 'sch-cat', name: 'Coffee subscription', type: 'expense', frequency: 'monthly',
    dayOfMonth: 1, accountId: 'cc', amount: 12, category: 'food',
  });
  await applyMutation(exec, 'postScheduled', { templateId: 'sch-cat' });
  const [row] = await exec(
    "SELECT category_id FROM transactions WHERE source_template_id = 'sch-cat'",
  );
  expect(String(row.category_id)).toBe('food');
});

test('createHolding rejects a currency that differs from the account currency', async () => {
  const exec = await seeded();
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
  const exec = await seeded();
  // rt-rent: $1850 expense on Chase Checking (chk).
  const chkBefore = await balanceOf(exec, 'chk');
  await applyMutation(exec, 'postScheduled', { templateId: 'rt-rent' });
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(chkBefore - 1850, 2);
});

test('postScheduled splits income across its linked accounts', async () => {
  const exec = await seeded();
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
  const exec = await seeded();
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
  const exec = await seeded();
  const { categorySpend } = await import('@/lib/db/queries/categories');
  const { monthlyCashFlow } = await import('@/lib/db/queries/reports');
  const food0 = (await categorySpend(exec, 'personal'))['food'] ?? 0;
  const chk0 = await balanceOf(exec, 'chk');

  // A $200 grocery expense, then a $50 refund linked back to it (same category).
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: -200, merchant: 'Whole Foods',
    categoryId: 'food', date: '2026-05-12', kind: 'expense',
  });
  const [exp] = await exec("SELECT id FROM transactions WHERE description = 'Whole Foods'");
  const cf1 = await monthlyCashFlow(exec, 'personal', '2026-05');

  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: 50, merchant: 'Whole Foods refund',
    categoryId: 'food', date: '2026-05-20', kind: 'refund', refundedTransactionId: String(exp.id),
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
  const exec = await seeded();
  const { getRefundsFor } = await import('@/lib/db/queries/transactions');
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: -200, merchant: 'TV',
    categoryId: 'food', date: '2026-05-12', kind: 'expense',
  });
  const [exp] = await exec("SELECT id FROM transactions WHERE description = 'TV'");
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: 80, merchant: 'TV partial refund',
    categoryId: 'food', date: '2026-05-15', kind: 'refund', refundedTransactionId: String(exp.id),
  });
  expect((await getRefundsFor(exec, String(exp.id))).length).toBe(1);

  await applyMutation(exec, 'deleteTransaction', { id: String(exp.id) });
  const [ref] = await exec("SELECT refunded_transaction_id FROM transactions WHERE description = 'TV partial refund'");
  expect(ref).toBeTruthy(); // refund row still exists
  expect(ref.refunded_transaction_id).toBeNull(); // link nulled, not cascaded
});

test('converting an income to a refund reclassifies it: nets category spend, drops from income, balance unchanged', async () => {
  const exec = await seeded();
  const { categorySpend } = await import('@/lib/db/queries/categories');
  const { monthlyCashFlow } = await import('@/lib/db/queries/reports');

  // A $200 grocery expense to offset against.
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: -200, merchant: 'Whole Foods',
    categoryId: 'food', date: '2026-05-12', kind: 'expense',
  });
  const [exp] = await exec("SELECT id FROM transactions WHERE description = 'Whole Foods'");
  const food1 = (await categorySpend(exec, 'personal'))['food'] ?? 0;

  // A $50 income (mis-recorded; really money back on the groceries).
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: 50, merchant: 'Mystery deposit',
    categoryId: 'misc', date: '2026-05-20', kind: 'income',
  });
  const [inc] = await exec("SELECT id FROM transactions WHERE description = 'Mystery deposit'");
  const balAfterIncome = await balanceOf(exec, 'chk');
  const cfIncome = await monthlyCashFlow(exec, 'personal', '2026-05');

  // Convert it: kind→refund, link to the expense, adopt its category.
  await applyMutation(exec, 'updateTransaction', {
    id: String(inc.id),
    patch: { kind: 'refund', refundedTransactionId: String(exp.id), category: 'food' },
  });

  const [row] = await exec("SELECT kind, refunded_transaction_id AS r, category_id AS c FROM transactions WHERE id = ?", [String(inc.id)]);
  expect(String(row.kind)).toBe('refund');
  expect(String(row.r)).toBe(String(exp.id));
  expect(String(row.c)).toBe('food');

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
  const exec = await seeded();
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
  const exec = await seeded();
  await expect(applyMutation(exec, 'createCategory', { ledgerId: 'personal', name: '  ' })).rejects.toThrow();
});

test('updateScheduledSplit updates the nth split by sort order', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'updateScheduledSplit', { templateId: 'rt-salary', index: 1, pct: 30 });
  const rows = await exec("SELECT amount_pct FROM scheduled_splits WHERE template_id = 'rt-salary' ORDER BY sort_order");
  expect(Number(rows[0].amount_pct)).toBe(60); // unchanged
  expect(Number(rows[1].amount_pct)).toBe(30); // updated
});

test('createTag + setTransactionTags replace the tag set', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'createTag', { id: 'tag-new', ledgerId: 'personal', name: 'Trip' });
  await applyMutation(exec, 'setTransactionTags', { id: 't02', tagIds: ['tag-new', 'tag-business'] });
  const rows = await exec("SELECT tag_id FROM transaction_tags WHERE transaction_id = 't02' ORDER BY tag_id");
  expect(rows.map((r) => String(r.tag_id))).toEqual(['tag-business', 'tag-new']);
  // Replacing with a smaller set removes the others.
  await applyMutation(exec, 'setTransactionTags', { id: 't02', tagIds: ['tag-new'] });
  const after = await exec("SELECT tag_id FROM transaction_tags WHERE transaction_id = 't02'");
  expect(after.map((r) => String(r.tag_id))).toEqual(['tag-new']);
});

test('seeded tag assignments are projected onto transactions', async () => {
  const exec = await seeded();
  const map = await exec("SELECT tag_id FROM transaction_tags WHERE transaction_id = 't03' ORDER BY tag_id");
  expect(map.length).toBe(2);
});

test('createTransfer converts the incoming leg across currencies', async () => {
  const exec = await seeded();
  // Add a EUR account in the personal (USD) ledger.
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,is_active,created_at,updated_at) VALUES ('eurw','personal','EUR Wallet','cash','EUR',0,1,'2026-05-26','2026-05-26')",
  );
  await applyMutation(exec, 'createTransfer', { fromAccountId: 'chk', toAccountId: 'eurw', fromAmount: 100, date: '2026-05-24' });
  // chk is USD; 100 USD → EUR at rate(USD)/rate(EUR) = 1 / 1.088 (USD is the hub).
  const eur = Number((await exec("SELECT current_balance AS b FROM accounts WHERE id = 'eurw'"))[0].b);
  expect(eur).toBeCloseTo(100 * (1 / 1.088), 2);
  const tg = await exec('SELECT exchange_rate AS r FROM transfer_groups ORDER BY created_at DESC LIMIT 1');
  expect(Number(tg[0].r)).toBeCloseTo(1 / 1.088, 4);
  // listTransfers surfaces both legs' native amounts + currencies for the UI.
  const [t] = await listTransfers(exec, 'personal');
  expect(t.fromCurrency).toBe('USD');
  expect(t.toCurrency).toBe('EUR');
  expect(t.amount).toBeCloseTo(100, 2); // sent (USD, native)
  expect(t.toAmount).toBeCloseTo(100 * (1 / 1.088), 2); // received (EUR, native)
});

test('addTransaction on a foreign-currency account: native balance, ledger-base amount_base', async () => {
  const exec = await seeded();
  // A JPY account inside the personal (USD) ledger — account currency ≠ ledger base.
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,opening_balance,is_active,created_at,updated_at) VALUES ('jpyw','personal','JPY Wallet','cash','JPY',0,0,1,'2026-05-26','2026-05-26')",
  );
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'jpyw', amount: -10000, currency: 'JPY',
    merchant: 'Konbini', date: '2026-05-13', status: 'confirmed',
  });
  // The balance moves in the ACCOUNT's currency (¥), un-converted.
  expect(await balanceOf(exec, 'jpyw')).toBeCloseTo(-10000, 2);
  const [row] = await exec("SELECT amount, amount_base, currency FROM transactions WHERE account_id='jpyw'");
  expect(Number(row.amount)).toBeCloseTo(-10000, 2); // native (¥)
  expect(String(row.currency)).toBe('JPY');
  // amount_base is the LEDGER base (USD) figure for cross-account reporting.
  const expected = await convertToBase(exec, -10000, 'JPY', 'USD', '2026-05-13');
  expect(Number(row.amount_base)).toBeCloseTo(expected.amountBase, 2);
  // ¥ → $ shrinks the magnitude ~150×, so base ≠ native (proves they're distinct).
  expect(Math.abs(Number(row.amount_base))).toBeLessThan(Math.abs(Number(row.amount)));
});

test('recompute keeps a foreign-currency account balance in its own currency', async () => {
  const exec = await seeded();
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,opening_balance,is_active,created_at,updated_at) VALUES ('jpyw','personal','JPY Wallet','cash','JPY',0,0,1,'2026-05-26','2026-05-26')",
  );
  const add = (amount: number, date: string) =>
    applyMutation(exec, 'addTransaction', {
      ledgerId: 'personal', accountId: 'jpyw', amount, currency: 'JPY', merchant: 'Konbini', date, status: 'confirmed',
    });
  await add(-10000, '2026-05-13');
  await add(-5000, '2026-05-14');
  expect(await balanceOf(exec, 'jpyw')).toBeCloseTo(-15000, 2); // ¥, summed natively
  // Cancelling routes through recomputeAccount — it must reverse in ¥, not USD.
  const [{ id }] = await exec("SELECT id FROM transactions WHERE account_id='jpyw' AND amount=-5000");
  await applyMutation(exec, 'deleteTransaction', { id: String(id) });
  expect(await balanceOf(exec, 'jpyw')).toBeCloseTo(-10000, 2);
});

test('editing a foreign-currency transaction amount reconverts amount_base to ledger base', async () => {
  const exec = await seeded();
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,opening_balance,is_active,created_at,updated_at) VALUES ('jpyw','personal','JPY Wallet','cash','JPY',0,0,1,'2026-05-26','2026-05-26')",
  );
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'jpyw', amount: -10000, currency: 'JPY', merchant: 'Konbini', date: '2026-05-13', status: 'confirmed',
  });
  const [{ id }] = await exec("SELECT id FROM transactions WHERE account_id='jpyw'");
  await applyMutation(exec, 'updateTransaction', { id: String(id), patch: { amount: -20000 } });
  // The balance reflects the new ¥ amount (native), summed in the account currency.
  expect(await balanceOf(exec, 'jpyw')).toBeCloseTo(-20000, 2);
  const [row] = await exec('SELECT amount, amount_base FROM transactions WHERE id = ?', [String(id)]);
  expect(Number(row.amount)).toBeCloseTo(-20000, 2); // native (¥)
  // amount_base is re-derived in USD (ledger base), not left as the native ¥ figure.
  const expected = await convertToBase(exec, -20000, 'JPY', 'USD', '2026-05-13');
  expect(Number(row.amount_base)).toBeCloseTo(expected.amountBase, 2);
  expect(Math.abs(Number(row.amount_base))).toBeLessThan(Math.abs(Number(row.amount)));
});

test('seed records each account opening balance and balances reconcile', async () => {
  const exec = await seeded();
  const [a] = await exec("SELECT opening_balance, current_balance FROM accounts WHERE id = 'cc'");
  // Only confirmed rows move the balance; pending (unconfirmed) ones are excluded.
  const sum = Number(
    (await exec("SELECT COALESCE(SUM(amount_base),0) AS s FROM transactions WHERE account_id='cc' AND status='confirmed'"))[0].s,
  );
  expect(Number(a.current_balance)).toBeCloseTo(Number(a.opening_balance) + sum, 2);
  expect(Number(a.current_balance)).toBeCloseTo(-842.18, 2);
});

test('editing a transaction amount recomputes the account balance', async () => {
  const exec = await seeded();
  const before = await balanceOf(exec, 'cc'); // -842.18
  await applyMutation(exec, 'updateTransaction', { id: 't01', patch: { amount: -100 } });
  // t01 was -6.75 → -100, so cc drops by the 93.25 difference.
  expect(await balanceOf(exec, 'cc')).toBeCloseTo(before - (100 - 6.75), 2);
});

test('cancelling a transaction reverses its effect on the balance', async () => {
  const exec = await seeded();
  const before = await balanceOf(exec, 'cc');
  await applyMutation(exec, 'deleteTransaction', { id: 't01' }); // -6.75 expense removed
  expect(await balanceOf(exec, 'cc')).toBeCloseTo(before + 6.75, 2);
});

test('migrate stamps the schema version in db_metadata', async () => {
  const exec = await seeded();
  await migrate(exec, { fresh: true });
  const meta = await readMetadata(exec);
  expect(meta).not.toBeNull();
  expect(meta!.schemaVersion).toBe(SCHEMA_VERSION);
  expect(meta!.appName).toBe('finch');
});

test('schema shape: budgets no longer carries tag_ids; new indexes present', async () => {
  const exec = await seeded();
  const budgetCols = (await exec('PRAGMA table_info(budgets)')).map((r) => String(r.name));
  expect(budgetCols).not.toContain('tag_ids');

  const indexNames = async (table: string) =>
    (await exec(`PRAGMA index_list(${table})`)).map((r) => String(r.name));
  expect(await indexNames('exchange_rates')).toContain('idx_rate_currency_date');
  expect(await indexNames('exchange_rates')).not.toContain('idx_rate_currency');
  expect(await indexNames('transactions')).toContain('idx_txn_account_status');
});


test('deleteCategory uncategorizes its transactions', async () => {
  const exec = await seeded();
  const before = Number((await exec("SELECT COUNT(*) AS n FROM categories WHERE id = 'food'"))[0].n);
  expect(before).toBe(1);
  const tagged = Number((await exec("SELECT COUNT(*) AS n FROM transactions WHERE category_id = 'food'"))[0].n);
  expect(tagged).toBeGreaterThan(0);
  await applyMutation(exec, 'deleteCategory', { id: 'food' });
  expect(Number((await exec("SELECT COUNT(*) AS n FROM categories WHERE id = 'food'"))[0].n)).toBe(0);
  // FK is SET NULL: those transactions survive but become uncategorized.
  expect(Number((await exec("SELECT COUNT(*) AS n FROM transactions WHERE category_id = 'food'"))[0].n)).toBe(0);
});

test('deleteCategory: scheduled_templates.category_id is SET NULL (used to be RESTRICT)', async () => {
  const exec = await seeded();
  // Hand-build a schedule linked to 'food' — bypassing the higher-level mutation
  // so the test focuses on the FK clause itself, not the createScheduled path.
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
  const exec = await seeded();
  expect(Number((await exec("SELECT COUNT(*) AS n FROM transaction_tags WHERE tag_id = 'tag-business'"))[0].n)).toBeGreaterThan(0);
  await applyMutation(exec, 'deleteTag', { id: 'tag-business' });
  expect(Number((await exec("SELECT COUNT(*) AS n FROM tags WHERE id = 'tag-business'"))[0].n)).toBe(0);
  expect(Number((await exec("SELECT COUNT(*) AS n FROM transaction_tags WHERE tag_id = 'tag-business'"))[0].n)).toBe(0);
});

test('deleteScheduled removes the template and cascades its splits', async () => {
  const exec = await seeded();
  expect(Number((await exec("SELECT COUNT(*) AS n FROM scheduled_splits WHERE template_id = 'rt-salary'"))[0].n)).toBeGreaterThan(0);
  await applyMutation(exec, 'deleteScheduled', { id: 'rt-salary' });
  expect(Number((await exec("SELECT COUNT(*) AS n FROM scheduled_templates WHERE id = 'rt-salary'"))[0].n)).toBe(0);
  expect(Number((await exec("SELECT COUNT(*) AS n FROM scheduled_splits WHERE template_id = 'rt-salary'"))[0].n)).toBe(0);
});

test('deleteCounterparty removes the merchant', async () => {
  const exec = await seeded();
  const cpId = String((await exec("SELECT id FROM counterparties WHERE ledger_id = 'personal' LIMIT 1"))[0].id);
  await applyMutation(exec, 'deleteCounterparty', { id: cpId });
  expect(Number((await exec('SELECT COUNT(*) AS n FROM counterparties WHERE id = ?', [cpId]))[0].n)).toBe(0);
});

test('deleteTransfer removes both legs and restores balances', async () => {
  const exec = await seeded();
  const chk0 = await balanceOf(exec, 'chk');
  const sav0 = await balanceOf(exec, 'sav');
  await applyMutation(exec, 'createTransfer', { fromAccountId: 'chk', toAccountId: 'sav', fromAmount: 200, date: '2026-05-27' });
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(chk0 - 200, 2);
  const groupId = String((await exec("SELECT transfer_group_id AS g FROM transactions WHERE transfer_group_id IS NOT NULL LIMIT 1"))[0].g);
  await applyMutation(exec, 'deleteTransfer', { id: groupId });
  expect(Number((await exec('SELECT COUNT(*) AS n FROM transactions WHERE transfer_group_id = ?', [groupId]))[0].n)).toBe(0);
  expect(Number((await exec('SELECT COUNT(*) AS n FROM transfer_groups WHERE id = ?', [groupId]))[0].n)).toBe(0);
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(chk0, 2);
  expect(await balanceOf(exec, 'sav')).toBeCloseTo(sav0, 2);
});

test('updateCategory edits name/type/icon/color', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'updateCategory', { id: 'food', patch: { name: 'Food & Drink', type: 'income', icon: 'coins', color: '#8085dc' } });
  const [c] = await exec("SELECT name, kind, icon, color FROM categories WHERE id = 'food'");
  expect(String(c.name)).toBe('Food & Drink');
  expect(String(c.kind)).toBe('income');
  expect(String(c.icon)).toBe('coins');
  expect(String(c.color)).toBe('#8085dc');
});

test('createCategory persists icon + color, and listCategories returns color', async () => {
  const exec = await seeded();
  const { listCategories } = await import('@/lib/db/queries/categories');
  await applyMutation(exec, 'createCategory', { ledgerId: 'personal', name: 'Travel', type: 'expense', icon: 'car', color: '#00a6ae' });
  const cat = (await listCategories(exec, 'personal')).find((c) => c.name === 'Travel')!;
  expect(cat.icon).toBe('car');
  expect(cat.color).toBe('#00a6ae');
  // Seeded categories keep their JSON color too.
  expect((await listCategories(exec, 'personal')).find((c) => c.id === 'food')!.color).toBe('#d16b7a');
});

test('updateTag edits fields', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'updateTag', { id: 'tag-business', patch: { name: 'Work', color: '300' } });
  const [tag] = await exec("SELECT name, color FROM tags WHERE id = 'tag-business'");
  expect(String(tag.name)).toBe('Work');
  expect(String(tag.color)).toBe('300');
});

test('updateScheduled and updateCounterparty edit fields', async () => {
  const exec = await seeded();
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
  const exec = await seeded();
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
  const exec = await seeded();
  const chk0 = await balanceOf(exec, 'chk');
  const sav0 = await balanceOf(exec, 'sav');
  await applyMutation(exec, 'createTransfer', { fromAccountId: 'chk', toAccountId: 'sav', fromAmount: 200, date: '2026-05-27', note: 'a' });
  const groupId = String((await exec("SELECT transfer_group_id AS g FROM transactions WHERE transfer_group_id IS NOT NULL LIMIT 1"))[0].g);
  await applyMutation(exec, 'updateTransfer', { id: groupId, patch: { fromAmount: 350, date: '2026-05-28', note: 'updated' } });
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(chk0 - 350, 2);
  expect(await balanceOf(exec, 'sav')).toBeCloseTo(sav0 + 350, 2);
  const legs = await exec('SELECT date, notes FROM transactions WHERE transfer_group_id = ?', [groupId]);
  expect(legs.every((l) => l.date === '2026-05-28' && l.notes === 'updated')).toBe(true);
});

test('createTransfer with explicit toAmount pins both sides + sets the rate', async () => {
  const exec = await seeded();
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,is_active,created_at,updated_at) VALUES ('eurw2','personal','EUR Wallet 2','cash','EUR',0,1,'2026-05-26','2026-05-26')",
  );
  // chk is USD; user types: sent $100, received €90 (bank's actual conversion, including fees).
  await applyMutation(exec, 'createTransfer', { fromAccountId: 'chk', toAccountId: 'eurw2', fromAmount: 100, toAmount: 90, date: '2026-05-24' });
  const eur = Number((await exec("SELECT current_balance AS b FROM accounts WHERE id = 'eurw2'"))[0].b);
  expect(eur).toBeCloseTo(90, 2);
  const tg = await exec('SELECT exchange_rate AS r FROM transfer_groups ORDER BY created_at DESC LIMIT 1');
  expect(Number(tg[0].r)).toBeCloseTo(0.9, 4);
});

test('updateTransfer with only fromAmount preserves the FX ratio on cross-currency', async () => {
  const exec = await seeded();
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,is_active,created_at,updated_at) VALUES ('eurw3','personal','EUR Wallet 3','cash','EUR',0,1,'2026-05-26','2026-05-26')",
  );
  // Create at $100 → €91 (rate 0.91), then double the from-leg.
  await applyMutation(exec, 'createTransfer', { fromAccountId: 'chk', toAccountId: 'eurw3', fromAmount: 100, toAmount: 91, date: '2026-05-24' });
  const groupId = String((await exec("SELECT id FROM transfer_groups ORDER BY created_at DESC LIMIT 1"))[0].id);
  await applyMutation(exec, 'updateTransfer', { id: groupId, patch: { fromAmount: 200 } });
  const eur = Number((await exec("SELECT current_balance AS b FROM accounts WHERE id = 'eurw3'"))[0].b);
  expect(eur).toBeCloseTo(182, 2); // 91 × (200/100)
});

test('updateTransfer with both amounts rewrites the rate on cross-currency', async () => {
  const exec = await seeded();
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,is_active,created_at,updated_at) VALUES ('eurw4','personal','EUR Wallet 4','cash','EUR',0,1,'2026-05-26','2026-05-26')",
  );
  // Initial: $100 → €91 (mid-rate). User corrects to $100 → €89 (bank's actual).
  await applyMutation(exec, 'createTransfer', { fromAccountId: 'chk', toAccountId: 'eurw4', fromAmount: 100, toAmount: 91, date: '2026-05-24' });
  const groupId = String((await exec("SELECT id FROM transfer_groups ORDER BY created_at DESC LIMIT 1"))[0].id);
  await applyMutation(exec, 'updateTransfer', { id: groupId, patch: { fromAmount: 100, toAmount: 89 } });
  const eur = Number((await exec("SELECT current_balance AS b FROM accounts WHERE id = 'eurw4'"))[0].b);
  expect(eur).toBeCloseTo(89, 2);
  const tg = await exec('SELECT exchange_rate AS r FROM transfer_groups WHERE id = ?', [groupId]);
  expect(Number(tg[0].r)).toBeCloseTo(0.89, 4);
});

test('createCounterparty inserts an unverified merchant', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'createCounterparty', { id: 'cp-new', ledgerId: 'personal', name: 'Starbucks' });
  const { listCounterparties } = await import('@/lib/db/queries/counterparties');
  const cp = (await listCounterparties(exec, 'personal')).find((c) => c.id === 'cp-new')!;
  expect(cp.name).toBe('Starbucks');
  expect(cp.verified).toBe(false);
  await expect(applyMutation(exec, 'createCounterparty', { name: '  ' })).rejects.toThrow();
});

test('createScheduled inserts a template that lists and posts', async () => {
  const exec = await seeded();
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
  const exec = await seeded();
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
  const exec = await seeded();
  const before = await balanceOf(exec, 'chk'); // 4218.50 seed
  await applyMutation(exec, 'adjustAccountBalance', { accountId: 'chk', targetBalance: 5000, note: 'reconcile' });
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(5000, 2);
  const [adj] = await exec("SELECT amount_base, kind, description, notes FROM transactions WHERE account_id = 'chk' ORDER BY created_at DESC LIMIT 1");
  expect(String(adj.kind)).toBe('adjustment');
  expect(Number(adj.amount_base)).toBeCloseTo(5000 - before, 2);
  expect(String(adj.description)).toBe('Balance adjustment');
  expect(String(adj.notes)).toBe('reconcile');
});

test('adjustments are excluded from category spend and cash flow', async () => {
  const exec = await seeded();
  const { categorySpend } = await import('@/lib/db/queries/categories');
  const { monthlyCashFlow } = await import('@/lib/db/queries/reports');
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
  const exec = await seeded();
  const before = await balanceOf(exec, 'chk');
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: 250, merchant: 'Side gig',
    categoryId: null, date: '2026-05-29', status: 'confirmed',
  });
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(before + 250, 2);
});

test('setExchangeRate upserts on (date, currency); deleteExchangeRate removes it', async () => {
  const exec = await seeded();
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
  const exec = await seeded();
  await expect(applyMutation(exec, 'setExchangeRate', { date: '2026-06-01', currency: '', rate: 0.01 })).rejects.toThrow(/currency/i);
  await expect(applyMutation(exec, 'setExchangeRate', { date: '2026-06-01', currency: 'JPY', rate: 0 })).rejects.toThrow(/rate/i);
  await expect(applyMutation(exec, 'setExchangeRate', { date: '2026/06/01', currency: 'JPY', rate: 0.01 })).rejects.toThrow(/date/i);
});

test('newly set rate is picked up by convertToBase for the same date', async () => {
  const exec = await seeded();
  const { convertToBase } = await import('@/lib/db/queries/rates');
  await applyMutation(exec, 'setExchangeRate', { date: '2026-06-15', currency: 'JPY', rate: 0.01, source: 'manual' });
  // JPY → USD on that date: rate = rate(JPY) / rate(USD) = 0.01 / 1 = 0.01 (USD is the hub).
  const conv = await convertToBase(exec, 100, 'JPY', 'USD', '2026-06-15');
  expect(conv.rate).toBeCloseTo(0.01, 6);
  expect(conv.amountBase).toBeCloseTo(1.0, 4);
});

test('setTransactionSplits validates sum + min-2-rows; categorySpend uses splits', async () => {
  const exec = await seeded();
  // Pick a confirmed expense from the seed so its category is known.
  const [parent] = await exec(
    "SELECT id, amount, amount_base, category_id FROM transactions WHERE ledger_id = 'personal' AND kind = 'expense' AND status = 'confirmed' LIMIT 1",
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
  // Both splits' targets get a positive contribution (magnitude).
  expect(after.food).toBeGreaterThan(0);
  expect(after.trans).toBeGreaterThan(0);
  // Sanity: per-row stored amount_base is derived from the parent's locked rate.
  const splitRows = await exec(
    'SELECT category_id, amount, amount_base FROM transaction_splits WHERE transaction_id = ? ORDER BY sort_order',
    [txId],
  );
  expect(splitRows).toHaveLength(2);
  const sumBase = splitRows.reduce((s, r) => s + Number(r.amount_base), 0);
  expect(sumBase).toBeCloseTo(Number(parent.amount_base), 2);

  // Clearing splits restores the parent's category.
  await applyMutation(exec, 'setTransactionSplits', { id: txId, splits: [] });
  const cleared = await exec('SELECT COUNT(*) AS n FROM transaction_splits WHERE transaction_id = ?', [txId]);
  expect(Number(cleared[0].n)).toBe(0);
  const restored = await categorySpend(exec, 'personal');
  // The original category should once again include this tx.
  expect(restored[originalCat]).toBeGreaterThan(0);
});

test('createAccountGroup / updateAccountGroup / deleteAccountGroup wire end-to-end', async () => {
  const exec = await seeded();
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
  const exec = await seeded();
  await expect(applyMutation(exec, 'createAccountGroup', { name: '   ' })).rejects.toThrow(/name/i);
});

test('pending transactions are excluded from the balance until confirmed', async () => {
  const exec = await seeded();
  const b0 = await balanceOf(exec, 'chk');
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: -50, merchant: 'Hold', date: '2026-05-28', status: 'pending',
  });
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(b0, 2); // pending → no balance change
  const [row] = await exec("SELECT id FROM transactions WHERE description = 'Hold' AND status = 'pending'");
  await applyMutation(exec, 'confirmTransaction', { id: String(row.id) });
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(b0 - 50, 2); // confirming pulls it in
});

test('generateDueScheduled materializes due occurrences, idempotently', async () => {
  const exec = await seeded();
  const cc0 = await balanceOf(exec, 'cc');
  const chk0 = await balanceOf(exec, 'chk');
  const sav0 = await balanceOf(exec, 'sav');

  await applyMutation(exec, 'generateDueScheduled', { today: '2026-05-30' });
  // rt-spotify (cc, day 22), rt-icloud (cc, day 8), rt-rent (chk, day 1) →
  // 3 pending expense rows. rt-sweep (chk → sav, day 28) → 1 confirmed
  // transfer = 2 transaction rows (from + to legs). coned/salary are
  // still skipped (variable / split).
  const gen = await exec(
    "SELECT id, status, source_template_id AS t FROM transactions WHERE source_template_id IS NOT NULL ORDER BY date",
  );
  expect(gen.length).toBe(5);
  const pending = gen.filter((r) => String(r.status) === 'pending');
  const confirmed = gen.filter((r) => String(r.status) === 'confirmed');
  expect(pending.length).toBe(3); // expense + income legs stay pending
  expect(confirmed.length).toBe(2); // transfer fires both legs as confirmed
  expect(confirmed.every((r) => String(r.t) === 'rt-sweep')).toBe(true);
  // Pending didn't touch cc; the confirmed sweep moved chk and sav.
  expect(await balanceOf(exec, 'cc')).toBeCloseTo(cc0, 2);
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(chk0 - 800, 2);
  expect(await balanceOf(exec, 'sav')).toBeCloseTo(sav0 + 800, 2);

  // Idempotent: a second run adds nothing (dedup via source_template_id + date).
  await applyMutation(exec, 'generateDueScheduled', { today: '2026-05-30' });
  const again = await exec("SELECT id FROM transactions WHERE source_template_id IS NOT NULL");
  expect(again.length).toBe(5);

  // Confirming the Spotify pending (11.99 expense) pulls it into cc's balance.
  const spotify = gen.find((r) => String(r.t) === 'rt-spotify')!;
  await applyMutation(exec, 'confirmTransaction', { id: String(spotify.id) });
  expect(await balanceOf(exec, 'cc')).toBeCloseTo(cc0 - 11.99, 2);
});

test('generateDueScheduled: recurring transfer caps at installment_total like other templates', async () => {
  const exec = await seeded();
  // 3-payment recurring transfer; after a year only 3 occurrences should fire
  // (Jan, Feb, Mar 2026), each producing two legs = 6 transaction rows total.
  await applyMutation(exec, 'createScheduled', {
    id: 'sch-recur-xfer', name: 'Auto-savings', type: 'transfer',
    frequency: 'monthly', dayOfMonth: 5, accountId: 'sav', fromAccountId: 'chk',
    amount: 200, installmentTotal: 3, autoPost: true, startDate: '2026-01-01',
  });
  await applyMutation(exec, 'generateDueScheduled', { today: '2026-12-31' });
  const legs = await exec(
    "SELECT id FROM transactions WHERE source_template_id = 'sch-recur-xfer'",
  );
  expect(legs.length).toBe(6); // 3 dates × 2 legs
  const tg = await exec(
    "SELECT DISTINCT transfer_group_id FROM transactions WHERE source_template_id = 'sch-recur-xfer'",
  );
  expect(tg.length).toBe(3); // three distinct transfer_groups
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
  const exec = await seeded();
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
  const exec = await seeded();
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
  const exec = await seeded();
  await applyMutation(exec, 'createScheduled', {
    id: 'sch-plan', name: 'Furniture 0%', type: 'expense', frequency: 'monthly',
    dayOfMonth: 1, accountId: 'chk', amount: 200, installmentTotal: 12,
    autoPost: true, startDate: '2026-01-01',
  });
  // generateDueScheduled creates pending rows — they shouldn't count toward
  // "paid" (the user hasn't confirmed them yet).
  await applyMutation(exec, 'generateDueScheduled', { today: '2026-03-15' });
  const pendingBefore = await exec(
    "SELECT id FROM transactions WHERE source_template_id = 'sch-plan' AND status = 'pending'",
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
  const exec = await seeded();
  // 3-month plan starting Jan 2026, daily would over-shoot, monthly is right.
  await applyMutation(exec, 'createScheduled', {
    id: 'sch-cap', name: 'Three-month plan', type: 'expense', frequency: 'monthly',
    dayOfMonth: 1, accountId: 'chk', amount: 100, installmentTotal: 3,
    autoPost: true, startDate: '2026-01-01',
  });
  // After a year, only 3 occurrences should exist (Jan, Feb, Mar) — the cap
  // wins even though monthly occurrences would otherwise have generated 12.
  await applyMutation(exec, 'generateDueScheduled', { today: '2026-12-31' });
  const gen = await exec(
    "SELECT id FROM transactions WHERE source_template_id = 'sch-cap'",
  );
  expect(gen.length).toBe(3);
});

// ---------------------------------------------------------------------------
// changeLedgerBase — rewrites locked amount_base figures + re-stamps the
// account opening cost basis. Pre-PR-66 these branches were untested.
// ---------------------------------------------------------------------------

test('changeLedgerBase re-stamps opening_balance_base for a foreign-currency account', async () => {
  const exec = await seeded();
  // Stand up a JPY account in the (USD) personal ledger with a known opening
  // balance + creation date. The seed's exchange_rates table has a JPY row on
  // 2026-05-24 (0.0065 USD per JPY).
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,opening_balance,opening_balance_base,is_active,created_at,updated_at) " +
    "VALUES ('jpyw','personal','JPY Wallet','cash','JPY',100000,100000,650,1,'2026-05-24','2026-05-24')",
  );
  // Flip the base to SGD. JPY → SGD via the USD pivot at the same creation
  // date should produce a new opening_balance_base that's roughly
  // 100000 * 0.0065 / 0.7457 ≈ 871.7 SGD.
  await applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'SGD' });
  const [a] = await exec("SELECT opening_balance_base FROM accounts WHERE id = 'jpyw'");
  expect(Number(a.opening_balance_base)).toBeCloseTo(871.7, 0); // ±1 SGD tolerance
  const [l] = await exec("SELECT base_currency FROM ledgers WHERE id = 'personal'");
  expect(String(l.base_currency)).toBe('SGD');
});

test('changeLedgerBase rewrites transaction_splits.amount_base under the new base', async () => {
  const exec = await seeded();
  // Pick any seed transaction with a known amount; attach two splits whose
  // amount_base values are written under the current (USD) base.
  const [tx] = await exec("SELECT id, amount FROM transactions WHERE ledger_id = 'personal' LIMIT 1");
  const txId = String(tx.id);
  const amt = Number(tx.amount);
  await applyMutation(exec, 'setTransactionSplits', {
    id: txId,
    splits: [
      { categoryId: 'food', amount: amt / 2 },
      { categoryId: 'food', amount: amt / 2 },
    ],
  });
  const before = await exec(
    'SELECT amount_base FROM transaction_splits WHERE transaction_id = ? ORDER BY sort_order',
    [txId],
  );
  // Flip the base to SGD and confirm the split's amount_base rewrote to match
  // the new base's conversion. We don't pin an exact value — just verify the
  // figure changed (USD == base today means amount == amount_base; under SGD
  // the conversion is no longer the identity for a USD-denominated row).
  await applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'SGD' });
  const after = await exec(
    'SELECT amount_base FROM transaction_splits WHERE transaction_id = ? ORDER BY sort_order',
    [txId],
  );
  expect(after.length).toBe(before.length);
  for (let i = 0; i < after.length; i++) {
    expect(Number(after[i].amount_base)).not.toBeCloseTo(Number(before[i].amount_base), 4);
  }
});

test('changeLedgerBase same-base call is a no-op (no row changes)', async () => {
  const exec = await seeded();
  const before = await exec("SELECT id, amount_base FROM transactions WHERE ledger_id = 'personal' ORDER BY id");
  await applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'USD' });
  const after = await exec("SELECT id, amount_base FROM transactions WHERE ledger_id = 'personal' ORDER BY id");
  expect(after.length).toBe(before.length);
  for (let i = 0; i < after.length; i++) {
    expect(Number(after[i].amount_base)).toBeCloseTo(Number(before[i].amount_base), 6);
  }
});

test('bulkRecategorize moves N rows in one statement; categorySpend shifts accordingly', async () => {
  const exec = await seeded();
  const { categorySpend } = await import('@/lib/db/queries/categories');
  // Pick three confirmed expenses currently tagged 'food'.
  const ids = (
    await exec(
      "SELECT id FROM transactions WHERE ledger_id = 'personal' AND category_id = 'food' AND status = 'confirmed' ORDER BY date DESC LIMIT 3",
    )
  ).map((r) => String(r.id));
  expect(ids.length).toBe(3);
  const movedSum = (
    await exec(
      `SELECT SUM(amount_base) AS s FROM transactions WHERE id IN (${ids.map(() => '?').join(',')})`,
      ids,
    )
  )[0];
  const moved = Math.abs(Number(movedSum.s));
  const before = await categorySpend(exec, 'personal');

  await applyMutation(exec, 'bulkRecategorize', { ids, categoryId: 'misc' });
  const after = await categorySpend(exec, 'personal');

  // Each moved row now has category 'misc'; no row keeps the old food link.
  const stillFood = await exec(
    `SELECT COUNT(*) AS c FROM transactions WHERE id IN (${ids.map(() => '?').join(',')}) AND category_id = 'food'`,
    ids,
  );
  expect(Number(stillFood[0].c)).toBe(0);
  expect((after['food'] ?? 0)).toBeCloseTo((before['food'] ?? 0) - moved, 2);
  expect((after['misc'] ?? 0)).toBeCloseTo((before['misc'] ?? 0) + moved, 2);
});

test('bulkRecategorize: empty ids is a no-op; null categoryId clears the link', async () => {
  const exec = await seeded();
  // Empty: nothing changes.
  const beforeCount = Number(
    (await exec("SELECT COUNT(*) AS c FROM transactions WHERE category_id = 'food'"))[0].c,
  );
  await applyMutation(exec, 'bulkRecategorize', { ids: [], categoryId: 'misc' });
  expect(
    Number((await exec("SELECT COUNT(*) AS c FROM transactions WHERE category_id = 'food'"))[0].c),
  ).toBe(beforeCount);

  // Null: clear the category on a single row.
  const [row] = await exec("SELECT id FROM transactions WHERE category_id = 'food' LIMIT 1");
  const id = String(row.id);
  await applyMutation(exec, 'bulkRecategorize', { ids: [id], categoryId: null });
  const [after] = await exec('SELECT category_id AS c FROM transactions WHERE id = ?', [id]);
  expect(after.c).toBeNull();
});
