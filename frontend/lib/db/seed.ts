// Builds the relational seed from the app's data/*.json, converting the flat
// mock shapes into the design-doc schema. Existing string ids are reused as PKs
// so the current UI lookups keep working as screens migrate.
//
// Scope (Phase 0): ledgers, account_groups, accounts, categories, counterparties,
// budgets, transfer_groups, exchange_rates, transactions (+ the snapshot/summary
// tables that the triggers fill on insert). recurring/pending/tags/sync_log are
// seeded in their own later phases.

import type { Exec } from './repo';
import accountsData from '@/data/accounts.json';
import accountGroupsData from '@/data/account-groups.json';
import categoriesData from '@/data/categories.json';
import ledgersData from '@/data/ledgers.json';
import counterpartiesData from '@/data/counterparties.json';
import transferGroupsData from '@/data/transfer-groups.json';
import exchangeRatesData from '@/data/exchange-rates.json';
import transactionsData from '@/data/transactions.json';

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
type TxRow = {
  id: string; merchant: string; category: string | null; amount: number; account: string;
  date: string; time?: string; note?: string; pending?: boolean; recurring?: boolean; ledgerId?: string;
};
type CounterpartyRow = { id: string; name: string; aliases?: string[]; category?: string; verified?: number };
type TransferRow = {
  id: string; date: string; amountBase: number; fromCurrency: string; toCurrency: string;
  exchangeRate?: number; fromLedger: string; notes?: string;
};
type RateRow = { date: string; currency: string; rate: number; source?: string };

const accounts = accountsData as AccountRow[];
const categories = categoriesData as CategoryRow[];
const ledgers = ledgersData as { id: string; name: string; base: string; isDefault: number }[];
const transactions = transactionsData as TxRow[];

const baseOf = (ledgerId: string) => ledgers.find((l) => l.id === ledgerId)?.base ?? 'USD';
const ledgerIdByName = (name: string) => ledgers.find((l) => l.name === name)?.id ?? 'personal';
const isoDate = (d: string) => d.replace(/\//g, '-');

export async function seedDatabase(exec: Exec): Promise<void> {
  await exec('BEGIN');
  try {
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

    // Transactions: insert per account in chronological order so the balance
    // trigger computes a running balance that ends at the account's known
    // balance. start = known_balance - sum(all that account's seed deltas).
    const byAccount = new Map<string, TxRow[]>();
    for (const t of transactions) {
      const list = byAccount.get(t.account) ?? [];
      list.push(t);
      byAccount.set(t.account, list);
    }
    for (const [accountId, list] of byAccount) {
      const acct = accounts.find((a) => a.id === accountId);
      const totalDelta = list.reduce((s, t) => s + t.amount, 0);
      let running = (acct?.balance ?? 0) - totalDelta;
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
            t.merchant, t.category, null, null, t.pending ? 'pending' : 'confirmed', t.pending ? null : SEED_TS,
            Math.round(running * 100) / 100, baseOf(ledgerId), t.note || null, t.recurring ? 1 : 0, SEED_TS,
          ],
        );
      }
    }

    await exec('COMMIT');
  } catch (err) {
    await exec('ROLLBACK');
    throw err;
  }
}
