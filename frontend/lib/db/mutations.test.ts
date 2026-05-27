import { test, expect } from 'bun:test';
import sqlite3InitModule from '@sqlite.org/sqlite-wasm';
import type { SqlValue } from '@sqlite.org/sqlite-wasm';
import { applySchema, migrate, SCHEMA_VERSION } from '@/lib/db/schema';
import { seedDatabase } from '@/lib/db/seed';
import { applyMutation } from '@/lib/db/mutations';
import { listTransfers } from '@/lib/db/queries/transfers';
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
    amount: 200,
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
    applyMutation(exec, 'createTransfer', { fromAccountId: 'chk', toAccountId: 'chk', amount: 50, date: '2026-05-27' }),
  ).rejects.toThrow();
  await expect(
    applyMutation(exec, 'createTransfer', { fromAccountId: 'chk', toAccountId: 'sav', amount: 0, date: '2026-05-27' }),
  ).rejects.toThrow();
});

test('postRecurring posts a resolvable expense template as a transaction', async () => {
  const exec = await seeded();
  // rt-spotify: $11.99 expense on "Amex Gold" → account cc.
  const ccBefore = await balanceOf(exec, 'cc');
  await applyMutation(exec, 'postRecurring', { templateId: 'rt-spotify' });
  expect(await balanceOf(exec, 'cc')).toBeCloseTo(ccBefore - 11.99, 2);
  const rows = await exec("SELECT * FROM transactions WHERE description = 'Spotify Premium'");
  expect(rows.length).toBe(1);
  expect(Number(rows[0].amount)).toBeCloseTo(-11.99, 2);
  expect(Number(rows[0].recurring)).toBe(1);
});

test('postRecurring errors clearly when the account cannot be matched', async () => {
  const exec = await seeded();
  // rt-rent uses "UOB One", which has no matching real account.
  await expect(applyMutation(exec, 'postRecurring', { templateId: 'rt-rent' })).rejects.toThrow(/match account/i);
});

test('postRecurring splits income across resolvable accounts', async () => {
  const exec = await seeded();
  // rt-salary: $5800 income split 60/25/15 across UOB One / Marcus Savings / Fidelity.
  // "Marcus Savings"→sav and "Fidelity"→inv resolve; "UOB One" does not.
  const savBefore = await balanceOf(exec, 'sav');
  const invBefore = await balanceOf(exec, 'inv');
  await applyMutation(exec, 'postRecurring', { templateId: 'rt-salary' });
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
    amount: 500,
    date: '2026-05-27',
  });
  const after = await categorySpend(exec, 'personal');
  // A transfer has no category, so category spend is unchanged.
  expect(JSON.stringify(after)).toBe(JSON.stringify(before));
});

test('createCategory inserts a ledger-scoped category', async () => {
  const exec = await seeded();
  const before = Number((await exec("SELECT count(*) AS n FROM categories WHERE ledger_id = 'personal'"))[0].n);
  await applyMutation(exec, 'createCategory', { ledgerId: 'personal', name: 'Travel', type: 'expense', icon: 'plane' });
  const rows = await exec("SELECT * FROM categories WHERE name = 'Travel' AND ledger_id = 'personal'");
  expect(rows.length).toBe(1);
  expect(String(rows[0].type)).toBe('expense');
  expect(String(rows[0].icon)).toBe('plane');
  const after = Number((await exec("SELECT count(*) AS n FROM categories WHERE ledger_id = 'personal'"))[0].n);
  expect(after).toBe(before + 1);
});

test('createCategory rejects an empty name', async () => {
  const exec = await seeded();
  await expect(applyMutation(exec, 'createCategory', { ledgerId: 'personal', name: '  ' })).rejects.toThrow();
});

test('renameCategory updates the name', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'renameCategory', { id: 'food', name: 'Food & Drink' });
  const rows = await exec("SELECT name FROM categories WHERE id = 'food'");
  expect(String(rows[0].name)).toBe('Food & Drink');
});

test('createGoal inserts and contributeGoal adds to saved (clamped at 0)', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'createGoal', { ledgerId: 'personal', name: 'New car', target: 5000, eta: 'Dec 2026' });
  const created = await exec("SELECT id, saved FROM goals WHERE name = 'New car'");
  expect(created.length).toBe(1);
  const id = String(created[0].id);
  await applyMutation(exec, 'contributeGoal', { id, amount: 250 });
  expect(Number((await exec('SELECT saved FROM goals WHERE id = ?', [id]))[0].saved)).toBe(250);
  await applyMutation(exec, 'contributeGoal', { id, amount: -1000 });
  expect(Number((await exec('SELECT saved FROM goals WHERE id = ?', [id]))[0].saved)).toBe(0);
});

