import { test, expect } from 'bun:test';
import { migrate, SCHEMA_VERSION } from './core/schema';
import { readMetadata } from '@/lib/db/queries/metadata';
import { applyMutation } from '@/lib/db/mutate';
import { listTransfers } from '@/lib/db/queries/transfers';
import { listBudgets } from '@/lib/db/queries/budgets';
import { seededAndAudited } from './core/test-utils';
import type { Exec } from './core/repo';
import { I18nError } from '@/lib/i18n-error';
import type { ActionName } from './domain/_args';

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

test('createTransfer forwards sourceTemplateId/occurrenceDate to the persisted entry', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'createTransfer', {
    fromAccountId: 'chk',
    toAccountId: 'sav',
    fromAmount: 200,
    date: '2026-05-27',
    sourceTemplateId: 's1',
    occurrenceDate: '2026-05-15',
  });

  const transfers = await listTransfers(exec, 'personal');
  const [row] = await exec(
    'SELECT source_template_id, occurrence_date FROM entries WHERE id = ?',
    [transfers[0].id],
  );
  expect(String(row.source_template_id)).toBe('s1');
  expect(String(row.occurrence_date)).toBe('2026-05-15');
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

test('migrate stamps the schema version in db_metadata', async () => {
  const exec = await seededAndAudited();
  await migrate(exec, { fresh: true });
  const meta = await readMetadata(exec);
  expect(meta).not.toBeNull();
  expect(meta!.schemaVersion).toBe(SCHEMA_VERSION);
  expect(meta!.appName).toBe('finch');
});

test('schema shape: budgets carries tag_ids + counterparty_ids; new indexes present', async () => {
  const exec = await seededAndAudited();
  const budgetCols = (await exec('PRAGMA table_info(budgets)')).map((r) => String(r.name));
  // Re-added (tag_ids was dropped 2026-06-06) + counterparty_ids: income goals
  // now match real transactions by tag/merchant.
  expect(budgetCols).toContain('tag_ids');
  expect(budgetCols).toContain('counterparty_ids');

  const indexNames = async (table: string) =>
    (await exec(`PRAGMA index_list(${table})`)).map((r) => String(r.name));
  expect(await indexNames('exchange_rates')).toContain('idx_rate_currency_date');
  expect(await indexNames('exchange_rates')).not.toContain('idx_rate_currency');
  // §2: transactions table dropped; entries/postings carry the DE indexes.
  expect(await indexNames('entries')).toContain('idx_entry_ledger_date');
  expect(await indexNames('postings')).toContain('idx_post_entry');
  expect(await indexNames('postings')).toContain('idx_post_account');
});


