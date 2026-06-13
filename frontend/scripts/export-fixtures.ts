// frontend/scripts/export-fixtures.ts — Phase 1.0 fixture-oracle generator.
//
// (1) Selector fixtures: imports the deterministic CASES, computes each case's
//     `expected` by running the REAL web selector on its `input`, and serializes
//     the result to the JSON the Swift ParityTests target reads.
// (2) Audit fixtures: builds one corrupt in-memory DB per AuditProblem.code,
//     runs the REAL `auditLedger` to capture the expected problem set, and
//     `VACUUM INTO`s a `<code>.sqlite3` the Swift audit-parity test opens.
//
// Run from frontend/:  bun scripts/export-fixtures.ts
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { CASES, type SelectorCase } from '@/lib/select.fixtures';
import {
  accountBalance, selectTransactions, categorySpend, budgetProgress,
  cycleWindow, merchantStats, anomalyScore, type MerchantStats,
} from '@/lib/select';
import { openDb, execFor, applyPragmaBootstrap } from '@/lib/db/core/driver';
import { applySchema } from '@/lib/db/core/schema';
import { auditLedger, postSimple, ensureSystemCategories } from '@/lib/db/core/entries';
import { projectState } from '@/lib/db/state';
import type { Exec } from '@/lib/db/core/repo';
import type { Tx } from '@/lib/store';
import type { AccountRow } from '@/lib/db/domain/accounts/types';
import type { ListOptions } from '@/lib/db/domain/transactions/types';
import type { BudgetRow } from '@/lib/db/domain/budgets/types';

// Canonical fixture root (single spelling, repo-root `ios/`). scripts/ lives at
// frontend/scripts, so the repo root is two levels up.
const OUT = path.join(
  import.meta.dir, '..', '..', 'ios', 'FinchCore', 'Tests', 'ParityTests', 'Fixtures',
);

// ───────────────────────── selector fixtures ─────────────────────────

/** `JSON.stringify` serializes a `Map` as `{}` — but `merchantStats` RETURNS a
 *  `Map<string, MerchantStats>`. This replacer converts any `Map` (at any depth)
 *  to a plain object before serialization. */
function mapToObjectReplacer(_key: string, value: unknown): unknown {
  return value instanceof Map ? Object.fromEntries(value) : value;
}

/** Run the real web selector for a case and return its output (the `expected`). */
function runSelector(c: SelectorCase): unknown {
  const i = c.input as Record<string, unknown>;
  switch (c.selector) {
    case 'accountBalance':     return accountBalance(i.accounts as AccountRow[], i.accountId as string);
    case 'selectTransactions': return selectTransactions(i.txns as Tx[], i.opts as ListOptions);
    case 'categorySpend':      return categorySpend(i.txns as Tx[], i.ledgerId as string, i.month as string | undefined);
    case 'budgetProgress':     return budgetProgress(i.budget as BudgetRow, i.txns as Tx[], i.today as string, i.categories as { id: string; parentId: string | null }[]);
    case 'cycleWindow':        return cycleWindow(i.frequency as string, i.startDate as string, i.today as string, i.endDate as string | null, i.isRecurring as number | undefined);
    case 'merchantStats':      return merchantStats(i.txns as Tx[], i.ledgerId as string);
    case 'anomalyScore': {
      // `stats` is authored as a plain object; rebuild it into the Map the selector expects.
      const stats = new Map<string, MerchantStats>(Object.entries(i.stats as Record<string, MerchantStats>));
      return anomalyScore(i.tx as Tx, stats, i.opts as { minCount?: number; threshold?: number } | undefined);
    }
  }
}

async function writeSelectorFixtures(): Promise<number> {
  for (const c of CASES) {
    const expected = runSelector(c);
    const fixture = { name: c.name, selector: c.selector, input: c.input, expected };
    const dir = path.join(OUT, 'selectors', c.selector);
    await fs.mkdir(dir, { recursive: true });
    await fs.writeFile(
      path.join(dir, `${c.selector}__${c.name}.json`),
      JSON.stringify(fixture, mapToObjectReplacer, 2) + '\n',
    );
  }
  return CASES.length;
}

// ───────────────────────── audit fixtures ─────────────────────────

// Minimal valid-insert helpers (the raw SQL from entries.test.ts's helpers).
// Corruption entries are status='pending' so the confirmed-only balance-drift
// check doesn't fire on every fixture.
const addLedger = (x: Exec, id: string, base: string) =>
  x("INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES (?,?,?,0,datetime('now'),datetime('now'))", [id, id, base]);
const addAccount = (x: Exec, id: string, ledgerId: string, currency = 'SGD', balance = 0) =>
  x(`INSERT INTO accounts (id,ledger_id,group_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
     VALUES (?,?,NULL,?,'savings',?,?,0,1,1,datetime('now'),datetime('now'))`, [id, ledgerId, id, currency, balance]);
