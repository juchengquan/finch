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
import * as os from 'node:os';
import { CASES, type SelectorCase } from '@/lib/select.fixtures';
import {
  accountBalance, selectTransactions, categorySpend, budgetProgress,
  cycleWindow, merchantStats, anomalyScore, type MerchantStats,
  currentMonth, prevMonth, monthlySpending, dailySpending,
  monthlyCashflow, topCategoryDeltas,
  incomeCategoryFlow, recentExpenses, findDuplicate, suggestCategory, weeklyDigest,
  netWorthByMonth, netWorthExplained, balanceSeries, netWorthSeries,
  netWorthByAccountType, selectTransfers, monthForecast, accountForecast,
  holdingsForAccount, holdingValue, holdingGainLoss, holdingsValueForAccount,
  investmentAccountTotal, unrealizedFx,
} from '@/lib/select';
import type { ScheduledTemplate } from '@/lib/store';
import type { Holding } from '@/lib/db/domain/holdings/types';
import { openDb, execFor, applyPragmaBootstrap } from '@/lib/db/core/driver';
import { applyMutation } from '@/lib/db/mutate';
import { applySchema, SCHEMA_VERSION } from '@/lib/db/core/schema';
import { buildPack } from '@/lib/db/core/pack';
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
    // Phase 1.5 — batch 1
    case 'currentMonth':      return currentMonth(i.txns as Tx[], i.ledgerId as string | undefined);
    case 'prevMonth':         return prevMonth(i.month as string);
    case 'monthlySpending':   return monthlySpending(i.txns as Tx[], i.ledgerId as string, i.endMonth as string, i.n as number);
    case 'dailySpending':     return dailySpending(i.txns as Tx[], i.ledgerId as string, i.endDate as string, i.n as number);
    case 'monthlyCashflow':   return monthlyCashflow(i.txns as Tx[], i.ledgerId as string, i.endMonth as string, i.n as number);
    case 'topCategoryDeltas': return topCategoryDeltas(i.txns as Tx[], i.ledgerId as string, i.curMonth as string, i.categories as { id: string; name: string }[], i.count as number | undefined);
    // Phase 1.5 — batch 2
    case 'incomeCategoryFlow': return incomeCategoryFlow(i.txns as Tx[], i.categories as { id: string; name: string; color?: string | null }[], i.ledgerId as string, i.month as string, i.topN as number | undefined);
    case 'recentExpenses':     return recentExpenses(i.txns as Tx[], i.ledgerId as string, i.limit as number | undefined);
    case 'findDuplicate':      return findDuplicate(i.txns as Tx[], i.ledgerId as string, i.draft as { merchant: string; amount: number; accountId: string; date: string; excludeId?: string });
    case 'suggestCategory':    return suggestCategory(i.txns as Tx[], i.ledgerId as string, i.description as string, i.counterpartyId as string | null | undefined, i.opts as { minCount?: number; minConfidence?: number } | undefined);
    case 'weeklyDigest':       return weeklyDigest(i.txns as Tx[], i.ledgerId as string, i.anchor as string);
    // Phase 1.5 — batch 3a (toBase omitted → web default identity)
    case 'netWorthByMonth':      return netWorthByMonth(i.txns as Tx[], i.accounts as AccountRow[], i.ledgerId as string, i.endMonth as string, i.n as number);
    case 'netWorthExplained':    return netWorthExplained(i.txns as Tx[], i.accounts as AccountRow[], i.ledgerId as string, i.endMonth as string, i.n as number);
    case 'balanceSeries':        return balanceSeries(i.txns as Tx[], i.accountId as string, i.currentBalance as number);
    case 'netWorthSeries':       return netWorthSeries(i.txns as Tx[], i.accounts as AccountRow[], i.ledgerId as string);
    case 'netWorthByAccountType': return netWorthByAccountType(i.accounts as AccountRow[], i.ledgerId as string);
    case 'selectTransfers':      return selectTransfers(i.txns as Tx[], i.accounts as AccountRow[], i.ledgerId as string);
    // Phase 1.5 — batch 3b
    case 'monthForecast':        return monthForecast(i.txns as Tx[], i.scheduled as ScheduledTemplate[], i.ledgerId as string, i.month as string, i.today as string);
    case 'accountForecast':      return accountForecast(i.account as AccountRow, i.scheduled as ScheduledTemplate[], i.today as string, i.horizonDays as number);
    // Phase 1.5 — batch 4 (unrealizedFx toBase = identity)
    case 'holdingsForAccount':       return holdingsForAccount(i.holdings as Holding[], i.accountId as string);
    case 'holdingValue':             return holdingValue(i.h as Holding);
    case 'holdingGainLoss':          return holdingGainLoss(i.h as Holding);
    case 'holdingsValueForAccount':  return holdingsValueForAccount(i.holdings as Holding[], i.accountId as string);
    case 'investmentAccountTotal':   return investmentAccountTotal(i.account as AccountRow, i.holdings as Holding[]);
    case 'unrealizedFx':             return unrealizedFx(i.account as AccountRow, i.txns as Tx[], (a: number) => a);
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