test('deleteTag drops the tag and its assignments', async () => {
  const exec = await seededAndAudited();
  // §2: entry_tags replaces transaction_tags.
  expect(Number((await exec("SELECT COUNT(*) AS n FROM entry_tags WHERE tag_id = 'tag-business'"))[0].n)).toBeGreaterThan(0);
  await applyMutation(exec, 'deleteTag', { id: 'tag-business' });
  expect(Number((await exec("SELECT COUNT(*) AS n FROM tags WHERE id = 'tag-business'"))[0].n)).toBe(0);
  expect(Number((await exec("SELECT COUNT(*) AS n FROM entry_tags WHERE tag_id = 'tag-business'"))[0].n)).toBe(0);
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

  const cpId = String((await exec("SELECT id FROM counterparties LIMIT 1"))[0].id);
  await applyMutation(exec, 'updateCounterparty', { id: cpId, patch: { name: 'Renamed Co' } });
  const [cp] = await exec('SELECT name FROM counterparties WHERE id = ?', [cpId]);
  expect(String(cp.name)).toBe('Renamed Co');
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

test('reports: monthly cash flow', async () => {
  const exec = await seededAndAudited();
  const cf = await monthlyCashFlow(exec, 'personal', '2026-05');
  expect(cf.income).toBeCloseTo(2900, 2);
  expect(cf.expense).toBeLessThan(0);
  expect(cf.net).toBeCloseTo(cf.income + cf.expense, 2);
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

// ---------------------------------------------------------------------------
// changeLedgerBase — rewrites locked amount_base figures + re-stamps the
// account opening cost basis. Pre-PR-66 these branches were untested.
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Dispatcher smoke tests. The per-action cases live in their per-domain
// mutations.test.ts files; these cover the dispatcher's own contract: an
// unknown action throws I18nError, and every name in the ActionName union
// resolves to a handler (the Args map smoke test in lib/db/domain/_args.test.ts
// does this at tsc level; this is the runtime-level version).
// ---------------------------------------------------------------------------

test('createBudget persists tagIds/counterpartyIds/saved; updateBudget patches saved + tagIds', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'createBudget', {
    id: 'bgt-inc',
    ledgerId: 'personal',
    name: 'Vacation fund',
    type: 'income',
    amount: 3000,
    isRecurring: 0,
    saved: 100,
    tagIds: ['t1'],
    counterpartyIds: ['c1'],
    frequency: 'monthly',
    startDate: '2026-01-01',
  });

  // Raw row: the JSON columns + saved round-trip through the create insert.
  const [row] = await exec("SELECT kind, tag_ids, counterparty_ids, saved FROM budgets WHERE id = 'bgt-inc'");
  expect(String(row.kind)).toBe('income');
  expect(JSON.parse(String(row.tag_ids))).toEqual(['t1']);
  expect(JSON.parse(String(row.counterparty_ids))).toEqual(['c1']);
  expect(Number(row.saved)).toBe(100);

  // Projected row: rowToBudget parses the JSON columns back into string arrays.
  const b = (await listBudgets(exec, 'personal')).find((x) => x.id === 'bgt-inc')!;
  expect(b.tagIds).toEqual(['t1']);
  expect(b.counterpartyIds).toEqual(['c1']);
  expect(b.saved).toBe(100);

  // updateBudget can patch `saved` and the array columns.
  await applyMutation(exec, 'updateBudget', { id: 'bgt-inc', patch: { saved: 250, tagIds: ['t2'] } });
  const [row2] = await exec("SELECT tag_ids, saved FROM budgets WHERE id = 'bgt-inc'");
  expect(Number(row2.saved)).toBe(250);
  expect(JSON.parse(String(row2.tag_ids))).toEqual(['t2']);
});

test('applyMutation throws I18nError for unknown action', async () => {
  const exec = await seededAndAudited();
  await expect(applyMutation(exec, 'nonexistentAction', {})).rejects.toThrow(I18nError);
});

test('applyMutation dispatches all 73 actions (smoke)', async () => {
  // Pin the action-name list. The Args map smoke test
  // (lib/db/domain/_args.test.ts) already does this at tsc level; this is the
  // runtime-level version — every name must resolve to a handler so a missing
  // case surfaces as 'Unknown action' I18nError in CI.
  const actions: ActionName[] = [
    'addScheduledSplit',
    'addTransaction',
    'adjustAccountBalance',
    'archiveAccount',
    'backfillRule',
    'bulkRecategorize',
    'changeLedgerBase',
    'clearPendingAmount',
    'confirmAllPending',
    'confirmPendingWithMerchant',
    'confirmTransaction',
    'createAccount',
    'createAccountGroup',
    'createBudget',
    'createBudgetGroup',
    'createCategory',
    'createCounterparty',
    'createHolding',
    'createLedger',
    'createRule',
    'createScheduled',
    'createTag',
    'createTransfer',
    'deleteAccount',
    'deleteAccountGroup',
    'deleteBudgetGroup',
    'deleteCategory',
    'deleteCounterparty',
    'deleteExchangeRate',
    'deleteHolding',
    'deleteLedger',
    'deleteRule',
    'deleteScheduled',
    'deleteTag',
    'deleteTransaction',
    'deleteTransfer',
    'generateDueScheduled',
    'markAllReviewed',
    'postScheduled',
    'reconcileAccount',
    'removeAttachment',
    'removeBudget',
    'removeScheduledSplit',
    'reset',
    'setBackupFrequency',
    'setBackupRetention',
    'setCleared',
    'setDefaultLedger',
    'setDisplayCurrency',
    'setExchangeRate',
    'setHoldingPrice',
    'setMobileTabIds',
    'setReviewed',
    'setTransactionSplits',
    'setTransactionTags',
    'unarchiveAccount',
    'unverifyCounterparty',
    'updateAccount',
    'updateAccountGroup',
    'updateBudget',
    'updateBudgetCycle',
    'updateBudgetGroup',
    'updateCategory',
    'updateCounterparty',
    'updateHolding',
    'updateLedger',
    'updateRule',
    'updateScheduled',
    'updateScheduledSplit',
    'updateTag',
    'updateTransaction',
    'updateTransfer',
    'verifyCounterparty',
  ];
  expect(actions.length).toBe(73);

  // The dispatcher should NOT throw 'Unknown action' for any of the 73 names.
  // It MAY throw a different I18nError (per-action arg validation), or a
  // plain Error (invariants), or succeed silently — the test doesn't care
  // about success/failure of the per-action logic, just that the dispatcher
  // routes every action to SOME handler.
  const exec = await seededAndAudited();
  for (const action of actions) {
    try {
      await applyMutation(exec, action, {} as never);
    } catch (err) {
      expect((err as Error).message).not.toMatch(/Unknown action/);
    }
  }
});