const addCategory = (x: Exec, id: string, ledgerId: string, kind = 'expense') =>
  x("INSERT INTO categories (id,ledger_id,parent_id,name,kind,icon,color,sort_order,system,created_at,updated_at) VALUES (?,?,NULL,?,?,NULL,NULL,0,NULL,datetime('now'),datetime('now'))", [id, ledgerId, id, kind]);
const rawEntry = (x: Exec, id: string, ledgerId: string, kind = 'expense') =>
  x(`INSERT INTO entries (id,ledger_id,date,description,kind,status,sealed,created_at,updated_at)
     VALUES (?,?,'2026-06-01','raw',?,'pending',0,datetime('now'),datetime('now'))`, [id, ledgerId, kind]);
const rawLeg = (x: Exec, id: string, entryId: string, accountId: string | null, categoryId: string | null, amount: number, base: number, sort: number, currency = 'SGD') =>
  x(`INSERT INTO postings (id,entry_id,account_id,category_id,amount,currency,amount_base,exchange_rate,sort_order)
     VALUES (?,?,?,?,?,?,?,1,?)`, [id, entryId, accountId, categoryId, amount, currency, base, sort]);
const seal = (x: Exec, id: string) => x('UPDATE entries SET sealed = 1 WHERE id = ?', [id]);

/** Fresh in-memory DB with the canonical schema + a clean base ledger
 *  (l1 base SGD, accounts a1/a2 SGD, category c1 expense). */
async function freshAuditDb(): Promise<{ x: Exec; close: () => void }> {
  const driver = await openDb(':memory:');
  applyPragmaBootstrap(driver);
  const x = execFor(driver);
  await applySchema(x);
  await addLedger(x, 'l1', 'SGD');
  await addAccount(x, 'a1', 'l1');
  await addAccount(x, 'a2', 'l1');
  await addCategory(x, 'c1', 'l1');
  return { x, close: () => driver.close() };
}

// One corrupt DB per code. Each trips its target code (+ inherent co-codes,
// e.g. unbalanced ⇒ trial-balance, single/zero-account-leg ⇒ kind-shape); the
// captured `expected` is whatever the real auditLedger returns.
const RECIPES: { code: string; corrupt: (x: Exec) => Promise<void> }[] = [
  { code: 'unsealed', corrupt: async (x) => {                 // balanced but never sealed
    await rawEntry(x, 'e1', 'l1');
    await rawLeg(x, 'p1', 'e1', 'a1', null, -10, -10, 0);
    await rawLeg(x, 'p2', 'e1', null, 'c1', 10, 10, 1);
  } },
  { code: 'unbalanced', corrupt: async (x) => {               // sealed, postings sum ≠ 0
    await rawEntry(x, 'e1', 'l1');
    await rawLeg(x, 'p1', 'e1', 'a1', null, -10, -10, 0);
    await rawLeg(x, 'p2', 'e1', null, 'c1', 5, 5, 1);          // sum_base = -5
    await x('DROP TRIGGER tr_entry_seal');                     // the seal trigger would reject this
    await seal(x, 'e1');
  } },
  { code: 'too-few-legs', corrupt: async (x) => {             // sealed, only 1 leg
    await rawEntry(x, 'e1', 'l1');
    await rawLeg(x, 'p1', 'e1', 'a1', null, 0, 0, 0);
    await x('DROP TRIGGER tr_entry_seal');                     // seal rejects < 2 legs
    await seal(x, 'e1');
  } },
  { code: 'no-account-leg', corrupt: async (x) => {           // sealed, 2 category legs, 0 account legs
    await rawEntry(x, 'e1', 'l1');
    await rawLeg(x, 'p1', 'e1', null, 'c1', 5, 5, 0);
    await rawLeg(x, 'p2', 'e1', null, 'c1', -5, -5, 1);
    await x('DROP TRIGGER tr_entry_seal');                     // seal rejects 0 account legs
    await seal(x, 'e1');
  } },
  { code: 'currency-mismatch', corrupt: async (x) => {        // USD leg on an SGD account
    await x('DROP TRIGGER tr_post_currency_insert');
    await rawEntry(x, 'e1', 'l1');
    await rawLeg(x, 'p1', 'e1', 'a1', null, -7, -7, 0, 'USD'); // a1 is SGD
    await rawLeg(x, 'p2', 'e1', null, 'c1', 7, 7, 1, 'SGD');
    await seal(x, 'e1');
  } },
  { code: 'cross-ledger', corrupt: async (x) => {             // posting on an account in another ledger
    await addLedger(x, 'l2', 'SGD');
    await addAccount(x, 'a2x', 'l2');
    await rawEntry(x, 'e1', 'l1');
    await rawLeg(x, 'p1', 'e1', 'a2x', null, -10, -10, 0);     // a2x belongs to l2
    await rawLeg(x, 'p2', 'e1', null, 'c1', 10, 10, 1);
    await seal(x, 'e1');
  } },
  { code: 'base-identity', corrupt: async (x) => {            // base-currency leg where amount ≠ amount_base
    await rawEntry(x, 'e1', 'l1');
    await rawLeg(x, 'p1', 'e1', 'a1', null, -10, -9, 0);       // SGD = base, amount -10 ≠ base -9
    await rawLeg(x, 'p2', 'e1', null, 'c1', 9, 9, 1);          // keeps the entry balanced (-9+9=0)
    await seal(x, 'e1');
  } },
  { code: 'kind-shape', corrupt: async (x) => {               // a 'transfer' with the wrong leg shape
    await rawEntry(x, 'e1', 'l1', 'transfer');
    await rawLeg(x, 'p1', 'e1', 'a1', null, -10, -10, 0);      // transfer needs 2 account legs, 0 category
    await rawLeg(x, 'p2', 'e1', null, 'c1', 10, 10, 1);
    await seal(x, 'e1');
  } },
  { code: 'trial-balance', corrupt: async (x) => {            // ledger total ≠ 0 (an unbalanced entry)
    await rawEntry(x, 'e1', 'l1');
    await rawLeg(x, 'p1', 'e1', 'a1', null, -10, -10, 0);
    await rawLeg(x, 'p2', 'e1', null, 'c1', 7, 7, 1);          // sum_base = -3
    await x('DROP TRIGGER tr_entry_seal');
    await seal(x, 'e1');
  } },
  { code: 'balance-drift', corrupt: async (x) => {            // cached balance ≠ derived
    await x("UPDATE accounts SET current_balance = 123 WHERE id = 'a1'");
  } },
];

