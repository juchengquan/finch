import { test, expect } from 'bun:test';
import { newDb, addAccount, rawEntry, rawLeg, seal } from './entries.test';
import { postEntry, auditLedger } from './core/entries';
import { listTransactions } from './queries/transactions';
import type { Exec } from './core/repo';

const createSplitRule = (
  exec: Exec,
  id: string,
  ledgerId: string,
  merchant: string,
  splits: Array<{ categoryId: string; fraction: number }>,
) => exec(
  `INSERT INTO rules (id,ledger_id,name,priority,condition,actions,is_active,run_on_edit,created_at,updated_at)
   VALUES (?,?,?,100,?,?,1,0,datetime('now'),datetime('now'))`,
  [
    id, ledgerId, `split ${merchant}`,
    JSON.stringify({ field: 'merchant', op: 'contains', value: merchant }),
    JSON.stringify([{ type: 'split', splits }]),
  ],
);

test('a purchase paid from two accounts is a legal shape', async () => {
  const exec = await newDb();
  await addAccount(exec, 'card', 'SGD', 'personal');
  await addAccount(exec, 'cash', 'SGD', 'personal');

  await postEntry(exec, {
    ledgerId: 'personal', date: '2026-06-01', time: '12:00',
    description: 'Market', kind: 'expense',
    legs: [
      { accountId: 'card', amount: -60 },
      { accountId: 'cash', amount: -40 },
      { categoryId: 'food', amountBase: 100 },
    ],
  });

  const problems = await auditLedger(exec, 'personal');
  expect(problems.filter((p) => p.code === 'kind-shape')).toEqual([]);
});

// This can't be built through postEntry: validateShape's `.transfer` branch
// is untouched by this task (I7 still pins transfers at exactly two account
// legs) and throws `error.transfer.twoLegs` before any row is written — the
// same write-path guard iOS's MultiAccountShapeTests ran into (see task-1's
// report). So the illegal shape is built directly via raw SQL + a manual
// seal (tr_entry_seal only checks balance/count, no per-kind opinion), the
// same technique iOS's audit-only test uses, to prove the audit clause
// alone still rejects it.
test('a transfer with three account legs is still a defect', async () => {
  const exec = await newDb();
  await addAccount(exec, 'a', 'SGD', 'personal');
  await addAccount(exec, 'b', 'SGD', 'personal');
  await addAccount(exec, 'c', 'SGD', 'personal');

  await rawEntry(exec, 'e-sweep', 'transfer');
  await rawLeg(exec, 'p-sweep-a', 'e-sweep', 'a', null, -100);
  await rawLeg(exec, 'p-sweep-b', 'e-sweep', 'b', null, 40);
  await rawLeg(exec, 'p-sweep-c', 'e-sweep', 'c', null, 60);
  await seal(exec, 'e-sweep');

  const problems = await auditLedger(exec, 'personal');
  expect(problems.some((p) => p.code === 'kind-shape')).toBe(true);
});

// Split tender means the refund positivity check must cover EVERY account
// leg, not just acct[0]. Card leg (first) is positive and would pass the old
// `acct[0].amount <= 0` check trivially; cash (second) is negative — the
// exact shape the old code would have waved through.
test('a refund across two accounts needs every leg positive, not just the first', async () => {
  const exec = await newDb();
  await addAccount(exec, 'card', 'SGD', 'personal');
  await addAccount(exec, 'cash', 'SGD', 'personal');

  await expect(postEntry(exec, {
    ledgerId: 'personal', date: '2026-06-01', time: '12:10',
    description: 'Bad refund', kind: 'refund', skipRules: true,
    legs: [
      { accountId: 'card', amount: 60 },
      { accountId: 'cash', amount: -40 },
      { categoryId: 'food', amountBase: -20 },
    ],
  })).rejects.toThrow('A refund must be positive');
});