// ───────────────────────── round-trip .finch fixtures ─────────────────────────

// The FinchApp test target reads these (a DIFFERENT dir from the ParityTests
// OUT): a CLEAN pack `loadPack` accepts, and a DIRTY pack (one unbalanced entry)
// the audit gate must REFUSE with PackError.auditFailed.
const APP_FIX = path.join(
  import.meta.dir, '..', '..', 'ios', 'FinchApp', 'Tests', 'FinchAppTests', 'Fixtures', 'roundtrip',
);

/** VACUUM a live exec into a temp file and read its bytes (a self-contained DB). */
async function dbBytesViaVacuum(x: Exec): Promise<Uint8Array> {
  const tmp = path.join(os.tmpdir(), `finch-rt-${process.pid}-${process.hrtime.bigint()}.sqlite3`);
  await fs.rm(tmp, { force: true });
  await x('VACUUM INTO ?', [tmp]);
  const buf = await fs.readFile(tmp);
  await fs.rm(tmp, { force: true });
  return new Uint8Array(buf);
}

/** Wrap DB bytes into a `.finch` via the REAL web `buildPack`. A FIXED
 *  `exportedAt` keeps the committed pack bytes deterministic across runs. */
async function buildFinch(dbBytes: Uint8Array): Promise<Uint8Array> {
  const { bytes } = await buildPack({
    dbBytes,
    attachmentFiles: [],
    meta: { appVersion: '1.0.0', schemaVersion: SCHEMA_VERSION, exportedAt: '2026-06-14T00:00:00Z', rowCounts: {} },
  });
  return bytes;
}

async function writeRoundtripFixtures(): Promise<void> {
  await fs.mkdir(APP_FIX, { recursive: true });

  // sample.finch — a CLEAN pack (audit passes; loadPack projects + persists).
  {
    const driver = await openDb(':memory:');
    applyPragmaBootstrap(driver);
    const x = execFor(driver);
    await applySchema(x);
    await addLedger(x, 'l1', 'SGD');
    await addAccount(x, 'a1', 'l1');
    await addAccount(x, 'a2', 'l1');
    await addCategory(x, 'c1', 'l1');
    await ensureSystemCategories(x, 'l1');
    await postSimple(x, { ledgerId: 'l1', accountId: 'a1', amount: -25, date: '2026-05-01', description: 'Coffee', categoryId: 'c1', skipRules: true });
    await postSimple(x, { ledgerId: 'l1', accountId: 'a1', amount: -10, date: '2026-05-02', description: 'Lunch', categoryId: 'c1', skipRules: true });
    await postSimple(x, { ledgerId: 'l1', accountId: 'a1', amount: 100, date: '2026-05-03', description: 'Pay', categoryId: 'c1', skipRules: true });
    const problems = await auditLedger(x, 'l1', { checkBalances: true });
    if (problems.length) throw new Error(`sample.finch DB is not clean: ${JSON.stringify(problems)}`);
    await fs.writeFile(path.join(APP_FIX, 'sample.finch'), await buildFinch(await dbBytesViaVacuum(x)));
    driver.close();
  }

  // dirty.finch — one unbalanced sealed entry (legs sum to -5) → audit fails.
  {
    const driver = await openDb(':memory:');
    applyPragmaBootstrap(driver);
    const x = execFor(driver);
    await applySchema(x);
    await addLedger(x, 'l1', 'SGD');
    await addAccount(x, 'a1', 'l1');
    await addCategory(x, 'c1', 'l1');
    await x('DROP TRIGGER tr_entry_seal');          // the seal trigger would reject an unbalanced entry
    await rawEntry(x, 'e1', 'l1');
    await rawLeg(x, 'p1', 'e1', 'a1', null, -10, -10, 0);
    await rawLeg(x, 'p2', 'e1', null, 'c1', 5, 5, 1);  // sum = -5 → unbalanced
    await seal(x, 'e1');
    const problems = await auditLedger(x, 'l1', { checkBalances: true });
    if (!problems.length) throw new Error('dirty.finch DB unexpectedly passed the audit');
    await fs.writeFile(path.join(APP_FIX, 'dirty.finch'), await buildFinch(await dbBytesViaVacuum(x)));
    driver.close();
  }
}