async function writeAuditFixtures(): Promise<{ count: number; covered: Set<string> }> {
  const dir = path.join(OUT, 'audit');
  await fs.mkdir(dir, { recursive: true });
  const covered = new Set<string>();
  for (const r of RECIPES) {
    const { x, close } = await freshAuditDb();
    await r.corrupt(x);
    const problems = await auditLedger(x, 'l1', { checkBalances: true });
    problems.forEach((p) => covered.add(p.code));
    // VACUUM INTO requires the target not to exist.
    const dbPath = path.join(dir, `${r.code}.sqlite3`);
    await fs.rm(dbPath, { force: true });
    await x('VACUUM INTO ?', [dbPath]);
    await fs.writeFile(
      path.join(dir, `${r.code}__corrupt.json`),
      JSON.stringify({ code: r.code, expected: problems }, null, 2) + '\n',
    );
    close();
  }
  return { count: RECIPES.length, covered };
}

/** Projection golden fixture (DESIGN §8.1): a real DB seeded via the chokepoint,
 *  plus the web `projectState`'s `transactions` output, for the Swift Projection
 *  parity test. */
async function writeProjectionFixture(): Promise<number> {
  const driver = await openDb(':memory:');
  applyPragmaBootstrap(driver);
  const x = execFor(driver);
  await applySchema(x);
  await addLedger(x, 'l1', 'SGD');
  await addAccount(x, 'a1', 'l1');
  await addAccount(x, 'a2', 'l1');
  await addCategory(x, 'c1', 'l1');
  await ensureSystemCategories(x, 'l1');
  // A few valid entries through the chokepoint (sealed + balanced).
  await postSimple(x, { ledgerId: 'l1', accountId: 'a1', amount: -25, date: '2026-05-01', description: 'Coffee', categoryId: 'c1', skipRules: true });
  await postSimple(x, { ledgerId: 'l1', accountId: 'a1', amount: -10, date: '2026-05-02', description: 'Lunch', categoryId: 'c1', skipRules: true });
  await postSimple(x, { ledgerId: 'l1', accountId: 'a1', amount: 100, date: '2026-05-03', description: 'Pay', categoryId: 'c1', skipRules: true });

  const state = await projectState(x);
  const dir = path.join(OUT, 'projection');
  await fs.mkdir(dir, { recursive: true });
  const dbPath = path.join(dir, 'projection.sqlite3');
  await fs.rm(dbPath, { force: true });
  await x('VACUUM INTO ?', [dbPath]);
  await fs.writeFile(path.join(dir, 'projection.json'),
    JSON.stringify({ expected: state.transactions }, null, 2) + '\n');
  driver.close();
  return state.transactions.length;
}

async function main(): Promise<void> {
  await fs.mkdir(OUT, { recursive: true });
  const sel = await writeSelectorFixtures();
  const aud = await writeAuditFixtures();
  const proj = await writeProjectionFixture();
  console.log(`  projection fixture: ${proj} txns`);
  const allCodes = ['unsealed', 'unbalanced', 'too-few-legs', 'no-account-leg', 'currency-mismatch',
    'cross-ledger', 'base-identity', 'kind-shape', 'trial-balance', 'balance-drift'];
  const missing = allCodes.filter((c) => !aud.covered.has(c));
  console.log(`export-fixtures: wrote ${sel} selector fixtures + ${aud.count} audit fixtures → ${path.relative(process.cwd(), OUT)}`);
  console.log(`  audit codes covered: ${[...aud.covered].sort().join(', ')}`);
  if (missing.length) { console.error(`  !! UNCOVERED audit codes: ${missing.join(', ')}`); process.exit(2); }
}

main().catch((e) => { console.error(e); process.exit(1); });