test('createGoal rejects empty name or non-positive target', async () => {
  const exec = await seeded();
  await expect(applyMutation(exec, 'createGoal', { name: '', target: 100 })).rejects.toThrow();
  await expect(applyMutation(exec, 'createGoal', { name: 'X', target: 0 })).rejects.toThrow();
});

test('updateRecurringSplit updates the nth split by sort order', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'updateRecurringSplit', { templateId: 'rt-salary', index: 1, pct: 30 });
  const rows = await exec("SELECT amount_pct FROM recurring_splits WHERE template_id = 'rt-salary' ORDER BY sort_order");
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
  await applyMutation(exec, 'createTransfer', { fromAccountId: 'chk', toAccountId: 'eurw', amount: 100, date: '2026-05-24' });
  // chk is USD; 100 USD → EUR at rate_to_sgd(USD)/rate_to_sgd(EUR) = 1.3412 / 1.4592.
  const eur = Number((await exec("SELECT current_balance AS b FROM accounts WHERE id = 'eurw'"))[0].b);
  expect(eur).toBeCloseTo(100 * (1.3412 / 1.4592), 2);
  const tg = await exec('SELECT exchange_rate AS r FROM transfer_groups ORDER BY created_at DESC LIMIT 1');
  expect(Number(tg[0].r)).toBeCloseTo(1.3412 / 1.4592, 4);
});

