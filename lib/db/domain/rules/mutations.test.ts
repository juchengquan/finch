import { test, expect } from 'bun:test';
import { applyMutation } from '@/lib/db/mutate';
import { seededDb } from '@/lib/db/core/test-utils';
import type { Condition, Action } from '@/lib/rules/types';

// backfillRule has the same LIMIT-1-rebuild hazard as setTransactionSplits and
// bulkRecategorize: a split-tender entry has exactly one category leg, so the
// pre-existing `catLegs.length < 2` gate never skips it, and the categorize
// would silently drop every account leg but the one LIMIT 1 fetches. A batch
// backfill must skip just this entry's re-categorization and keep going, not
// abort the whole run. Same seeding rationale as the transactions-mutations
// multi-account tests: no web write path produces this shape today (Task 1's
// shape relaxation was iOS-only), so the fixture is seeded directly at the SQL
// layer, bypassing postEntry.
test('backfillRule on a multi-account entry is skipped and keeps both legs', async () => {
  const { exec } = await seededDb();
  const [chk] = await exec("SELECT currency FROM accounts WHERE id = 'chk'");
  const [sav] = await exec("SELECT currency FROM accounts WHERE id = 'sav'");
  const entryId = 'e-multi-acct-backfill-test';
  await exec(
    `INSERT INTO entries (id,ledger_id,date,description,kind,status,confirmed_at,sealed,created_at,updated_at)
     VALUES (?,'personal','2026-06-01','Market','expense','confirmed',datetime('now'),0,datetime('now'),datetime('now'))`,
    [entryId],
  );
  await exec(
    `INSERT INTO postings (id,entry_id,account_id,category_id,amount,currency,amount_base,exchange_rate,sort_order)
     VALUES (?,?,?,NULL,-60,?,-60,1,0)`,
    ['p-multi-bf-1', entryId, 'chk', String(chk.currency)],
  );
  await exec(
    `INSERT INTO postings (id,entry_id,account_id,category_id,amount,currency,amount_base,exchange_rate,sort_order)
     VALUES (?,?,?,NULL,-40,?,-40,1,1)`,
    ['p-multi-bf-2', entryId, 'sav', String(sav.currency)],
  );
  await exec(
    `INSERT INTO postings (id,entry_id,account_id,category_id,amount,currency,amount_base,exchange_rate,sort_order)
     VALUES (?,?,NULL,'food',100,'USD',100,1,2)`,
    ['p-multi-bf-cat', entryId],
  );
  await exec('UPDATE entries SET sealed = 1 WHERE id = ?', [entryId]); // fires tr_entry_seal — confirms the fixture balances

  const condition: Condition = { field: 'merchant', op: 'contains', value: 'Market' };
  const actions: Action[] = [{ type: 'set_category', categoryId: 'misc' }];
  await applyMutation(exec, 'createRule', {
    id: 'r-multi-acct', ledgerId: 'personal', name: 'Market→misc', condition, actions,
  });

  await applyMutation(exec, 'backfillRule', { id: 'r-multi-acct' });

  const acctLegs = await exec(
    'SELECT amount_base FROM postings WHERE entry_id = ? AND account_id IS NOT NULL',
    [entryId],
  );
  expect(acctLegs.length).toBe(2);
  const total = acctLegs.reduce((s, r) => s + Number(r.amount_base), 0);
  expect(total).toBeCloseTo(-100, 2);
  const [catRow] = await exec(
    'SELECT category_id AS c FROM postings WHERE entry_id = ? AND category_id IS NOT NULL',
    [entryId],
  );
  expect(String(catRow.c)).toBe('food'); // untouched — recategorization was skipped for this entry
});