// Mirrors iOS's MultiAccountRulesTests: a splits rule must distribute over
// the TOTAL of the account legs (100), not the first one (60), or the entry
// can't balance. Totals alone can't discriminate this — appendResidue
// force-balances any shortfall into a sys:fx equity leg, which is itself a
// category leg, so the buggy first-leg-only path's food=42/shop=18/fx=40 and
// the correct path's food=70/shop=30 both sum to 100. Assert per-category.
test('a splits rule on a two-account entry distributes over the total, not the first leg', async () => {
  const exec = await newDb();
  // Both accounts in the ledger's own base (USD) — no fx conversion in play,
  // so the asserted amounts are exact, not rate-dependent.
  await addAccount(exec, 'card', 'USD', 'personal');
  await addAccount(exec, 'cash', 'USD', 'personal');
  await createSplitRule(exec, 'rule-split2', 'personal', 'Market', [
    { categoryId: 'food', fraction: 0.7 },
    { categoryId: 'shop', fraction: 0.3 },
  ]);

  const { entryId } = await postEntry(exec, {
    ledgerId: 'personal', date: '2026-06-01', time: '12:15',
    description: 'Market', kind: 'expense',
    legs: [
      { accountId: 'card', amount: -60 },
      { accountId: 'cash', amount: -40 },
      { categoryId: 'food', amountBase: 100 },
    ],
  });

  const rows = await exec(
    'SELECT category_id, ROUND(amount_base, 2) AS b FROM postings WHERE entry_id = ? AND account_id IS NULL',
    [entryId],
  );
  const byCat = new Map(rows.map((r) => [String(r.category_id), Number(r.b)]));
  expect(byCat.get('food')).toBeCloseTo(70, 2);
  expect(byCat.get('shop')).toBeCloseTo(30, 2);
  const fxLegs = await exec(
    `SELECT COUNT(*) AS n FROM postings p JOIN categories c ON c.id = p.category_id
      WHERE p.entry_id = ? AND c.system = 'fx'`,
    [entryId],
  );
  expect(Number(fxLegs[0].n)).toBe(0);
});

// Mirrors iOS's mixed-currency rules test (Task 3 fix round 1): the
// synthetic Tx used for rule MATCHING must be currency-coherent. -50 USD +
// -50 EUR (EUR rate 1.10) sums to a base total of -105, but a raw
// mixed-currency native sum would be -100 — not a real quantity in any
// currency. A threshold of 101 sits strictly between the two, so this only
// fires if the engine used the coherent base total, not the raw native sum.
test('a rule condition matches the base-currency total across mixed-currency legs, not the raw native sum', async () => {
  const exec = await newDb();
  await addAccount(exec, 'usd-acct', 'USD', 'personal');
  await addAccount(exec, 'eur-acct', 'EUR', 'personal');
  await exec(
    "INSERT OR REPLACE INTO exchange_rates (date,currency,rate,source) VALUES ('2026-06-01','EUR',1.10,'manual')",
  );
  await exec(
    `INSERT INTO rules (id,ledger_id,name,priority,condition,actions,is_active,run_on_edit,created_at,updated_at)
     VALUES ('rule-mixed','personal','mixed ccy',100,?,?,1,0,datetime('now'),datetime('now'))`,
    [
      JSON.stringify({ field: 'amount', op: 'gte', value: 101 }),
      JSON.stringify([{ type: 'mark_reviewed' }]),
    ],
  );

  const { entryId } = await postEntry(exec, {
    ledgerId: 'personal', date: '2026-06-01', time: '13:00',
    description: 'Trip supplies', kind: 'expense',
    legs: [
      { accountId: 'usd-acct', amount: -50 },
      { accountId: 'eur-acct', amount: -50 },
      { categoryId: 'food', amountBase: 105 },
    ],
  });

  const [row] = await exec('SELECT reviewed_at FROM entries WHERE id = ?', [entryId]);
  expect(row.reviewed_at).not.toBeNull();
});

// Mirrors iOS's MultiAccountShapeTests projection pair: `enrichLegTxs` must
// key transferGroupId off `kind`, not the account-leg count — since split
// tender, `acct >= 2` no longer implies transfer.
test('a split-tender expense across two accounts is not presented as a transfer', async () => {
  const exec = await newDb();
  await addAccount(exec, 'card', 'USD', 'personal');
  await addAccount(exec, 'cash', 'USD', 'personal');

  await postEntry(exec, {
    ledgerId: 'personal', date: '2026-06-01', time: '14:00',
    description: 'Market run', kind: 'expense', skipRules: true,
    legs: [
      { accountId: 'card', amount: -60 },
      { accountId: 'cash', amount: -40 },
      { categoryId: 'food', amountBase: 100 },
    ],
  });

  const rows = (await listTransactions(exec, { ledgerId: 'personal' }))
    .filter((t) => t.merchant === 'Market run');
  expect(rows.length).toBe(2);
  expect(rows.every((t) => t.transferGroupId === undefined)).toBe(true);
});

// A genuine transfer must keep its grouping.
test('a genuine two-account transfer still carries transferGroupId', async () => {
  const exec = await newDb();
  await addAccount(exec, 'from-acct', 'USD', 'personal');
  await addAccount(exec, 'to-acct', 'USD', 'personal');

  await postEntry(exec, {
    ledgerId: 'personal', date: '2026-06-02', time: '09:00',
    description: 'Move funds', kind: 'transfer', skipRules: true,
    legs: [
      { accountId: 'from-acct', amount: -50 },
      { accountId: 'to-acct', amount: 50 },
    ],
  });

  const rows = (await listTransactions(exec, { ledgerId: 'personal' }))
    .filter((t) => t.merchant === 'Move funds');
  expect(rows.length).toBe(2);
  expect(rows.every((t) => t.transferGroupId != null)).toBe(true);
});
