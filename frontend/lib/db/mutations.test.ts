import { test, expect } from 'bun:test';
import sqlite3InitModule from '@sqlite.org/sqlite-wasm';
import type { SqlValue } from '@sqlite.org/sqlite-wasm';
import { applySchema } from '@/lib/db/schema';
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
