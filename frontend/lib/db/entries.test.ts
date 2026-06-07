import { test, expect } from 'bun:test';
import { seededDb, freshDb } from '@/lib/db/test-utils';
import { applyEntriesSchema } from '@/lib/db/entries-schema';
import type { Exec } from '@/lib/db/repo';
import { ensureSystemCategories, postEntry } from '@/lib/db/entries';

// Seeded in-memory DB (ledger 'personal', category 'food', FX rows — see
// data/*.json) with the PR-A additive schema applied on top. Base-sensitive
// tests don't rely on any seeded ledger's base: they build their own ledger
// via withTestLedger (ledger base is user-chosen at create time).
export const newDb = async (): Promise<Exec> => {
  const db = await seededDb();
  await applyEntriesSchema(db.exec);
  return db.exec;
};

// Fresh, transaction-less account so balance assertions start from a clean 0
// (seeded accounts already carry legacy-table balances).
export const addAccount = async (exec: Exec, id: string, currency = 'SGD', ledgerId = 'personal') => {
  await exec(
    `INSERT INTO accounts (id,ledger_id,group_id,name,type,currency,current_balance,opening_balance,opening_balance_base,sort_order,include_in_net_worth,is_active,created_at,updated_at)
     VALUES (?,?,NULL,?,'savings',?,0,0,0,0,1,1,datetime('now'),datetime('now'))`,
    [id, ledgerId, id, currency],
  );
};