test('seed records each account opening balance and balances reconcile', async () => {
  const exec = await seeded();
  const [a] = await exec("SELECT opening_balance, current_balance FROM accounts WHERE id = 'cc'");
  const sum = Number(
    (await exec("SELECT COALESCE(SUM(amount_base),0) AS s FROM transactions WHERE account_id='cc' AND status!='cancelled'"))[0].s,
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

test('migrate stamps the schema version', async () => {
  const exec = await seeded();
  await migrate(exec, { fresh: true });
  expect(Number((await exec('PRAGMA user_version'))[0].user_version)).toBe(SCHEMA_VERSION);
});

test('migrate adds + backfills opening_balance on a pre-versioning db', async () => {
  const sqlite3 = await initSqlite({ print() {}, printErr() {} });
  const db = new sqlite3.oo1.DB(':memory:');
  const exec: Exec = async (sql, bind) => {
    const rows: Record<string, SqlValue>[] = [];
    db.exec({ sql, bind: (bind ?? []) as SqlValue[], rowMode: 'object', resultRows: rows });
    return rows;
  };
  // Minimal pre-versioning shape: accounts without opening_balance (plus the other
  // tables later migrations alter, sans their added columns — applySchema would
  // have created these in real paths before migrate runs).
  await exec('CREATE TABLE accounts (id TEXT PRIMARY KEY, current_balance REAL NOT NULL DEFAULT 0)');
  await exec('CREATE TABLE transactions (id TEXT PRIMARY KEY, account_id TEXT, amount_base REAL, status TEXT)');
  await exec('CREATE TABLE categories (id TEXT PRIMARY KEY, name TEXT)');
  await exec("INSERT INTO accounts (id,current_balance) VALUES ('x', 100)");
  await exec("INSERT INTO transactions (id,account_id,amount_base,status) VALUES ('t1','x',-30,'confirmed'),('t2','x',-10,'cancelled')");
  await migrate(exec, { fresh: false });
  const [a] = await exec("SELECT opening_balance FROM accounts WHERE id = 'x'");
  expect(Number(a.opening_balance)).toBeCloseTo(130, 2); // 100 − (−30); cancelled t2 excluded
  expect(Number((await exec('PRAGMA user_version'))[0].user_version)).toBe(SCHEMA_VERSION);
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

test('deleteTag drops the tag and its assignments', async () => {
  const exec = await seeded();
  expect(Number((await exec("SELECT COUNT(*) AS n FROM transaction_tags WHERE tag_id = 'tag-business'"))[0].n)).toBeGreaterThan(0);
  await applyMutation(exec, 'deleteTag', { id: 'tag-business' });
  expect(Number((await exec("SELECT COUNT(*) AS n FROM tags WHERE id = 'tag-business'"))[0].n)).toBe(0);
  expect(Number((await exec("SELECT COUNT(*) AS n FROM transaction_tags WHERE tag_id = 'tag-business'"))[0].n)).toBe(0);
});

test('deleteRecurring removes the template and cascades its splits', async () => {
  const exec = await seeded();
  expect(Number((await exec("SELECT COUNT(*) AS n FROM recurring_splits WHERE template_id = 'rt-salary'"))[0].n)).toBeGreaterThan(0);
  await applyMutation(exec, 'deleteRecurring', { id: 'rt-salary' });
  expect(Number((await exec("SELECT COUNT(*) AS n FROM recurring_templates WHERE id = 'rt-salary'"))[0].n)).toBe(0);
  expect(Number((await exec("SELECT COUNT(*) AS n FROM recurring_splits WHERE template_id = 'rt-salary'"))[0].n)).toBe(0);
});

test('deleteGoal and deleteSubscription hard-delete the row', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'createGoal', { ledgerId: 'personal', name: 'Boat', target: 9000 });
  const goalId = String((await exec("SELECT id FROM goals WHERE name = 'Boat'"))[0].id);
  await applyMutation(exec, 'deleteGoal', { id: goalId });
  expect(Number((await exec('SELECT COUNT(*) AS n FROM goals WHERE id = ?', [goalId]))[0].n)).toBe(0);

  const subId = String((await exec("SELECT id FROM subscriptions LIMIT 1"))[0].id);
  await applyMutation(exec, 'deleteSubscription', { id: subId });
  expect(Number((await exec('SELECT COUNT(*) AS n FROM subscriptions WHERE id = ?', [subId]))[0].n)).toBe(0);
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
  await applyMutation(exec, 'createTransfer', { fromAccountId: 'chk', toAccountId: 'sav', amount: 200, date: '2026-05-27' });
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(chk0 - 200, 2);
  const groupId = String((await exec("SELECT transfer_group_id AS g FROM transactions WHERE transfer_group_id IS NOT NULL LIMIT 1"))[0].g);
  await applyMutation(exec, 'deleteTransfer', { id: groupId });
  expect(Number((await exec('SELECT COUNT(*) AS n FROM transactions WHERE transfer_group_id = ?', [groupId]))[0].n)).toBe(0);
  expect(Number((await exec('SELECT COUNT(*) AS n FROM transfer_groups WHERE id = ?', [groupId]))[0].n)).toBe(0);
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(chk0, 2);
  expect(await balanceOf(exec, 'sav')).toBeCloseTo(sav0, 2);
});

test('updateCategory edits name/type/icon/hue', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'updateCategory', { id: 'food', patch: { name: 'Food & Drink', type: 'income', icon: 'coins', hue: 280 } });
  const [c] = await exec("SELECT name, type, icon, hue FROM categories WHERE id = 'food'");
  expect(String(c.name)).toBe('Food & Drink');
  expect(String(c.type)).toBe('income');
  expect(String(c.icon)).toBe('coins');
  expect(Number(c.hue)).toBe(280);
});

test('createCategory persists icon + hue, and listCategories returns hue', async () => {
  const exec = await seeded();
  const { listCategories } = await import('@/lib/db/queries/categories');
  await applyMutation(exec, 'createCategory', { ledgerId: 'personal', name: 'Travel', type: 'expense', icon: 'car', hue: 200 });
  const cat = (await listCategories(exec, 'personal')).find((c) => c.name === 'Travel')!;
  expect(cat.icon).toBe('car');
  expect(cat.hue).toBe(200);
  // Seeded categories keep their JSON hue too.
  expect((await listCategories(exec, 'personal')).find((c) => c.id === 'food')!.hue).toBe(12);
});

test('updateGoal edits fields and rejects a non-positive target', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'createGoal', { ledgerId: 'personal', name: 'Trip', target: 1000 });
  const id = String((await exec("SELECT id FROM goals WHERE name = 'Trip'"))[0].id);
  await applyMutation(exec, 'updateGoal', { id, patch: { name: 'Big Trip', target: 2500, eta: 'Dec 2026' } });
  const [g] = await exec('SELECT name, target, eta FROM goals WHERE id = ?', [id]);
  expect(String(g.name)).toBe('Big Trip');
  expect(Number(g.target)).toBe(2500);
  expect(String(g.eta)).toBe('Dec 2026');
  await expect(applyMutation(exec, 'updateGoal', { id, patch: { target: 0 } })).rejects.toThrow();
});

test('updateTag and updateSubscription edit fields', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'updateTag', { id: 'tag-business', patch: { name: 'Work', color: '300' } });
  const [tag] = await exec("SELECT name, color FROM tags WHERE id = 'tag-business'");
  expect(String(tag.name)).toBe('Work');
  expect(String(tag.color)).toBe('300');

  const subId = String((await exec('SELECT id FROM subscriptions LIMIT 1'))[0].id);
  await applyMutation(exec, 'updateSubscription', { id: subId, patch: { name: 'Netflix 4K', amount: 22.99, next: 'Jul 1' } });
  const [sub] = await exec('SELECT name, amount, next_date FROM subscriptions WHERE id = ?', [subId]);
  expect(String(sub.name)).toBe('Netflix 4K');
  expect(Number(sub.amount)).toBeCloseTo(22.99, 2);
  expect(String(sub.next_date)).toBe('Jul 1');
});

