// Builds the relational seed from the app's data/*.json, converting the flat
// mock shapes into the design-doc schema. Existing string ids are reused as PKs
// so the current UI lookups keep working as screens migrate.
//
// Split into reusable parts so persistence (lib/db/state.ts) can rebuild a DB
// from arbitrary store state:
//   - seedReference: the static entity tables (ledgers/accounts/categories/…).
//   - insertTransactions: rows from a Tx[] (seed JSON or live store).
//   - seedAppStateDefaults: the transitional store slices (pending/recurring/…).

import type { Exec } from './repo';
import type { Tx } from '@/lib/store';
import { convertToBase } from './queries/rates';
import accountsData from '@/data/accounts.json';
import accountGroupsData from '@/data/account-groups.json';
import categoriesData from '@/data/categories.json';
import ledgersData from '@/data/ledgers.json';
import counterpartiesData from '@/data/counterparties.json';
import transferGroupsData from '@/data/transfer-groups.json';
import exchangeRatesData from '@/data/exchange-rates.json';
import devicesData from '@/data/devices.json';
import goalsData from '@/data/goals.json';
import subscriptionsData from '@/data/subscriptions.json';
import scheduledItemsData from '@/data/scheduled-items.json';
import tagsData from '@/data/tags.json';
import transactionsData from '@/data/transactions.json';
import recurringData from '@/data/recurring-templates.json';

const SEED_TS = '2026-05-26T00:00:00';

const ACCOUNT_TYPE: Record<string, string> = {
  checking: 'savings',
  savings: 'savings',
  credit: 'credit_card',
  invest: 'investment',
  cash: 'cash',
  fx: 'fx',
  virtual: 'virtual',
};

type AccountRow = { id: string; name: string; type: string; group: string; balance: number; last4?: string; color?: string; ledger?: string };
type CategoryRow = { id: string; name: string; budget?: number; icon?: string; ledger?: string };
type CounterpartyRow = { id: string; name: string; aliases?: string[]; category?: string; verified?: number };
type TransferRow = {
  id: string; date: string; amountBase: number; fromCurrency: string; toCurrency: string;
  exchangeRate?: number; fromLedger: string; notes?: string;
};
type RateRow = { date: string; currency: string; rate: number; source?: string };

const accounts = accountsData as AccountRow[];
const categories = categoriesData as CategoryRow[];
const ledgers = ledgersData as { id: string; name: string; base: string; isDefault: number }[];

const baseOf = (ledgerId: string) => ledgers.find((l) => l.id === ledgerId)?.base ?? 'USD';

// The ledger-base value of a transaction: its `amount`, except foreign rows whose
// base is derived from the exchange_rates table (rate locked at the txn date).
async function baseOfTx(exec: Exec, t: Tx): Promise<{ amountBase: number; rate: number; native: number; currency: string }> {
  const baseCurrency = baseOf(t.ledgerId ?? 'personal');
  const native = t.nativeAmount ?? t.amount;
  const currency = t.currency ?? baseCurrency;
  if (t.nativeAmount != null && currency !== baseCurrency) {
    const conv = await convertToBase(exec, native, currency, baseCurrency, t.date);
    return { amountBase: conv.amountBase, rate: conv.rate, native, currency };
  }
  return { amountBase: t.amount, rate: 1, native, currency };
}

