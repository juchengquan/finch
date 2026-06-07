import { test, expect } from 'bun:test';
import { seededDb, freshDb } from '@/lib/db/test-utils';
import { applyEntriesSchema } from '@/lib/db/entries-schema';
import type { Exec } from '@/lib/db/repo';
import {
  ensureSystemCategories, postEntry,
  postSimple, postTransfer, postAdjustment, postOpening,
  rebuildEntry, recomputeAccountFromPostings,
} from '@/lib/db/entries';

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

test('cross-currency rule splits absorb base rounding — no phantom FX leg', async () => {
  const exec = await newDb();
  await withTestLedger(exec); // ledger 'lt', base SGD
  await addAccount(exec, 'a-xs', 'USD', 'lt');
  const sys = await ensureSystemCategories(exec, 'lt');
  // Pin a rate that makes USD→SGD = 1/0.75 = 1.333… (irrational per-leg r2 drift).
  await exec("INSERT OR REPLACE INTO exchange_rates (date,currency,rate,source) VALUES ('2026-06-02','SGD',0.75,'manual')");
  await exec(
    `INSERT INTO rules (id,ledger_id,name,priority,condition,actions,is_active,run_on_edit,created_at,updated_at)
     VALUES ('rule-xs','lt','halve',100,?,?,1,0,datetime('now'),datetime('now'))`,
    [
      JSON.stringify({ field: 'merchant', op: 'contains', value: 'Halves' }),
      JSON.stringify([{ type: 'split', splits: [
        { categoryId: 'cat-t', fraction: 0.5 },
        { categoryId: null, fraction: 0.5 },
      ] }]),
    ],
  );
  const { entryId } = await postEntry(exec, {
    ledgerId: 'lt', date: '2026-06-02', description: 'Halves Mart', kind: 'expense',
    legs: [{ accountId: 'a-xs', amount: -100 }], autoBalanceCategoryId: null,
  });
  const fx = await exec('SELECT COUNT(*) AS n FROM postings WHERE entry_id = ? AND category_id = ?', [entryId, sys.fx]);
  expect(Number(fx[0].n)).toBe(0); // rounding absorbed by the last split, not minted as FX
  const sum = await exec('SELECT ROUND(SUM(amount_base),2) AS s FROM postings WHERE entry_id = ?', [entryId]);
  expect(Math.abs(Number(sum[0].s))).toBe(0);
  const cats = await exec('SELECT amount_base FROM postings WHERE entry_id = ? AND account_id IS NULL ORDER BY sort_order', [entryId]);
  expect(cats.length).toBe(2);
  // −100 USD at 1.333… → base −133.33; halves: 66.67 + 66.66.
  expect(Number(cats[0].amount_base)).toBe(66.67);
  expect(Number(cats[1].amount_base)).toBe(66.66);
});

test('an identical timed manual add collides; NULL time never collides', async () => {
  const exec = await newDb();
  await withTestLedger(exec);
  await addAccount(exec, 'a-dd', 'SGD', 'lt');
  const mk = (id: string, time: string | null) => postEntry(exec, {
    id, ledgerId: 'lt', date: '2026-06-03', time, description: 'Coffee', kind: 'expense',
    legs: [{ accountId: 'a-dd', amount: -6 }], autoBalanceCategoryId: 'cat-t', skipRules: true,
  });
  await mk('e-dd1', '08:30');
  await expect(mk('e-dd2', '08:30')).rejects.toThrow('UNIQUE');
  // NULL-time parity with the old idx_txn_dedup carve-out (scheduled posts):
  await mk('e-dd3', null);
  await mk('e-dd4', null);
  const n = await exec("SELECT COUNT(*) AS n FROM entries WHERE description = 'Coffee'");
  expect(Number(n[0].n)).toBe(3);
});

test('postEntry resolves the counterparty from the description', async () => {
  const exec = await newDb();
  await withTestLedger(exec);
  await addAccount(exec, 'a-cp', 'SGD', 'lt');
  await exec(
    "INSERT INTO counterparties (id,ledger_id,name,is_verified,created_at,updated_at) VALUES ('cp-t1','lt','Blue Bottle',1,datetime('now'),datetime('now'))",
  );
  const { entryId } = await postEntry(exec, {
    ledgerId: 'lt', date: '2026-06-03', description: 'blue bottle', kind: 'expense',
    legs: [{ accountId: 'a-cp', amount: -8 }], autoBalanceCategoryId: 'cat-t',
  });
  const [e] = await exec('SELECT counterparty_id FROM entries WHERE id = ?', [entryId]);
  expect(String(e.counterparty_id)).toBe('cp-t1');
});

