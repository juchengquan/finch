import { test, expect } from 'bun:test';
import { seededDb, freshDb } from '@/lib/db/test-utils';
import { applyEntriesSchema } from '@/lib/db/entries-schema';
import type { Exec } from '@/lib/db/repo';

// Seeded in-memory DB (ledger 'personal', base SGD, category 'food', FX rows)
// with the PR-A additive schema applied on top.
export const newDb = async (): Promise<Exec> => {
  const db = await seededDb();
  await applyEntriesSchema(db.exec);
  return db.exec;
};

// Fresh, transaction-less account so balance assertions start from a clean 0
// (seeded accounts already carry legacy-table balances).
export const addAccount = async (exec: Exec, id: string, currency = 'SGD') => {
  await exec(
    `INSERT INTO accounts (id,ledger_id,group_id,name,type,currency,current_balance,opening_balance,opening_balance_base,sort_order,include_in_net_worth,is_active,created_at,updated_at)
     VALUES (?,?,NULL,?,'savings',?,0,0,0,0,1,1,datetime('now'),datetime('now'))`,
    [id, 'personal', id, currency],
  );
};

export const balanceOf = async (exec: Exec, id: string) =>
  Number((await exec('SELECT current_balance AS b FROM accounts WHERE id = ?', [id]))[0].b);

test('applyEntriesSchema creates the new tables and upgrades categories', async () => {
  const exec = await newDb();
  const names = (await exec(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('entries','postings','entry_tags')",
  )).map((r) => String(r.name)).sort();
  expect(names).toEqual(['entries', 'entry_tags', 'postings']);

  // Upgraded CHECK: equity is allowed…
  await exec(
    `INSERT INTO categories (id,ledger_id,parent_id,name,kind,icon,color,sort_order,system,created_at,updated_at)
     VALUES ('cat-eq-t','personal',NULL,'Equity test','equity',NULL,NULL,0,NULL,datetime('now'),datetime('now'))`,
  );
  // …and transfer is not.
  await expect(exec(
    `INSERT INTO categories (id,ledger_id,parent_id,name,kind,icon,color,sort_order,system,created_at,updated_at)
     VALUES ('cat-tr-t','personal',NULL,'Transfer test','transfer',NULL,NULL,0,NULL,datetime('now'),datetime('now'))`,
  )).rejects.toThrow();

  // Seeded categories survived the rebuild.
  const food = await exec("SELECT kind FROM categories WHERE id = 'food'");
  expect(String(food[0].kind)).toBe('expense');
});

test('CATEGORIES_UPGRADE re-kinds transfer categories and keeps the parent FK', async () => {
  // freshDb = canonical schema, no seed: the OLD categories CHECK still
  // allows kind='transfer', so we can stage a pre-upgrade row.
  const db = await freshDb();
  const exec = db.exec;
  await exec(
    "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','SGD',1,datetime('now'),datetime('now'))",
  );
  await exec(
    "INSERT INTO categories (id,ledger_id,parent_id,name,kind,icon,color,sort_order,created_at,updated_at) VALUES ('c-par','l1',NULL,'Parent','expense',NULL,NULL,0,datetime('now'),datetime('now'))",
  );
  await exec(
    "INSERT INTO categories (id,ledger_id,parent_id,name,kind,icon,color,sort_order,created_at,updated_at) VALUES ('c-tr','l1','c-par','Old transfer','transfer',NULL,NULL,1,datetime('now'),datetime('now'))",
  );
  await applyEntriesSchema(exec);
  const [tr] = await exec("SELECT kind, parent_id FROM categories WHERE id = 'c-tr'");
  expect(String(tr.kind)).toBe('expense');
  expect(String(tr.parent_id)).toBe('c-par');
  // The self-referential FK survived the rebuild: deleting the parent
  // promotes the child to top-level (SET NULL), not an error or cascade.
  await exec("DELETE FROM categories WHERE id = 'c-par'");
  const [child] = await exec("SELECT parent_id FROM categories WHERE id = 'c-tr'");
  expect(child.parent_id).toBeNull();
});
