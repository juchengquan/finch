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
const r2 = (n: number) => Math.round(n * 100) / 100;

function newId(prefix: string): string {
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
}

// Insert one transaction row directly (used for transfers, which carry a
// transfer_group_id and need an explicit balance_after).
async function insertTxRow(
  exec: Exec,
  row: {
    ledgerId: string;
    accountId: string;
    date: string;
    amount: number;
    description: string;
    balanceAfter: number;
    currency: string;
    transferGroupId: string | null;
    note: string | null;
  },
): Promise<void> {
  const ts = new Date().toISOString();
  await exec(
    `INSERT INTO transactions
      (id,ledger_id,account_id,date,time,amount,amount_base,exchange_rate,exchange_rate_date,
       description,category_id,counterparty_id,transfer_group_id,status,confirmed_at,
       balance_after,currency,notes,recurring,created_at)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
    [
      newId('t'), row.ledgerId, row.accountId, row.date, null, row.amount, row.amount, 1, row.date,
      row.description, null, null, row.transferGroupId, 'confirmed', ts,
      row.balanceAfter, row.currency, row.note, 0, ts,
    ],
  );
}

// Create a transfer: a transfer_group plus two confirmed transactions (out/in)
// that share its id, so it moves both account balances and shows in Activity.
async function createTransfer(exec: Exec, args: Args): Promise<void> {
  const fromId = str(args.fromAccountId);
  const toId = str(args.toAccountId);
  const amount = Math.abs(Number(args.amount));
  const date = str(args.date);
  const note = args.note ? str(args.note) : null;
  if (!amount) throw new Error('Transfer amount must be greater than 0');
  if (fromId === toId) throw new Error('Pick two different accounts');

  const [from] = await exec('SELECT ledger_id, currency, current_balance, name FROM accounts WHERE id = ?', [fromId]);
  const [to] = await exec('SELECT currency, current_balance, name FROM accounts WHERE id = ?', [toId]);
  if (!from || !to) throw new Error('Account not found');

  const ledgerId = String(from.ledger_id);
  const tgId = newId('tg');
  await exec(
    'INSERT INTO transfer_groups (id,ledger_id,created_at,amount_base,from_currency,to_currency,exchange_rate,notes) VALUES (?,?,?,?,?,?,?,?)',
    [tgId, ledgerId, date, amount, String(from.currency), String(to.currency), 1, note],
  );
  await insertTxRow(exec, {
    ledgerId, accountId: fromId, date, amount: -amount, description: `Transfer to ${String(to.name)}`,
    balanceAfter: r2(Number(from.current_balance) - amount), currency: String(from.currency), transferGroupId: tgId, note,
  });
  await insertTxRow(exec, {
    ledgerId, accountId: toId, date, amount, description: `Transfer from ${String(from.name)}`,
    balanceAfter: r2(Number(to.current_balance) + amount), currency: String(to.currency), transferGroupId: tgId, note,
  });
}

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
    case 'createTransfer':
      await createTransfer(exec, args);
      return;
    case 'reset':
      await resetDb(exec);
      return;
    default:
      throw new Error(`Unknown action: ${action}`);
  }
}