// ───────────────────────── write-side round-trip parity ─────────────────────────

// A canonical, id-/timestamp-agnostic snapshot of the DB. Entries nest their
// postings (both minus random ids); timestamps collapse to booleans; all numbers
// render as fixed "%.6f" strings so the Swift port can compare structurally
// without float/JSON-format drift. Domain tables keep their (arg-provided) ids.
const num = (v: unknown): string | null => (v == null ? null : Number(v).toFixed(6));

async function canonicalState(x: Exec): Promise<Record<string, unknown>> {
  const rows = (sql: string, b: unknown[] = []) => x(sql, b as never);
  const entries = await rows('SELECT * FROM entries');
  const entryObjs = [];
  for (const e of entries) {
    const ps = await rows('SELECT account_id, category_id, amount, currency, amount_base, exchange_rate, orig_amount, orig_currency, memo, cleared_at, sort_order FROM postings WHERE entry_id = ? ORDER BY sort_order', [e.id]);
    entryObjs.push({
      ledger_id: e.ledger_id, date: e.date, time: e.time ?? null, description: e.description ?? null,
      kind: e.kind, status: e.status, counterparty_id: e.counterparty_id ?? null,
      refunded_entry_id: e.refunded_entry_id ?? null, source_template_id: e.source_template_id ?? null,
      notes: e.notes ?? null, applied_rule_ids: e.applied_rule_ids ?? null,
      reviewed: e.reviewed_at != null, sealed: Number(e.sealed),
      postings: ps.map((p) => ({
        account_id: p.account_id ?? null, category_id: p.category_id ?? null, amount: num(p.amount),
        currency: p.currency, amount_base: num(p.amount_base), exchange_rate: num(p.exchange_rate),
        orig_amount: num(p.orig_amount), orig_currency: p.orig_currency ?? null, memo: p.memo ?? null,
        cleared: p.cleared_at != null, sort_order: Number(p.sort_order),
      })),
    });
  }
  // Content tuple (id-free, order-independent of dictionary key order) so the
  // Swift port can reproduce the exact same entry ordering.
  const ekey = (o: { date: unknown; kind: unknown; description: unknown; postings: { account_id: unknown; category_id: unknown; amount_base: unknown }[] }) =>
    `${o.date}|${o.kind}|${o.description ?? ''}|` +
    o.postings.map((p) => `${p.account_id ?? ''}:${p.category_id ?? ''}:${p.amount_base ?? ''}`).join(';');
  entryObjs.sort((a, b) => (ekey(a) < ekey(b) ? -1 : ekey(a) > ekey(b) ? 1 : 0));

  const map = (rs: Record<string, unknown>[], cols: Record<string, (r: Record<string, unknown>) => unknown>) =>
    rs.map((r) => Object.fromEntries(Object.entries(cols).map(([k, f]) => [k, f(r)])));

  return {
    entries: entryObjs,
    ledgers: map(await rows('SELECT * FROM ledgers ORDER BY id'), { id: (r) => r.id, name: (r) => r.name, base: (r) => r.base_currency, is_default: (r) => Number(r.is_default), color: (r) => r.color ?? null, tagline: (r) => r.tagline ?? null }),
    account_groups: map(await rows('SELECT * FROM account_groups ORDER BY id'), { id: (r) => r.id, ledger_id: (r) => r.ledger_id, name: (r) => r.name, sort_order: (r) => Number(r.sort_order) }),
    accounts: map(await rows('SELECT * FROM accounts ORDER BY id'), { id: (r) => r.id, ledger_id: (r) => r.ledger_id, group_id: (r) => r.group_id ?? null, name: (r) => r.name, type: (r) => r.type, currency: (r) => r.currency, current_balance: (r) => num(r.current_balance), sort_order: (r) => Number(r.sort_order), include_in_net_worth: (r) => Number(r.include_in_net_worth), is_active: (r) => Number(r.is_active), archived: (r) => r.archived_at != null }),
    categories: map(await rows('SELECT * FROM categories ORDER BY id'), { id: (r) => r.id, ledger_id: (r) => r.ledger_id, parent_id: (r) => r.parent_id ?? null, name: (r) => r.name, kind: (r) => r.kind, system: (r) => r.system ?? null, sort_order: (r) => Number(r.sort_order) }),
    counterparties: map(await rows('SELECT * FROM counterparties ORDER BY id'), { id: (r) => r.id, ledger_id: (r) => r.ledger_id, name: (r) => r.name, is_verified: (r) => Number(r.is_verified) }),
    tags: map(await rows('SELECT * FROM tags ORDER BY id'), { id: (r) => r.id, ledger_id: (r) => r.ledger_id, name: (r) => r.name, color: (r) => r.color ?? null }),
    budgets: map(await rows('SELECT * FROM budgets ORDER BY id'), { id: (r) => r.id, ledger_id: (r) => r.ledger_id, group_id: (r) => r.group_id ?? null, name: (r) => r.name, kind: (r) => r.kind, amount: (r) => num(r.amount), saved: (r) => num(r.saved), frequency: (r) => r.frequency, start_date: (r) => r.start_date, end_date: (r) => r.end_date ?? null, is_recurring: (r) => Number(r.is_recurring), rollover: (r) => Number(r.rollover), account_ids: (r) => r.account_ids ?? null, category_ids: (r) => r.category_ids ?? null, warning_pct: (r) => num(r.warning_pct), pending_amount: (r) => num(r.pending_amount) }),
    budget_groups: map(await rows('SELECT * FROM budget_groups ORDER BY id'), { id: (r) => r.id, ledger_id: (r) => r.ledger_id, name: (r) => r.name, sort_order: (r) => Number(r.sort_order) }),
    holdings: map(await rows('SELECT * FROM holdings ORDER BY id'), { id: (r) => r.id, account_id: (r) => r.account_id, symbol: (r) => r.symbol, shares: (r) => num(r.shares), cost_basis: (r) => num(r.cost_basis), currency: (r) => r.currency, last_price: (r) => num(r.last_price) }),
    exchange_rates: map(await rows('SELECT * FROM exchange_rates ORDER BY date, currency'), { date: (r) => r.date, currency: (r) => r.currency, rate: (r) => num(r.rate), source: (r) => r.source ?? null }),
    scheduled_templates: map(await rows('SELECT * FROM scheduled_templates ORDER BY id'), { id: (r) => r.id, ledger_id: (r) => r.ledger_id, name: (r) => r.name, kind: (r) => r.kind, amount: (r) => num(r.amount), frequency: (r) => r.frequency, day_of_month: (r) => Number(r.day_of_month), account_id: (r) => r.account_id, from_account_id: (r) => r.from_account_id ?? null, start_date: (r) => r.start_date ?? null, is_active: (r) => Number(r.is_active), splits_enabled: (r) => Number(r.splits_enabled) }),
    rules: map(await rows('SELECT * FROM rules ORDER BY id'), { id: (r) => r.id, ledger_id: (r) => r.ledger_id, priority: (r) => Number(r.priority), condition: (r) => JSON.parse(String(r.condition)), actions: (r) => JSON.parse(String(r.actions)), is_active: (r) => Number(r.is_active) }),
    app_state: map(await rows('SELECT * FROM app_state ORDER BY key'), { key: (r) => r.key, value: (r) => r.value }),
  };
}