// Ledger base is user-chosen at create time, so base-sensitive tests create
// their OWN ledger + category instead of assuming anything about the seed.
export const addLedger = async (exec: Exec, id: string, base: string) => {
  await exec(
    "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES (?,?,?,0,datetime('now'),datetime('now'))",
    [id, id, base],
  );
};
export const addCategory = async (exec: Exec, id: string, ledgerId: string, kind = 'expense') => {
  await exec(
    "INSERT INTO categories (id,ledger_id,parent_id,name,kind,icon,color,sort_order,system,created_at,updated_at) VALUES (?,?,NULL,?,?,NULL,NULL,0,NULL,datetime('now'),datetime('now'))",
    [id, ledgerId, id, kind],
  );
};
// The standard base-sensitive fixture: ledger 'lt' (base SGD), category 'cat-t'.
export const withTestLedger = async (exec: Exec) => {
  await addLedger(exec, 'lt', 'SGD');
  await addCategory(exec, 'cat-t', 'lt');
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

// --- raw-SQL helpers for trigger-level tests (no chokepoint involved) ---
const rawEntry = (exec: Exec, id: string, kind = 'expense', status = 'confirmed') =>
  exec(
    `INSERT INTO entries (id,ledger_id,date,description,kind,status,sealed,created_at,updated_at)
     VALUES (?,?,'2026-06-01','raw',?,?,0,datetime('now'),datetime('now'))`,
    [id, 'personal', kind, status],
  );
const rawLeg = (exec: Exec, id: string, entryId: string, accountId: string | null, categoryId: string | null, amount: number, base = amount, currency = 'SGD') =>
  exec(
    `INSERT INTO postings (id,entry_id,account_id,category_id,amount,currency,amount_base,exchange_rate,sort_order)
     VALUES (?,?,?,?,?,?,?,1,0)`,
    [id, entryId, accountId, categoryId, amount, currency, base],
  );
const seal = (exec: Exec, id: string) => exec('UPDATE entries SET sealed = 1 WHERE id = ?', [id]);

test('seal rejects an unbalanced entry', async () => {
  const exec = await newDb();
  await addAccount(exec, 'a1');
  await rawEntry(exec, 'e-unbal');
  await rawLeg(exec, 'p-u1', 'e-unbal', 'a1', null, -100);
  await rawLeg(exec, 'p-u2', 'e-unbal', null, 'food', 90);
  await expect(seal(exec, 'e-unbal')).rejects.toThrow('Entry postings must balance');
});

test('seal rejects fewer than two postings and entries with no account leg', async () => {
  const exec = await newDb();
  await addAccount(exec, 'a2');
  await rawEntry(exec, 'e-one');
  await rawLeg(exec, 'p-o1', 'e-one', 'a2', null, 0);
  await expect(seal(exec, 'e-one')).rejects.toThrow('Entry postings must balance');

  await rawEntry(exec, 'e-nacct');
  await rawLeg(exec, 'p-n1', 'e-nacct', null, 'food', -50);
  await rawLeg(exec, 'p-n2', 'e-nacct', null, 'food', 50);
  await expect(seal(exec, 'e-nacct')).rejects.toThrow('Entry postings must balance');
});

test('sealed postings are immutable except cleared_at/memo; cascade delete passes', async () => {
  const exec = await newDb();
  await addAccount(exec, 'a3');
  await rawEntry(exec, 'e-ok');
  await rawLeg(exec, 'p-k1', 'e-ok', 'a3', null, -100);
  await rawLeg(exec, 'p-k2', 'e-ok', null, 'food', 100);
  await seal(exec, 'e-ok'); // balanced → succeeds

  await expect(rawLeg(exec, 'p-k3', 'e-ok', 'a3', null, 1)).rejects.toThrow('Unseal');
  await expect(exec('UPDATE postings SET amount = -90 WHERE id = ?', ['p-k1'])).rejects.toThrow('Unseal');
  await expect(exec('DELETE FROM postings WHERE id = ?', ['p-k1'])).rejects.toThrow('Unseal');
  // cleared_at + memo stay editable on sealed entries (setCleared needs this).
  await exec("UPDATE postings SET cleared_at = datetime('now'), memo = 'cleared' WHERE id = ?", ['p-k1']);

  // FK CASCADE from the entry delete passes the guards (parent row is gone
  // first, so the guard's sealed-subquery returns NULL).
  await exec('DELETE FROM entries WHERE id = ?', ['e-ok']);
  const left = await exec("SELECT COUNT(*) AS n FROM postings WHERE entry_id = 'e-ok'");
  expect(Number(left[0].n)).toBe(0);
});

test('seal rejects a zero-posting entry (COALESCE guard)', async () => {
  const exec = await newDb();
  await rawEntry(exec, 'e-zero');
  await expect(seal(exec, 'e-zero')).rejects.toThrow('Entry postings must balance');
});

test('a posting cannot be moved out of a sealed entry', async () => {
  const exec = await newDb();
  await addAccount(exec, 'a4');
  await rawEntry(exec, 'e-sealed2');
  await rawLeg(exec, 'p-s1', 'e-sealed2', 'a4', null, -10);
  await rawLeg(exec, 'p-s2', 'e-sealed2', null, 'food', 10);
  await seal(exec, 'e-sealed2');
  await rawEntry(exec, 'e-open'); // unsealed target
  await expect(
    exec("UPDATE postings SET entry_id = 'e-open' WHERE id = 'p-s1'"),
  ).rejects.toThrow('Unseal');
});

test('account legs must be in the account currency', async () => {
  const exec = await newDb();
  await addAccount(exec, 'a-usd', 'USD');
  await rawEntry(exec, 'e-ccy');
  await expect(
    rawLeg(exec, 'p-c1', 'e-ccy', 'a-usd', null, -100, -100, 'SGD'),
  ).rejects.toThrow('account currency');
  // Category legs are exempt (they're base-denominated, no account).
  await rawLeg(exec, 'p-c2', 'e-ccy', null, 'food', 100, 100, 'SGD');
});

test('confirmed postings move the cached balance; pending do not', async () => {
  const exec = await newDb();
  await addAccount(exec, 'a-bal');
  await rawEntry(exec, 'e-conf', 'expense', 'confirmed');
  await rawLeg(exec, 'p-b1', 'e-conf', 'a-bal', null, -25.5);
  await rawLeg(exec, 'p-b2', 'e-conf', null, 'food', 25.5);
  await seal(exec, 'e-conf');
  expect(await balanceOf(exec, 'a-bal')).toBe(-25.5);

  await rawEntry(exec, 'e-pend', 'expense', 'pending');
  await rawLeg(exec, 'p-b3', 'e-pend', 'a-bal', null, -10);
  await rawLeg(exec, 'p-b4', 'e-pend', null, 'food', 10);
  await seal(exec, 'e-pend');
  expect(await balanceOf(exec, 'a-bal')).toBe(-25.5); // unchanged
});

test('the currency guard also fires on UPDATE of an unsealed posting', async () => {
  const exec = await newDb();
  await addAccount(exec, 'a-cu', 'SGD');
  await rawEntry(exec, 'e-cu');
  await rawLeg(exec, 'p-cu1', 'e-cu', 'a-cu', null, -5);
  await expect(
    exec("UPDATE postings SET currency = 'USD' WHERE id = 'p-cu1'"),
  ).rejects.toThrow('account currency');
});

test('the balance trigger rounds accumulated cents', async () => {
  const exec = await newDb();
  await addAccount(exec, 'a-rd');
  await rawEntry(exec, 'e-rd');
  await rawLeg(exec, 'p-rd1', 'e-rd', 'a-rd', null, -0.1);
  await rawLeg(exec, 'p-rd2', 'e-rd', 'a-rd', null, -0.2);
  await rawLeg(exec, 'p-rd3', 'e-rd', null, 'food', 0.3);
  await seal(exec, 'e-rd');
  expect(await balanceOf(exec, 'a-rd')).toBe(-0.3);
});

test('ensureSystemCategories is idempotent and per-ledger', async () => {
  const exec = await newDb();
  const a = await ensureSystemCategories(exec, 'personal');
  const b = await ensureSystemCategories(exec, 'personal');
  expect(a).toEqual(b); // second call returns the same ids, inserts nothing

  const rows = await exec(
    "SELECT system, kind FROM categories WHERE ledger_id = 'personal' AND system IS NOT NULL ORDER BY system",
  );
  expect(rows.map((r) => `${r.system}:${r.kind}`)).toEqual([
    'adjustment:equity', 'fx:equity', 'opening:equity',
  ]);

  // Per-ledger isolation: another seeded ledger gets its own rows.
  const c = await ensureSystemCategories(exec, 'family');
  expect(c.opening).not.toBe(a.opening);
});

test('postEntry books a balanced expense with an auto-balance category leg', async () => {
  const exec = await newDb();
  await withTestLedger(exec);
  await addAccount(exec, 'a-pe1', 'SGD', 'lt');
  const { entryId } = await postEntry(exec, {
    ledgerId: 'lt', date: '2026-06-02', description: 'Lunch', kind: 'expense',
    legs: [{ accountId: 'a-pe1', amount: -12.5 }],
    autoBalanceCategoryId: 'cat-t', skipRules: true,
  });
  const legs = await exec('SELECT account_id, category_id, amount, amount_base, currency FROM postings WHERE entry_id = ? ORDER BY sort_order', [entryId]);
  expect(legs.length).toBe(2);
  expect(Number(legs[0].amount)).toBe(-12.5);          // account leg, SGD == ledger base
  expect(String(legs[1].category_id)).toBe('cat-t');    // category leg, +12.5 base
  expect(Number(legs[1].amount_base)).toBe(12.5);
  const [e] = await exec('SELECT sealed, status FROM entries WHERE id = ?', [entryId]);
  expect(Number(e.sealed)).toBe(1);
  expect(String(e.status)).toBe('confirmed');
  expect(await balanceOf(exec, 'a-pe1')).toBe(-12.5);
});

test('postEntry appends an FX-residue equity leg when locked bases disagree', async () => {
  const exec = await newDb();
  await withTestLedger(exec);
  await addAccount(exec, 'a-sgd1', 'SGD', 'lt');
  await addAccount(exec, 'a-usd1', 'USD', 'lt');
  const sys = await ensureSystemCategories(exec, 'lt');
  // Pre-locked bases that deliberately don't cancel: −100 SGD vs +74 USD
  // worth 100.50 SGD (a pinned bank rate).
  const { entryId } = await postEntry(exec, {
    ledgerId: 'lt', date: '2026-06-02', description: 'FX move', kind: 'transfer', skipRules: true,
    legs: [
      { accountId: 'a-sgd1', amount: -100, amountBase: -100, exchangeRate: 1 },
      { accountId: 'a-usd1', amount: 74, amountBase: 100.5, exchangeRate: 1.358 },
    ],
  });
  const fx = await exec('SELECT amount_base FROM postings WHERE entry_id = ? AND category_id = ?', [entryId, sys.fx]);
  expect(fx.length).toBe(1);
  expect(Number(fx[0].amount_base)).toBe(-0.5); // exact balance (I1)
});

test('postEntry validates shape per kind and is atomic on failure', async () => {
  const exec = await newDb();
  await withTestLedger(exec);
  await addAccount(exec, 'a-pe2', 'SGD', 'lt');
  // refund must be positive
  await expect(postEntry(exec, {
    ledgerId: 'lt', date: '2026-06-02', description: 'Bad refund', kind: 'refund', skipRules: true,
    legs: [{ accountId: 'a-pe2', amount: -5 }], autoBalanceCategoryId: 'cat-t',
  })).rejects.toThrow('refund must be positive');
  // transfer needs exactly two account legs
  await expect(postEntry(exec, {
    ledgerId: 'lt', date: '2026-06-02', description: 'Bad transfer', kind: 'transfer', skipRules: true,
    legs: [{ accountId: 'a-pe2', amount: -5 }], autoBalanceCategoryId: 'cat-t',
  })).rejects.toThrow('exactly two account legs');
  // nothing leaked from the failed attempts
  const n = await exec("SELECT COUNT(*) AS n FROM entries WHERE description LIKE 'Bad %'");
  expect(Number(n[0].n)).toBe(0);
  expect(await balanceOf(exec, 'a-pe2')).toBe(0);
});

test('postEntry keeps amount = amount_base on base-currency legs (I9)', async () => {
  const exec = await newDb();
  await withTestLedger(exec);
  await addAccount(exec, 'a-pe3', 'SGD', 'lt'); // account currency == ledger base
  const { entryId } = await postEntry(exec, {
    ledgerId: 'lt', date: '2026-06-02', description: 'Salary', kind: 'income', skipRules: true,
    legs: [{ accountId: 'a-pe3', amount: 3000 }], autoBalanceCategoryId: null,
  });
  const legs = await exec('SELECT amount, amount_base FROM postings WHERE entry_id = ?', [entryId]);
  for (const l of legs) expect(Number(l.amount)).toBe(Number(l.amount_base));
});
