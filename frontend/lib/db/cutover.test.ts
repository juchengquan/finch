import { test, expect } from 'bun:test';
import { seededDb } from '@/lib/db/test-utils';
import { moveLegacyData, dropLegacyTables } from '@/lib/db/cutover';
import { auditLedger } from '@/lib/db/entries';
import type { Exec } from '@/lib/db/repo';

const balances = async (exec: Exec) =>
  new Map((await exec('SELECT id, current_balance AS b FROM accounts')).map((r) => [String(r.id), Number(r.b)]));

test('moveLegacyData: audit-clean, id-faithful, balance-preserving, idempotent', async () => {
  const exec = (await seededDb()).exec;
  const before = await balances(exec);
  const [{ n: txnCount }] = (await exec('SELECT COUNT(*) AS n FROM transactions')) as { n: number }[];
  const [single] = await exec("SELECT id, account_id FROM transactions WHERE transfer_group_id IS NULL AND kind IN ('income','expense') LIMIT 1");
  const [grp] = await exec('SELECT transfer_group_id AS g FROM transactions WHERE transfer_group_id IS NOT NULL LIMIT 1');
  const [tagCount] = await exec('SELECT COUNT(*) AS n FROM transaction_tags');

  const res = await moveLegacyData(exec);
  expect(res.entries).toBeGreaterThan(0);

  // Audit clean (the function itself throws on problems; assert again explicitly).
  expect(await auditLedger(exec, undefined, { checkBalances: true })).toEqual([]);

  // Id fidelity: a single's txn id is BOTH its entry id and its account-posting id.
  const sid = String(single.id);
  expect((await exec('SELECT id FROM entries WHERE id = ?', [sid])).length).toBe(1);
  const [sp] = await exec('SELECT account_id FROM postings WHERE id = ?', [sid]);
  expect(String(sp.account_id)).toBe(String(single.account_id));

  // A transfer group id is an entry with exactly two account legs keeping old txn ids.
  if (grp) {
    const gid = String(grp.g);
    const legs = await exec('SELECT id FROM postings WHERE entry_id = ? AND account_id IS NOT NULL', [gid]);
    expect(legs.length).toBe(2);
    const oldLegIds = (await exec('SELECT id FROM transactions WHERE transfer_group_id = ?', [gid])).map((r) => String(r.id)).sort();
    expect(legs.map((l) => String(l.id)).sort()).toEqual(oldLegIds);
  }

  // Tags carried over (count preserved — transfer legs collapse onto one entry,
  // so the entry_tags count can only be <= the legacy count; seed has no
  // transfer-leg tags, so equality holds).
  const [etags] = await exec('SELECT COUNT(*) AS n FROM entry_tags');
  expect(Number(etags.n)).toBe(Number(tagCount.n));

  // Balances preserved exactly (recomputed from postings inside the move).
  const after = await balances(exec);
  for (const [id, b] of before) expect(after.get(id)).toBe(b);

  // Idempotent: a re-run changes nothing.
  const [e1] = await exec('SELECT COUNT(*) AS n FROM entries');
  const [p1] = await exec('SELECT COUNT(*) AS n FROM postings');
  await moveLegacyData(exec);
  const [e2] = await exec('SELECT COUNT(*) AS n FROM entries');
  const [p2] = await exec('SELECT COUNT(*) AS n FROM postings');
  expect(Number(e2.n)).toBe(Number(e1.n));
  expect(Number(p2.n)).toBe(Number(p1.n));

  void txnCount;
});