// A fixed-id base seed (raw SQL, run identically on both sides) for the entities
// whose handlers generate random ids — the ledger, the three system equity
// categories (resolved by `system` marker, so postOpening/postAdjustment REUSE
// these instead of minting random ones), the user categories, and the accounts.
// createCategory/createLedger/ensureSystemCategories mint random ids, so they
// can't be referenced by a fixed id in later steps; seeding sidesteps that and
// keeps canonicalState comparable.
const N = "datetime('now')";
const SEED_SQL: string[] = [
  `INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('personal','Personal','USD',1,${N},${N})`,
  `INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,system,created_at,updated_at) VALUES ('sys-open','personal',NULL,'Opening balance','equity',9000,'opening',${N},${N})`,
  `INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,system,created_at,updated_at) VALUES ('sys-adj','personal',NULL,'Balance adjustment','equity',9001,'adjustment',${N},${N})`,
  `INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,system,created_at,updated_at) VALUES ('sys-fx','personal',NULL,'FX gain/loss','equity',9002,'fx',${N},${N})`,
  `INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('food','personal',NULL,'Food','expense',0,${N},${N})`,
  `INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('pay','personal',NULL,'Salary','income',1,${N},${N})`,
  `INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','personal','Checking','cash','USD',0,0,1,1,${N},${N})`,
  `INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a2','personal','Savings','savings','USD',0,1,1,1,${N},${N})`,
];

