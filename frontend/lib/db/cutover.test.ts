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