test('a rule can recategorize, split, and tag an incoming entry', async () => {
  const exec = await newDb();
  await withTestLedger(exec);
  await addAccount(exec, 'a-rl', 'SGD', 'lt');
  await exec(
    "INSERT INTO tags (id,ledger_id,name,color,created_at,updated_at) VALUES ('tag-t','lt','market',NULL,datetime('now'),datetime('now'))",
  );
  await exec(
    `INSERT INTO rules (id,ledger_id,name,priority,condition,actions,is_active,run_on_edit,created_at,updated_at)
     VALUES ('rule-t1','lt','split groceries',100,?,?,1,0,datetime('now'),datetime('now'))`,
    [
      JSON.stringify({ field: 'merchant', op: 'contains', value: 'Market' }),
      JSON.stringify([
        { type: 'split', splits: [
          { categoryId: 'cat-t', fraction: 0.6 },
          { categoryId: null, fraction: 0.4 },
        ] },
        { type: 'add_tag', tagId: 'tag-t' },
      ]),
    ],
  );
  const { entryId } = await postEntry(exec, {
    ledgerId: 'lt', date: '2026-06-03', description: 'Sunday Market', kind: 'expense',
    legs: [{ accountId: 'a-rl', amount: -50 }], autoBalanceCategoryId: null,
  });
  const cats = await exec(
    'SELECT category_id, amount_base FROM postings WHERE entry_id = ? AND account_id IS NULL ORDER BY sort_order',
    [entryId],
  );
  expect(cats.length).toBe(2);
  expect(Number(cats[0].amount_base)).toBe(30);  // 60% of 50, negated to the category side
  expect(Number(cats[1].amount_base)).toBe(20);  // remainder-absorbing last split
  const [e] = await exec('SELECT applied_rule_ids FROM entries WHERE id = ?', [entryId]);
  expect(String(e.applied_rule_ids)).toContain('rule-t1');
  // Rule-added tag landed in entry_tags (insertTxRow parity).
  const tags = await exec('SELECT tag_id FROM entry_tags WHERE entry_id = ?', [entryId]);
  expect(tags.map((t) => String(t.tag_id))).toEqual(['tag-t']);
});

test('postOpening books a pre-cleared opening entry; zero is a no-op', async () => {
  const exec = await newDb();
  await withTestLedger(exec);
  await addAccount(exec, 'a-op', 'SGD', 'lt');
  expect(await postOpening(exec, { ledgerId: 'lt', accountId: 'a-op', amount: 0, date: '2026-06-01' })).toBeNull();
  const res = await postOpening(exec, { ledgerId: 'lt', accountId: 'a-op', amount: 250, date: '2026-06-01' });
  expect(res?.entryId).toBe('open-a-op');
  const [leg] = await exec('SELECT cleared_at FROM postings WHERE entry_id = ? AND account_id IS NOT NULL', ['open-a-op']);
  expect(leg.cleared_at).not.toBeNull();
  const [e] = await exec('SELECT kind, status FROM entries WHERE id = ?', ['open-a-op']);
  expect(String(e.kind)).toBe('opening');
  // Idempotent: a second call returns the same entry and books nothing new.
  const again = await postOpening(exec, { ledgerId: 'lt', accountId: 'a-op', amount: 250, date: '2026-06-01' });
  expect(again?.entryId).toBe('open-a-op');
  expect(await balanceOf(exec, 'a-op')).toBe(250);
});

test('postAdjustment books the delta against the adjustment equity category', async () => {
  const exec = await newDb();
  await withTestLedger(exec);
  await addAccount(exec, 'a-adj', 'SGD', 'lt');
  const sys = await ensureSystemCategories(exec, 'lt');
  // Sub-cent / zero deltas are a silent no-op (legacy adjustAccountBalance parity).
  expect(await postAdjustment(exec, { ledgerId: 'lt', accountId: 'a-adj', delta: 0.004, date: '2026-06-04' })).toBeNull();
  const res = await postAdjustment(exec, {
    ledgerId: 'lt', accountId: 'a-adj', delta: -12.34, date: '2026-06-04', source: 'reconcile',
  });
  const entryId = res!.entryId;
  const [e] = await exec('SELECT kind, description FROM entries WHERE id = ?', [entryId]);
  expect(String(e.kind)).toBe('adjustment');
  expect(String(e.description)).toBe('Reconciliation adjustment');
  const eq = await exec('SELECT amount_base FROM postings WHERE entry_id = ? AND category_id = ?', [entryId, sys.adjustment]);
  expect(Number(eq[0].amount_base)).toBe(12.34);
  expect(await balanceOf(exec, 'a-adj')).toBe(-12.34);
});

