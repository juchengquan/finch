// Server-side handlers for every store action, operating on the same state
// representation that projectState reads: transactions live in the transactions
// table; pending/recurring/override slices live in app_state. Each handler is a
// pure SQL mutation; the API route persists the file and returns the new state.

import type { Exec } from './repo';
import type { PendingItem, RecurringTemplate } from '@/lib/store';
import {
  addTransaction as qAdd,
  updateTransaction as qUpdate,
  cancelTransaction as qCancel,
  type AddInput,
} from './queries/transactions';
import { seedReference, insertTransactions, seedAppStateDefaults } from './seed';
import transactionsData from '@/data/transactions.json';
import type { Tx } from '@/lib/store';

async function getJson<T>(exec: Exec, key: string, fallback: T): Promise<T> {
  const rows = await exec('SELECT value FROM app_state WHERE key = ?', [key]);
  const raw = rows[0]?.value;
  if (raw == null) return fallback;
  try {
    return JSON.parse(String(raw)) as T;
  } catch {
    return fallback;
  }
}

async function setJson(exec: Exec, key: string, value: unknown): Promise<void> {
  await exec('INSERT OR REPLACE INTO app_state (key, value) VALUES (?, ?)', [key, JSON.stringify(value)]);
}

const RESET_TABLES = [
  'transactions',
  'account_balance_snapshots',
  'ledger_summaries',
  'budgets',
  'transfer_groups',
  'counterparties',
  'categories',
  'accounts',
  'account_groups',
  'exchange_rates',
  'ledgers',
  'app_state',
];

async function resetDb(exec: Exec): Promise<void> {
  for (const t of RESET_TABLES) await exec(`DELETE FROM ${t}`);
  await seedReference(exec);
  await insertTransactions(exec, transactionsData as Tx[]);
  await seedAppStateDefaults(exec);
}

type Args = Record<string, unknown>;
const str = (v: unknown) => String(v);

export async function applyMutation(exec: Exec, action: string, args: Args): Promise<void> {
  switch (action) {
    case 'addTransaction':
      await qAdd(exec, args as unknown as AddInput);
      return;
    case 'updateTransaction':
      await qUpdate(exec, str(args.id), args.patch as Parameters<typeof qUpdate>[2]);
      return;
    case 'deleteTransaction':
      await qCancel(exec, str(args.id));
      return;
    case 'confirmPending':
    case 'cancelPending': {
      const pending = await getJson<PendingItem[]>(exec, 'pending', []);
      await setJson(exec, 'pending', pending.filter((p) => p.id !== str(args.id)));
      return;
    }
    case 'confirmAllPending':
      await setJson(exec, 'pending', []);
      return;
    case 'setBudget': {
      const bo = await getJson<Record<string, number>>(exec, 'budgetOverrides', {});
      bo[str(args.categoryId)] = Number(args.amount);
      await setJson(exec, 'budgetOverrides', bo);
      return;
    }
    case 'setAccountDetails': {
      const ao = await getJson<Record<string, Record<string, unknown>>>(exec, 'accountOverrides', {});
      ao[str(args.accountId)] = { ...ao[str(args.accountId)], ...(args.patch as Record<string, unknown>) };
      await setJson(exec, 'accountOverrides', ao);
      return;
    }
    case 'updateRecurringSplit': {
      const recurring = await getJson<RecurringTemplate[]>(exec, 'recurring', []);
      const next = recurring.map((t) =>
        t.id === str(args.templateId) && t.splits
          ? { ...t, splits: t.splits.map((sp, i) => (i === Number(args.index) ? { ...sp, pct: Number(args.pct) } : sp)) }
          : t,
      );
      await setJson(exec, 'recurring', next);
      return;
    }
    case 'verifyCounterparty': {
      const v = await getJson<string[]>(exec, 'verifiedExtra', []);
      if (!v.includes(str(args.id))) v.push(str(args.id));
      await setJson(exec, 'verifiedExtra', v);
      return;
    }
    case 'addAlias': {
      const a = await getJson<Record<string, string[]>>(exec, 'aliasExtra', {});
      a[str(args.id)] = [...(a[str(args.id)] ?? []), str(args.alias)];
      await setJson(exec, 'aliasExtra', a);
      return;
    }
    case 'reset':
      await resetDb(exec);
      return;
    default:
      throw new Error(`Unknown action: ${action}`);
  }
}