/** A deterministic write-action sequence over the seeded fixed ids. Every entity
 *  it creates is either arg-id-honoring (counterparty/tag/budget/group/scheduled/
 *  rule) or an entry/posting (canonicalState nests those minus ids). No action
 *  references a randomly-generated id, so web + Swift converge on one end state. */
const WRITE_SEQUENCE: { action: string; args: Record<string, unknown> }[] = [
  { action: 'createCounterparty', args: { id: 'cp1', ledgerId: 'personal', name: 'Starbucks' } },
  { action: 'createTag', args: { id: 'tg1', ledgerId: 'personal', name: 'work', color: '#f00' } },
  { action: 'addTransaction', args: { ledgerId: 'personal', accountId: 'a1', amount: -25, merchant: 'Coffee', categoryId: 'food', date: '2026-05-01', skipRules: true } },
  { action: 'addTransaction', args: { ledgerId: 'personal', accountId: 'a1', amount: 2000, merchant: 'Pay', categoryId: 'pay', date: '2026-05-02', kind: 'income', skipRules: true } },
  { action: 'createTransfer', args: { fromAccountId: 'a1', toAccountId: 'a2', fromAmount: 500, date: '2026-05-03' } },
  { action: 'createBudget', args: { id: 'b1', ledgerId: 'personal', name: 'Food', type: 'expense', amount: 300, categoryIds: ['food'], startDate: '2026-01-01' } },
  { action: 'createBudgetGroup', args: { id: 'bg1', ledgerId: 'personal', name: 'Essentials' } },
  { action: 'contributeBudget', args: { id: 'b1', amount: 50 } },
  { action: 'setExchangeRate', args: { date: '2026-05-01', currency: 'EUR', rate: 1.1 } },
  { action: 'setDisplayCurrency', args: { ledgerId: 'personal', currency: 'USD' } },
  { action: 'createScheduled', args: { id: 's1', ledgerId: 'personal', name: 'Rent', type: 'expense', amount: 1500, frequency: 'monthly', dayOfMonth: 1, accountId: 'a1', startDate: '2026-01-01' } },
  { action: 'createRule', args: { id: 'r1', ledgerId: 'personal', name: 'Coffee', condition: { field: 'merchant', op: 'contains', value: 'coffee' }, actions: [{ type: 'set_category', categoryId: 'food' }] } },
  { action: 'adjustAccountBalance', args: { accountId: 'a2', targetBalance: 600, date: '2026-05-04' } },
  // Stateful chain: split the just-added tx (id resolved at runtime, identically
  // on both sides) — exercises setTransactionSplits against the oracle.
  { action: 'addTransaction', args: { ledgerId: 'personal', accountId: 'a1', amount: -100, merchant: 'SplitMe', categoryId: 'food', date: '2026-05-05', skipRules: true } },
  { action: 'setTransactionSplits', args: { id: '$lastAccountPosting', splits: [{ categoryId: 'food', amount: -60 }, { categoryId: 'pay', amount: -40 }] } },
  // Confirm the income tx via its account-posting id (re-uses the same chain pattern).
  { action: 'addTransaction', args: { ledgerId: 'personal', accountId: 'a1', amount: -7, merchant: 'Pending', categoryId: 'food', date: '2026-05-06', status: 'pending', skipRules: true } },
  { action: 'setReviewed', args: { id: '$lastAccountPosting', reviewed: true } },
  // Rules-on-insert: r1 (Coffee→food) exists by now; this tx omits skipRules, so
  // the postEntry hook fires — categoryId 'pay' is re-pointed to 'food' and
  // applied_rule_ids stamps 'r1'. Verified byte-for-byte against the oracle.
  { action: 'addTransaction', args: { ledgerId: 'personal', accountId: 'a1', amount: -8, merchant: 'Morning Coffee', categoryId: 'pay', date: '2026-05-07' } },
  // Cross-currency: a JPY purchase on a USD account. Exercises the foreign-
  // currency path — orig_amount/orig_currency carried, native+base derived via
  // rateToHub (a JPY rate is set first so the conversion is deterministic), plus
  // the FX residue + the write-through 'derived' USD-rate row. Verified byte-for-
  // byte against the oracle.
  { action: 'setExchangeRate', args: { date: '2026-05-08', currency: 'JPY', rate: 0.0065 } },
  { action: 'addTransaction', args: { ledgerId: 'personal', accountId: 'a1', amount: -3820, currency: 'JPY', merchant: 'Yodobashi', categoryId: 'food', date: '2026-05-08', skipRules: true } },
];