test('postSimple defaults kind by sign', async () => {
  const exec = await newDb();
  await withTestLedger(exec);
  await addAccount(exec, 'a-sim', 'SGD', 'lt');
  const { entryId } = await postSimple(exec, {
    ledgerId: 'lt', accountId: 'a-sim', amount: 99, date: '2026-06-04',
    description: 'Rebate', skipRules: true,
  });
  const [e] = await exec('SELECT kind FROM entries WHERE id = ?', [entryId]);
  expect(String(e.kind)).toBe('income');
});

test('postTransfer: same-currency equality, cross-currency residue, pinned toAmount', async () => {
  const exec = await newDb();
  await withTestLedger(exec);
  await addAccount(exec, 'a-t1', 'SGD', 'lt');
  await addAccount(exec, 'a-t2', 'SGD', 'lt');
  await addAccount(exec, 'a-t3', 'USD', 'lt');
  await ensureSystemCategories(exec, 'lt');

  await expect(postTransfer(exec, {
    fromAccountId: 'a-t1', toAccountId: 'a-t2', fromAmount: 100, toAmount: 90, date: '2026-06-04',
  })).rejects.toThrow('Same-currency transfer amounts must match');

  // Same currency: two legs, no residue.
  const ok = await postTransfer(exec, { fromAccountId: 'a-t1', toAccountId: 'a-t2', fromAmount: 100, date: '2026-06-04' });
  const legs = await exec('SELECT COUNT(*) AS n FROM postings WHERE entry_id = ?', [ok.entryId]);
  expect(Number(legs[0].n)).toBe(2);
  expect(await balanceOf(exec, 'a-t1')).toBe(-100);
  expect(await balanceOf(exec, 'a-t2')).toBe(100);

  // Cross-currency with a pinned (off-market) toAmount: each leg locks its own
  // base; the difference lands on the fx equity leg, and the entry still
  // balances exactly.
  const x = await postTransfer(exec, {
    fromAccountId: 'a-t1', toAccountId: 'a-t3', fromAmount: 135, toAmount: 100, date: '2026-06-04',
  });
  const sum = await exec('SELECT ROUND(SUM(amount_base),2) AS s FROM postings WHERE entry_id = ?', [x.entryId]);
  expect(Math.abs(Number(sum[0].s))).toBe(0);
  const memos = await exec('SELECT memo FROM postings WHERE entry_id = ? AND account_id IS NOT NULL ORDER BY sort_order', [x.entryId]);
  expect(String(memos[0].memo)).toContain('Transfer to');
  expect(String(memos[1].memo)).toContain('Transfer from');
});

test('rebuildEntry: header-only patch keeps legs; status flip recomputes', async () => {
  const exec = await newDb();
  await withTestLedger(exec);
  await addAccount(exec, 'a-rb1', 'SGD', 'lt');
  const { entryId } = await postSimple(exec, {
    ledgerId: 'lt', accountId: 'a-rb1', amount: -40, date: '2026-06-05',
    description: 'Dinner', categoryId: 'cat-t', skipRules: true,
  });
  await rebuildEntry(exec, entryId, { description: 'Dinner out', status: 'pending' });
  const [e] = await exec('SELECT description, status, confirmed_at, sealed FROM entries WHERE id = ?', [entryId]);
  expect(String(e.description)).toBe('Dinner out');
  expect(String(e.status)).toBe('pending');
  expect(e.confirmed_at).toBeNull();
  expect(Number(e.sealed)).toBe(1);
  expect(await balanceOf(exec, 'a-rb1')).toBe(0); // pending rows don't count

  await rebuildEntry(exec, entryId, { status: 'confirmed' });
  expect(await balanceOf(exec, 'a-rb1')).toBe(-40);
});