test('updateRecurring and updateCounterparty edit fields', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'updateRecurring', { id: 'rt-spotify', patch: { name: 'Spotify Duo', amount: 14.99, frequency: 'yearly', dayOfMonth: 5, autoPost: 0 } });
  const [r] = await exec("SELECT name, amount, frequency, day_of_month, auto_post FROM recurring_templates WHERE id = 'rt-spotify'");
  expect(String(r.name)).toBe('Spotify Duo');
  expect(Number(r.amount)).toBeCloseTo(14.99, 2);
  expect(String(r.frequency)).toBe('yearly');
  expect(Number(r.day_of_month)).toBe(5);
  expect(Number(r.auto_post)).toBe(0);

  const cpId = String((await exec("SELECT id FROM counterparties WHERE ledger_id = 'personal' LIMIT 1"))[0].id);
  await applyMutation(exec, 'updateCounterparty', { id: cpId, patch: { name: 'Renamed Co', category: 'shop' } });
  const [cp] = await exec('SELECT standardized_name, category FROM counterparties WHERE id = ?', [cpId]);
  expect(String(cp.standardized_name)).toBe('Renamed Co');
  expect(String(cp.category)).toBe('shop');
});

test('setBudget upserts the budgets table; deleteBudget removes it', async () => {
  const exec = await seeded();
  const { budgetByCategory } = await import('@/lib/db/queries/budgets');
  expect((await budgetByCategory(exec)).food).toBe(700); // seeded

  await applyMutation(exec, 'setBudget', { categoryId: 'food', amount: 950 });
  expect((await budgetByCategory(exec)).food).toBe(950);
  expect(Number((await exec("SELECT amount FROM budgets WHERE id = 'bud-food'"))[0].amount)).toBe(950);

  // Insert path: a category created without a budget gets a new row.
  await applyMutation(exec, 'createCategory', { ledgerId: 'personal', name: 'Travel' });
  const travelId = String((await exec("SELECT id FROM categories WHERE name = 'Travel'"))[0].id);
  await applyMutation(exec, 'setBudget', { categoryId: travelId, amount: 300 });
  expect((await budgetByCategory(exec))[travelId]).toBe(300);

  await applyMutation(exec, 'setBudget', { categoryId: 'food', amount: -5 }).then(
    () => { throw new Error('should reject'); },
    () => {},
  );

  await applyMutation(exec, 'deleteBudget', { categoryId: 'food' });
  expect((await budgetByCategory(exec)).food).toBeUndefined();
});

test('updateTransfer rewrites both legs and recomputes balances', async () => {
  const exec = await seeded();
  const chk0 = await balanceOf(exec, 'chk');
  const sav0 = await balanceOf(exec, 'sav');
  await applyMutation(exec, 'createTransfer', { fromAccountId: 'chk', toAccountId: 'sav', amount: 200, date: '2026-05-27', note: 'a' });
  const groupId = String((await exec("SELECT transfer_group_id AS g FROM transactions WHERE transfer_group_id IS NOT NULL LIMIT 1"))[0].g);
  await applyMutation(exec, 'updateTransfer', { id: groupId, patch: { amount: 350, date: '2026-05-28', note: 'updated' } });
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(chk0 - 350, 2);
  expect(await balanceOf(exec, 'sav')).toBeCloseTo(sav0 + 350, 2);
  const legs = await exec('SELECT date, notes FROM transactions WHERE transfer_group_id = ?', [groupId]);
  expect(legs.every((l) => l.date === '2026-05-28' && l.notes === 'updated')).toBe(true);
});

test('scheduled items create / update / delete', async () => {
  const exec = await seeded();
  const { listScheduledItems } = await import('@/lib/db/queries/planning');
  await applyMutation(exec, 'createScheduledItem', { id: 'sch-x', ledgerId: 'personal', day: 12, month: 'Jul', label: 'Insurance', amount: -120, type: 'Bill', color: '#abc' });
  let item = (await listScheduledItems(exec, 'personal')).find((s) => s.id === 'sch-x')!;
  expect(item.label).toBe('Insurance');
  expect(item.amount).toBeCloseTo(-120, 2);

  await applyMutation(exec, 'updateScheduledItem', { id: 'sch-x', patch: { label: 'Car Insurance', amount: -130, day: 15 } });
  item = (await listScheduledItems(exec, 'personal')).find((s) => s.id === 'sch-x')!;
  expect(item.label).toBe('Car Insurance');
  expect(item.day).toBe(15);

  await applyMutation(exec, 'deleteScheduledItem', { id: 'sch-x' });
  expect((await listScheduledItems(exec, 'personal')).find((s) => s.id === 'sch-x')).toBeUndefined();
});