/** Resolve `$lastAccountPosting` to the most-recent account-leg posting id (the
 *  same logical row on web + Swift), so the declarative sequence can chain. */
async function resolveArgs(x: Exec, args: Record<string, unknown>): Promise<Record<string, unknown>> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(args)) {
    if (v === '$lastAccountPosting') {
      const r = await x('SELECT id FROM postings WHERE account_id IS NOT NULL ORDER BY rowid DESC LIMIT 1', []);
      out[k] = String(r[0].id);
    } else out[k] = v;
  }
  return out;
}

async function writeWriteParityFixture(): Promise<void> {
  const driver = await openDb(':memory:');
  applyPragmaBootstrap(driver);
  const x = execFor(driver);
  await applySchema(x);
  for (const sql of SEED_SQL) await x(sql, []);
  for (const step of WRITE_SEQUENCE) await applyMutation(x, step.action, await resolveArgs(x, step.args));
  const expected = await canonicalState(x);
  const dir = path.join(OUT, 'writeparity');
  await fs.mkdir(dir, { recursive: true });
  await fs.writeFile(path.join(dir, 'sequence.json'),
    JSON.stringify({ seedSql: SEED_SQL, sequence: WRITE_SEQUENCE, expected }, null, 2) + '\n');
  driver.close();
}

async function main(): Promise<void> {
  await fs.mkdir(OUT, { recursive: true });
  await writeWriteParityFixture();
  console.log('  write-parity fixture: sequence.json');
  const sel = await writeSelectorFixtures();
  const aud = await writeAuditFixtures();
  const proj = await writeProjectionFixture();
  await writeRoundtripFixtures();
  console.log('  round-trip fixtures: sample.finch + dirty.finch');
  console.log(`  projection fixture: ${proj} txns`);
  const allCodes = ['unsealed', 'unbalanced', 'too-few-legs', 'no-account-leg', 'currency-mismatch',
    'cross-ledger', 'base-identity', 'kind-shape', 'trial-balance', 'balance-drift'];
  const missing = allCodes.filter((c) => !aud.covered.has(c));
  console.log(`export-fixtures: wrote ${sel} selector fixtures + ${aud.count} audit fixtures → ${path.relative(process.cwd(), OUT)}`);
  console.log(`  audit codes covered: ${[...aud.covered].sort().join(', ')}`);
  if (missing.length) { console.error(`  !! UNCOVERED audit codes: ${missing.join(', ')}`); process.exit(2); }
}

main().catch((e) => { console.error(e); process.exit(1); });