test('rebuildEntry: a date edit re-locks account-leg bases at the new date', async () => {
  const exec = await newDb();
  await withTestLedger(exec); // ledger 'lt', base SGD
  await addAccount(exec, 'a-rb2', 'USD', 'lt');
  // Pin two distinct SGD-hub rate days so the re-lock is observable:
  // rate(USD→SGD) = rateToHub(USD)/rateToHub(SGD) = 1/r(SGD).
  await exec("INSERT OR REPLACE INTO exchange_rates (date,currency,rate,source) VALUES ('2026-06-01','SGD',0.5,'manual')");
  await exec("INSERT OR REPLACE INTO exchange_rates (date,currency,rate,source) VALUES ('2026-06-10','SGD',0.8,'manual')");
  const { entryId } = await postSimple(exec, {
    ledgerId: 'lt', accountId: 'a-rb2', amount: -100, date: '2026-06-01',
    description: 'USD spend', categoryId: 'cat-t', skipRules: true,
  });
  const base1 = Number((await exec('SELECT amount_base AS b FROM postings WHERE entry_id = ? AND account_id IS NOT NULL', [entryId]))[0].b);
  expect(base1).toBe(-200); // 100 USD at SGD-hub 0.5 → 200 SGD

  await rebuildEntry(exec, entryId, { date: '2026-06-10' });
  const base2 = Number((await exec('SELECT amount_base AS b FROM postings WHERE entry_id = ? AND account_id IS NOT NULL', [entryId]))[0].b);
  expect(base2).toBe(-125); // 100 USD at SGD-hub 0.8 → 125 SGD
  // Plain category legs scale with the re-lock (the category side follows the
  // new figure — no phantom FX residue on a simple expense).
  const cats = await exec('SELECT amount_base FROM postings WHERE entry_id = ? AND account_id IS NULL', [entryId]);
  expect(cats.length).toBe(1);
  expect(Number(cats[0].amount_base)).toBe(125);
  const sum = await exec('SELECT ROUND(SUM(amount_base),2) AS s FROM postings WHERE entry_id = ?', [entryId]);
  expect(Math.abs(Number(sum[0].s))).toBe(0); // still balanced after re-lock
});

test('rebuildEntry: legs replacement rebalances and recomputes both accounts', async () => {
  const exec = await newDb();
  await withTestLedger(exec);
  await addAccount(exec, 'a-rb3', 'SGD', 'lt');
  await addAccount(exec, 'a-rb4', 'SGD', 'lt');
  const { entryId } = await postSimple(exec, {
    ledgerId: 'lt', accountId: 'a-rb3', amount: -10, date: '2026-06-05',
    description: 'Move me', categoryId: 'cat-t', skipRules: true,
  });
  await rebuildEntry(exec, entryId, {
    legs: [{ accountId: 'a-rb4', amount: -10 }, { categoryId: 'cat-t', amountBase: 10 }],
  });
  expect(await balanceOf(exec, 'a-rb3')).toBe(0);   // old account released
  expect(await balanceOf(exec, 'a-rb4')).toBe(-10); // new account charged
});

test('recomputeAccountFromPostings restores a corrupted cached balance', async () => {
  const exec = await newDb();
  await withTestLedger(exec);
  await addAccount(exec, 'a-rc', 'SGD', 'lt');
  await postSimple(exec, {
    ledgerId: 'lt', accountId: 'a-rc', amount: -33.33, date: '2026-06-05',
    description: 'Drift', categoryId: 'cat-t', skipRules: true,
  });
  await exec("UPDATE accounts SET current_balance = 999 WHERE id = 'a-rc'");
  await recomputeAccountFromPostings(exec, 'a-rc');
  expect(await balanceOf(exec, 'a-rc')).toBe(-33.33);
});

test('rebuildEntry rejects a kind change that contradicts the leg shape', async () => {
  const exec = await newDb();
  await withTestLedger(exec);
  await addAccount(exec, 'a-kv', 'SGD', 'lt');
  const { entryId } = await postSimple(exec, {
    ledgerId: 'lt', accountId: 'a-kv', amount: -7, date: '2026-06-05',
    description: 'Negative', categoryId: 'cat-t', skipRules: true,
  });
  await expect(rebuildEntry(exec, entryId, { kind: 'refund' })).rejects.toThrow('refund must be positive');
  const [e] = await exec('SELECT kind, sealed FROM entries WHERE id = ?', [entryId]);
  expect(String(e.kind)).toBe('expense'); // the whole edit rolled back
  expect(Number(e.sealed)).toBe(1);
});

test('rebuildEntry re-stamps the dedup hash from the edited content', async () => {
  const exec = await newDb();
  await withTestLedger(exec);
  await addAccount(exec, 'a-dh', 'SGD', 'lt');
  const mk = (id: string, desc: string) => postSimple(exec, {
    id, ledgerId: 'lt', accountId: 'a-dh', amount: -9, date: '2026-06-05', time: '09:00',
    description: desc, categoryId: 'cat-t', skipRules: true,
  });
  await mk('e-dh1', 'Tea');
  await mk('e-dh2', 'Latte');
  // Editing e-dh2 into an exact duplicate of e-dh1 must collide…
  await expect(rebuildEntry(exec, 'e-dh2', { description: 'Tea' })).rejects.toThrow('UNIQUE');
  // …and the rejected edit rolled back wholesale.
  const [e] = await exec("SELECT description, sealed FROM entries WHERE id = 'e-dh2'");
  expect(String(e.description)).toBe('Latte');
  expect(Number(e.sealed)).toBe(1);
});
