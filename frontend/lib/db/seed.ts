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
import accountsData from '@/data/accounts.json';
import accountGroupsData from '@/data/account-groups.json';
import categoriesData from '@/data/categories.json';
import ledgersData from '@/data/ledgers.json';
import counterpartiesData from '@/data/counterparties.json';
import transferGroupsData from '@/data/transfer-groups.json';
import exchangeRatesData from '@/data/exchange-rates.json';
import transactionsData from '@/data/transactions.json';
import pendingData from '@/data/pending.json';
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

type AccountRow = { id: string; name: string; type: string; group: string; balance: number; last4?: string; ledger?: string };
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

// Each account's opening balance is fixed: the known seed balance minus the sum
// of the seed transactions for that account. Running balances then start there
// and add whatever transactions are inserted, so current_balance reflects the
// live set (adds/deletes), not just the original seed.
const seedDeltaByAccount = (() => {
  const m = new Map<string, number>();
  for (const t of transactionsData as Tx[]) m.set(t.account, (m.get(t.account) ?? 0) + t.amount);
  return m;
})();
const openingBalance = (accountId: string): number => {
  const acct = accounts.find((a) => a.id === accountId);
  return (acct?.balance ?? 0) - (seedDeltaByAccount.get(accountId) ?? 0);
};

const baseOf = (ledgerId: string) => ledgers.find((l) => l.id === ledgerId)?.base ?? 'USD';
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
      'INSERT INTO accounts (id,ledger_id,group_id,name,type,currency,current_balance,credit_limit,notes,include_in_net_worth,is_active,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [a.id, ledgerId, a.group, a.name, ACCOUNT_TYPE[a.type] ?? 'savings', baseOf(ledgerId), a.balance, null, null, null, 1, SEED_TS, SEED_TS],
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
  for (const [accountId, list] of byAccount) {
    let running = openingBalance(accountId);
    const ordered = [...list].sort((a, b) =>
      (a.date + (a.time ?? '')).localeCompare(b.date + (b.time ?? '')),
    );
    for (const t of ordered) {
      running += t.amount;
      const ledgerId = t.ledgerId ?? 'personal';
      await exec(
        `INSERT INTO transactions
          (id,ledger_id,account_id,date,time,amount,amount_base,exchange_rate,exchange_rate_date,
           description,category_id,counterparty_id,transfer_group_id,status,confirmed_at,
           balance_after,currency,notes,recurring,created_at)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
        [
          t.id, ledgerId, t.account, t.date, t.time ?? null, t.amount, t.amount, 1, t.date,
          t.merchant, t.category, null, t.transferGroupId ?? null, t.pending ? 'pending' : 'confirmed', t.pending ? null : SEED_TS,
          Math.round(running * 100) / 100, baseOf(ledgerId), t.note || null, t.recurring ? 1 : 0, SEED_TS,
        ],
      );
    }
  }
}

/** Seed the transitional store slices (pending/recurring + empty override maps). */
export async function seedAppStateDefaults(exec: Exec): Promise<void> {
  const entries: [string, unknown][] = [
    ['pending', pendingData],
    ['recurring', recurringData],
    ['budgetOverrides', {}],
    ['accountOverrides', {}],
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
    await seedAppStateDefaults(exec);
    await exec('COMMIT');
  } catch (err) {
    await exec('ROLLBACK');
    throw err;
  }
}