test('moveLegacyData maps transfers, strays, splits, F3 rows, and residue ids', async () => {
  const exec = (await seededDb()).exec;
  const now = "datetime('now')";
  const addAcct = (id: string, ccy: string) =>
    exec(
      `INSERT INTO accounts (id,ledger_id,group_id,name,type,currency,current_balance,opening_balance,opening_balance_base,sort_order,include_in_net_worth,is_active,created_at,updated_at)
       VALUES ('${id}','personal',NULL,'${id}','savings','${ccy}',0,0,0,0,1,1,${now},${now})`,
    );
  await addAcct('a-tx1', 'SGD');
  await addAcct('a-tx2', 'SGD');
  await addAcct('a-tx3', 'USD');
  await addAcct('a-cm', 'USD');
  const txCols =
    '(id,ledger_id,account_id,date,time,amount,amount_base,exchange_rate,description,category_id,counterparty_id,transfer_group_id,refunded_transaction_id,kind,status,confirmed_at,source_template_id,currency,notes,cleared_at,applied_rule_ids,reviewed_at,created_at,updated_at)';

  // (a) Same-currency transfer: group tg-x with two legs.
  await exec(
    `INSERT INTO transfer_groups (id,ledger_id,from_currency,to_currency,exchange_rate,notes,created_at,updated_at)
     VALUES ('tg-x','personal','SGD','SGD',1,'note-x',${now},${now})`,
  );
  await exec(
    `INSERT INTO transactions ${txCols} VALUES
     ('t-xa','personal','a-tx1','2026-05-01',NULL,-80,-59.2,0.74,'Transfer to a-tx2',NULL,NULL,'tg-x',NULL,'transfer','confirmed',${now},NULL,'SGD',NULL,NULL,NULL,NULL,${now},${now}),
     ('t-xb','personal','a-tx2','2026-05-01',NULL,80,59.2,0.74,'Transfer from a-tx1',NULL,NULL,'tg-x',NULL,'transfer','confirmed',${now},NULL,'SGD',NULL,NULL,NULL,NULL,${now},${now})`,
  );

  // (b) Pinned cross-currency transfer with a base residue: tg-xc.
  await exec(
    `INSERT INTO transfer_groups (id,ledger_id,from_currency,to_currency,exchange_rate,notes,created_at,updated_at)
     VALUES ('tg-xc','personal','SGD','USD',0.7444,NULL,${now},${now})`,
  );
  await exec(
    `INSERT INTO transactions ${txCols} VALUES
     ('t-xca','personal','a-tx1','2026-05-02',NULL,-135,-100,0.7407,'Transfer to a-tx3',NULL,NULL,'tg-xc',NULL,'transfer','confirmed',${now},NULL,'SGD',NULL,NULL,NULL,NULL,${now},${now}),
     ('t-xcb','personal','a-tx3','2026-05-02',NULL,100.5,100.5,1,'Transfer from a-tx1',NULL,NULL,'tg-xc',NULL,'transfer','confirmed',${now},NULL,'USD',NULL,NULL,NULL,NULL,${now},${now})`,
  );

  // (c) Orphan transfer leg: a 1-leg group → stray → re-kinded adjustment.
  await exec(
    `INSERT INTO transfer_groups (id,ledger_id,from_currency,to_currency,exchange_rate,notes,created_at,updated_at)
     VALUES ('tg-dead','personal','SGD','SGD',1,NULL,${now},${now})`,
  );
  await exec(
    `INSERT INTO transactions ${txCols} VALUES
     ('t-stray','personal','a-tx1','2026-05-03',NULL,-7,-5.18,0.74,'half a transfer',NULL,NULL,'tg-dead',NULL,'transfer','confirmed',${now},NULL,'SGD',NULL,NULL,NULL,NULL,${now},${now})`,
  );

  // (d) Split expense with a cleared flag.
  await exec(
    `INSERT INTO transactions ${txCols} VALUES
     ('t-sx','personal','a-tx2','2026-05-04','09:00',-100,-74,0.74,'split shop','food',NULL,NULL,NULL,'expense','confirmed',${now},NULL,'SGD',NULL,${now},NULL,NULL,${now},${now})`,
  );
  await exec(
    `INSERT INTO transaction_splits (id,transaction_id,category_id,amount,amount_base,description,sort_order) VALUES
     ('t-sx-s0','t-sx','food',-60,-44.4,'groceries',0),
     ('t-sx-s1','t-sx',NULL,-40,-29.6,NULL,1)`,
  );

  // (e) F3 row: SGD-denominated row on a USD account.
  await exec(
    `INSERT INTO transactions ${txCols} VALUES
     ('t-f3','personal','a-cm','2026-05-05',NULL,-50,-37,0.74,'foreign row','food',NULL,NULL,NULL,'expense','confirmed',${now},NULL,'SGD',NULL,NULL,NULL,NULL,${now},${now})`,
  );

  await moveLegacyData(exec);
  expect(await auditLedger(exec, undefined, { checkBalances: true })).toEqual([]);

  // (a) transfer: entry id = group id, two account legs keep txn ids + memos.
  const [te] = await exec("SELECT kind, description FROM entries WHERE id = 'tg-x'");
  expect(String(te.kind)).toBe('transfer');
  const tlegs = await exec("SELECT id, memo FROM postings WHERE entry_id = 'tg-x' AND account_id IS NOT NULL ORDER BY id");
  expect(tlegs.map((l) => String(l.id))).toEqual(['t-xa', 't-xb']);
  expect(String(tlegs[0].memo)).toBe('Transfer to a-tx2');

  // (b) pinned cross-ccy: residue leg with the canonical `${entryId}-fx` id.
  const [fx] = await exec("SELECT id, amount_base FROM postings WHERE entry_id = 'tg-xc' AND account_id IS NULL");
  expect(String(fx.id)).toBe('tg-xc-fx');
  expect(Number(fx.amount_base)).toBe(-0.5);

  // (c) stray leg re-kinded to adjustment with an equity leg.
  const [se] = await exec("SELECT kind FROM entries WHERE id = 't-stray'");
  expect(String(se.kind)).toBe('adjustment');
  const eq = await exec(
    "SELECT c.system AS s FROM postings p JOIN categories c ON c.id = p.category_id WHERE p.entry_id = 't-stray' AND p.account_id IS NULL",
  );
  expect(String(eq[0].s)).toBe('adjustment');

  // (d) splits: ids preserved, signs negated, cleared flag carried.
  const slegs = await exec("SELECT id, amount_base, memo FROM postings WHERE entry_id = 't-sx' AND account_id IS NULL ORDER BY sort_order");
  expect(slegs.map((l) => String(l.id))).toEqual(['t-sx-s0', 't-sx-s1']);
  expect(slegs.map((l) => Number(l.amount_base))).toEqual([44.4, 29.6]);
  expect(String(slegs[0].memo)).toBe('groceries');
  const [sleg] = await exec("SELECT cleared_at FROM postings WHERE id = 't-sx'");
  expect(sleg.cleared_at).not.toBeNull();

  // (e) F3: re-denominated account leg keeps the original for display.
  const [f3] = await exec("SELECT amount, currency, orig_amount, orig_currency FROM postings WHERE id = 't-f3'");
  expect(String(f3.currency)).toBe('USD');
  expect(Number(f3.orig_amount)).toBe(-50);
  expect(String(f3.orig_currency)).toBe('SGD');
});

test('dropLegacyTables removes the legacy surface', async () => {
  const exec = (await seededDb()).exec;
  await moveLegacyData(exec);
  await dropLegacyTables(exec);
  const left = await exec(
    "SELECT name FROM sqlite_master WHERE name IN ('transactions','transfer_groups','transaction_splits','transaction_tags','transaction_attachments','transactions_fts')",
  );
  expect(left.length).toBe(0);
  // Entries survive and the books still audit clean.
  expect(await auditLedger(exec, undefined, { checkBalances: true })).toEqual([]);
});