// Each account's opening balance is fixed: the known seed balance minus the sum
// of the *seed* transactions' base amounts. Running balances start there and add
// whatever is actually inserted, so current_balance reflects the live set
// (adds/deletes), not just the original seed.
async function seedOpeningByAccount(exec: Exec): Promise<Map<string, number>> {
  const deltaByAccount = new Map<string, number>();
  for (const t of transactionsData as Tx[]) {
    const { amountBase } = await baseOfTx(exec, t);
    deltaByAccount.set(t.account, (deltaByAccount.get(t.account) ?? 0) + amountBase);
  }
  const opening = new Map<string, number>();
  for (const a of accounts) {
    opening.set(a.id, Math.round(((a.balance ?? 0) - (deltaByAccount.get(a.id) ?? 0)) * 100) / 100);
  }
  return opening;
}
const ledgerIdByName = (name: string) => ledgers.find((l) => l.name === name)?.id ?? 'personal';
const isoDate = (d: string) => d.replace(/\//g, '-');

/** Seed the static reference tables (everything except transactions / app_state). */
export async function seedReference(exec: Exec): Promise<void> {
  for (const l of ledgers) {
    await exec(
      'INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES (?,?,?,?,?,?)',
      [l.id, l.name, l.base, l.isDefault ? 1 : 0, SEED_TS, SEED_TS],
    );
  }

  // Groups are shared across ledgers in the mock; seed them under the default
  // ledger (FK only requires the group row to exist, not a ledger match).
  for (let i = 0; i < accountGroupsData.length; i++) {
    const g = accountGroupsData[i];
    await exec(
      'INSERT INTO account_groups (id,ledger_id,name,include_in_net_worth,sort_order,created_at,updated_at) VALUES (?,?,?,?,?,?,?)',
      [g.id, 'personal', g.name, g.id === 'credit' ? 0 : 1, i, SEED_TS, SEED_TS],
    );
  }

  for (const a of accounts) {
    const ledgerId = a.ledger ?? 'personal';
    await exec(
      'INSERT INTO accounts (id,ledger_id,group_id,name,type,currency,current_balance,opening_balance,credit_limit,notes,color,last4,institution,routing,include_in_net_worth,is_active,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      // opening_balance starts at the known balance; insertTransactions overwrites
      // it with the true opening (known − Σ bases) for accounts that have txns.
      [a.id, ledgerId, a.group, a.name, ACCOUNT_TYPE[a.type] ?? 'savings', baseOf(ledgerId), a.balance, a.balance, null, null, a.color ?? null, a.last4 ?? null, null, null, null, 1, SEED_TS, SEED_TS],
    );
  }

  for (let i = 0; i < categories.length; i++) {
    const c = categories[i];
    await exec(
      'INSERT INTO categories (id,ledger_id,name,parent_name,type,icon,sort_order) VALUES (?,?,?,?,?,?,?)',
      [c.id, c.ledger ?? 'personal', c.name, null, 'expense', c.icon ?? null, i],
    );
  }

  for (const cp of counterpartiesData as CounterpartyRow[]) {
    await exec(
      'INSERT INTO counterparties (id,ledger_id,standardized_name,aliases,category,logo_url,is_verified,created_at) VALUES (?,?,?,?,?,?,?,?)',
      [cp.id, 'personal', cp.name, JSON.stringify(cp.aliases ?? []), cp.category ?? null, null, cp.verified ? 1 : 0, SEED_TS],
    );
  }

  for (const c of categories) {
    if (!c.budget) continue;
    const ledgerId = c.ledger ?? 'personal';
    await exec(
      'INSERT INTO budgets (id,ledger_id,name,type,amount,carry_forward,frequency,start_date,is_recurring,rollover,category_ids,warning_pct,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [`bud-${c.id}`, ledgerId, c.name, 'expense', c.budget, 0, 'monthly', '2026-05-01', 1, 0, JSON.stringify([c.id]), 80, SEED_TS, SEED_TS],
    );
  }

  for (const tg of transferGroupsData as TransferRow[]) {
    await exec(
      'INSERT INTO transfer_groups (id,ledger_id,created_at,amount_base,from_currency,to_currency,exchange_rate,notes) VALUES (?,?,?,?,?,?,?,?)',
      [tg.id, ledgerIdByName(tg.fromLedger), isoDate(tg.date), tg.amountBase, tg.fromCurrency, tg.toCurrency, tg.exchangeRate ?? null, tg.notes ?? null],
    );
  }

  for (const r of exchangeRatesData as RateRow[]) {
    await exec(
      'INSERT OR IGNORE INTO exchange_rates (date,currency,rate_to_sgd,source) VALUES (?,?,?,?)',
      [isoDate(r.date), r.currency, r.rate, r.source ?? null],
    );
  }

  type DeviceRow = { id: string; name: string; lastSync: string; lastTxn?: string; current?: number };
  for (const d of devicesData as DeviceRow[]) {
    await exec(
      'INSERT OR IGNORE INTO sync_log (device_id,ledger_id,device_name,last_sync_at,last_txn_id,is_current) VALUES (?,?,?,?,?,?)',
      [d.id, 'personal', d.name, d.lastSync, d.lastTxn ?? null, d.current ? 1 : 0],
    );
  }

  type GoalRow = { id: string; name: string; target: number; saved: number; eta?: string; hue?: number; ledger?: string };
  const goals = goalsData as GoalRow[];
  for (let i = 0; i < goals.length; i++) {
    const g = goals[i];
    await exec(
      'INSERT OR IGNORE INTO goals (id,ledger_id,name,target,saved,eta,hue,sort_order,created_at) VALUES (?,?,?,?,?,?,?,?,?)',
      [g.id, g.ledger ?? 'personal', g.name, g.target, g.saved ?? 0, g.eta ?? null, g.hue ?? 200, i, SEED_TS],
    );
  }

  type TagSeed = { id: string; name: string; color?: string; ledger?: string };
  for (const t of (tagsData as { tags: TagSeed[] }).tags) {
    await exec('INSERT OR IGNORE INTO tags (id,ledger_id,name,color) VALUES (?,?,?,?)', [
      t.id, t.ledger ?? 'personal', t.name, t.color ?? null,
    ]);
  }

  type SubRow = { id: string; name: string; amount: number; cadence?: string; next?: string; logoHue?: number; ledger?: string };
  const subs = subscriptionsData as SubRow[];
  for (let i = 0; i < subs.length; i++) {
    const s = subs[i];
    await exec(
      'INSERT OR IGNORE INTO subscriptions (id,ledger_id,name,amount,cadence,next_date,hue,sort_order,created_at) VALUES (?,?,?,?,?,?,?,?,?)',
      [s.id, s.ledger ?? 'personal', s.name, s.amount, s.cadence ?? 'monthly', s.next ?? null, s.logoHue ?? 200, i, SEED_TS],
    );
  }

  type SchedRow = { day: number; month: string; label: string; amount: number; type: string; color?: string; ledger?: string };
  const sched = scheduledItemsData as SchedRow[];
  for (let i = 0; i < sched.length; i++) {
    const s = sched[i];
    await exec(
      'INSERT OR IGNORE INTO scheduled_items (id,ledger_id,day,month,label,amount,type,color) VALUES (?,?,?,?,?,?,?,?)',
      [`sch-${i}`, s.ledger ?? 'personal', s.day, s.month, s.label, s.amount, s.type, s.color ?? null],
    );
  }

  // Recurring templates live in their own tables. The mock references accounts by
  // display name (not all map to real accounts), so the names are stored verbatim
  // (account_id stays null) and resolved at post time; next/last run are display labels.
  type SplitSeed = { account: string; pct?: number; abs?: number | null; label?: string };
  type RecurSeed = {
    id: string; name: string; type: string; amount?: number | null; varies?: number;
    frequency: string; dayOfMonth: number; account: string; from?: string; autoPost?: number;
    nextRun?: string; lastRun?: string; splits?: SplitSeed[]; ledger?: string;
  };
  for (const r of recurringData as RecurSeed[]) {
    const ledgerId = r.ledger ?? 'personal';
    await exec(
      `INSERT OR IGNORE INTO recurring_templates
        (id,ledger_id,name,type,amount,amount_varies,splits_enabled,account_id,account_name,
         from_account_id,from_account_name,category_id,frequency,day_of_month,start_date,
         next_run,last_run,auto_post,is_active,created_at,updated_at)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
      [
        r.id, ledgerId, r.name, r.type, r.amount ?? null, r.varies ? 1 : 0, r.splits?.length ? 1 : 0,
        null, r.account, null, r.from ?? null, null, r.frequency, r.dayOfMonth, '2026-05-01',
        r.nextRun ?? null, r.lastRun ?? null, r.autoPost ?? 1, 1, SEED_TS, SEED_TS,
      ],
    );
    const splits = r.splits ?? [];
    for (let i = 0; i < splits.length; i++) {
      const sp = splits[i];
      await exec(
        'INSERT OR IGNORE INTO recurring_splits (id,template_id,account_id,account_name,amount_pct,amount_abs,description,sort_order) VALUES (?,?,?,?,?,?,?,?)',
        [`${r.id}-s${i}`, r.id, null, sp.account, sp.pct ?? null, sp.abs ?? null, sp.label ?? null, i],
      );
    }
  }
}

/** Seed the static tag→transaction assignments. Must run after transactions
 *  exist; OR IGNORE skips rows whose transaction is absent. */
export async function seedTransactionTags(exec: Exec): Promise<void> {
  type Assign = { transactionId: string; tagId: string };
  for (const a of (tagsData as { assignments: Assign[] }).assignments) {
    // Guard the FK: OR IGNORE does not suppress foreign-key violations, and
    // buildState may rebuild from a transaction set that lacks these seed ids.
    await exec(
      'INSERT OR IGNORE INTO transaction_tags (transaction_id, tag_id) SELECT ?, ? WHERE EXISTS (SELECT 1 FROM transactions WHERE id = ?)',
      [a.transactionId, a.tagId, a.transactionId],
    );
  }
}

/**
 * Insert a Tx[] into the transactions table. Inserts per account in
 * chronological order so the balance trigger computes a running balance ending
 * at the account's known seed balance (start = known − sum(deltas)).
 */
export async function insertTransactions(exec: Exec, txs: Tx[]): Promise<void> {
  const byAccount = new Map<string, Tx[]>();
  for (const t of txs) {
    const list = byAccount.get(t.account) ?? [];
    list.push(t);
    byAccount.set(t.account, list);
  }
  const opening = await seedOpeningByAccount(exec);
  for (const [accountId, list] of byAccount) {
    const ordered = [...list].sort((a, b) =>
      (a.date + (a.time ?? '')).localeCompare(b.date + (b.time ?? '')),
    );
    const resolved = await Promise.all(
      ordered.map(async (t) => ({ t, ledgerId: t.ledgerId ?? 'personal', ...(await baseOfTx(exec, t)) })),
    );
    const open = opening.get(accountId) ?? accounts.find((a) => a.id === accountId)?.balance ?? 0;
    // Record the true opening so balances can be recomputed after edits/deletes.
    await exec('UPDATE accounts SET opening_balance = ? WHERE id = ?', [open, accountId]);
    let running = open;
    for (const r of resolved) {
      running = Math.round((running + r.amountBase) * 100) / 100;
      const t = r.t;
      await exec(
        `INSERT INTO transactions
          (id,ledger_id,account_id,date,time,amount,amount_base,exchange_rate,exchange_rate_date,
           description,category_id,counterparty_id,transfer_group_id,status,confirmed_at,
           balance_after,currency,notes,recurring,created_at)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
        [
          t.id, r.ledgerId, t.account, t.date, t.time ?? null, r.native, r.amountBase, r.rate, t.date,
          t.merchant, t.category, null, t.transferGroupId ?? null, t.pending ? 'pending' : 'confirmed', t.pending ? null : SEED_TS,
          running, r.currency, t.note || null, t.recurring ? 1 : 0, SEED_TS,
        ],
      );
    }
  }
}

/** Seed the transitional store slices (empty override maps + alias/verify extras). */
export async function seedAppStateDefaults(exec: Exec): Promise<void> {
  const entries: [string, unknown][] = [
    ['budgetOverrides', {}],
    ['verifiedExtra', []],
    ['aliasExtra', {}],
  ];
  for (const [k, v] of entries) {
    await exec('INSERT OR REPLACE INTO app_state (key,value) VALUES (?,?)', [k, JSON.stringify(v)]);
  }
}

/** Create a complete fresh database (reference + seed transactions + defaults). */
export async function seedDatabase(exec: Exec): Promise<void> {
  await exec('BEGIN');
  try {
    await seedReference(exec);
    await insertTransactions(exec, transactionsData as Tx[]);
    await seedTransactionTags(exec);
    await seedAppStateDefaults(exec);
    await exec('COMMIT');
  } catch (err) {
    await exec('ROLLBACK');
    throw err;
  }
}
