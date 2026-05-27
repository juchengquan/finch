// Server-side handlers for every store action, operating on the same state
// representation that projectState reads: transactions live in the transactions
// table; pending/recurring/override slices live in app_state. Each handler is a
// pure SQL mutation; the API route persists the file and returns the new state.

import type { Exec } from './repo';
import { listRecurring, deleteRecurring as qDeleteRecurring } from './queries/recurring';
import {
  recomputeForTransaction,
  createAccount as qCreateAccount,
  updateAccount as qUpdateAccount,
  archiveAccount as qArchiveAccount,
  deleteAccount as qDeleteAccount,
  type AccountPatch,
} from './queries/accounts';
import { deleteGoal as qDeleteGoal } from './queries/goals';
import { deleteTag as qDeleteTag } from './queries/tags';
import { deleteSubscription as qDeleteSubscription } from './queries/planning';
import { deleteCategory as qDeleteCategory } from './queries/categories';
import { deleteCounterparty as qDeleteCounterparty } from './queries/counterparties';
import { deleteTransfer as qDeleteTransfer } from './queries/transfers';
import { isAccountType } from '@/lib/account-types';
import { convertToBase } from './queries/rates';
import {
  addTransaction as qAdd,
  updateTransaction as qUpdate,
  cancelTransaction as qCancel,
  confirmTransaction as qConfirm,
  type AddInput,
} from './queries/transactions';
import { seedReference, insertTransactions, seedAppStateDefaults, seedTransactionTags } from './seed';
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
  'goals',
  'subscriptions',
  'scheduled_items',
  'recurring_splits',
  'recurring_templates',
  'sync_log',
  'tags',
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
  await seedTransactionTags(exec);
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
    recurring?: boolean;
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
      row.balanceAfter, row.currency, row.note, row.recurring ? 1 : 0, ts,
    ],
  );
}

// Match a recurring template's account NAME to a real account id in the ledger
// (the mock templates store names like "Amex Gold", not ids).
async function resolveAccountId(exec: Exec, ledgerId: string, name: string): Promise<string | null> {
  if (!name) return null;
  const accts = await exec('SELECT id, name FROM accounts WHERE ledger_id = ?', [ledgerId]);
  const lc = name.toLowerCase();
  const exact = accts.find((a) => String(a.name).toLowerCase() === lc);
  if (exact) return String(exact.id);
  const partial = accts.find(
    (a) => String(a.name).toLowerCase().includes(lc) || lc.includes(String(a.name).toLowerCase()),
  );
  return partial ? String(partial.id) : null;
}

async function postSingle(
  exec: Exec,
  ledgerId: string,
  accountId: string,
  amount: number,
  description: string,
  date: string,
): Promise<void> {
  const [acct] = await exec('SELECT current_balance, currency FROM accounts WHERE id = ?', [accountId]);
  await insertTxRow(exec, {
    ledgerId, accountId, date, amount, description,
    balanceAfter: r2(Number(acct?.current_balance ?? 0) + amount), currency: String(acct?.currency ?? 'USD'),
    transferGroupId: null, note: null, recurring: true,
  });
}

// Post a recurring template now: create the confirmed transaction(s) it implies.
// Income templates with splits post one row per (resolvable) split.
async function postRecurring(exec: Exec, args: Args): Promise<void> {
  const templateId = str(args.templateId);
  const ledgerId = 'personal';
  const recurring = await listRecurring(exec, ledgerId);
  const t = recurring.find((r) => r.id === templateId);
  if (!t) throw new Error('Template not found');
  const date = new Date().toISOString().slice(0, 10);

  if (t.type === 'transfer') {
    const fromId = await resolveAccountId(exec, ledgerId, t.from ?? '');
    const toId = await resolveAccountId(exec, ledgerId, t.account);
    if (!fromId || !toId) throw new Error(`Couldn't match the accounts for "${t.name}"`);
    await createTransfer(exec, { fromAccountId: fromId, toAccountId: toId, amount: t.amount ?? 0, date, note: t.name });
    return;
  }

  if (t.amount == null) throw new Error(`"${t.name}" has a variable amount — add it manually`);
  const sign = t.type === 'income' ? 1 : -1;

  if (t.type === 'income' && t.splits?.length) {
    let posted = 0;
    for (const sp of t.splits) {
      const acctId = await resolveAccountId(exec, ledgerId, sp.account);
      if (!acctId) continue;
      const portion = sp.abs != null ? sp.abs : (t.amount * (sp.pct ?? 0)) / 100;
      if (!portion) continue;
      await postSingle(exec, ledgerId, acctId, portion, `${t.name} · ${sp.label}`, date);
      posted++;
    }
    if (!posted) throw new Error(`Couldn't match any split account for "${t.name}"`);
    return;
  }

  const acctId = await resolveAccountId(exec, ledgerId, t.account);
  if (!acctId) throw new Error(`Couldn't match account "${t.account}" for "${t.name}"`);
  await postSingle(exec, ledgerId, acctId, sign * t.amount, t.name, date);
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
  const fromCurrency = String(from.currency);
  const toCurrency = String(to.currency);
  // `amount` is in the from-account's currency; convert it to the to-account's
  // currency for the incoming leg (no-op when the currencies match).
  const conv = await convertToBase(exec, amount, fromCurrency, toCurrency, date);
  const toAmount = conv.amountBase;
  const tgId = newId('tg');
  await exec(
    'INSERT INTO transfer_groups (id,ledger_id,created_at,amount_base,from_currency,to_currency,exchange_rate,notes) VALUES (?,?,?,?,?,?,?,?)',
    [tgId, ledgerId, date, amount, fromCurrency, toCurrency, conv.rate, note],
  );
  await insertTxRow(exec, {
    ledgerId, accountId: fromId, date, amount: -amount, description: `Transfer to ${String(to.name)}`,
    balanceAfter: r2(Number(from.current_balance) - amount), currency: fromCurrency, transferGroupId: tgId, note,
  });
  await insertTxRow(exec, {
    ledgerId, accountId: toId, date, amount: toAmount, description: `Transfer from ${String(from.name)}`,
    balanceAfter: r2(Number(to.current_balance) + toAmount), currency: toCurrency, transferGroupId: tgId, note,
  });
}

export async function applyMutation(exec: Exec, action: string, args: Args): Promise<void> {
  switch (action) {
    case 'addTransaction':
      await qAdd(exec, args as unknown as AddInput);
      return;
    case 'updateTransaction':
      await qUpdate(exec, str(args.id), args.patch as Parameters<typeof qUpdate>[2]);
      await recomputeForTransaction(exec, str(args.id)); // an amount/date edit shifts balances
      return;
    case 'deleteTransaction':
      await qCancel(exec, str(args.id));
      await recomputeForTransaction(exec, str(args.id)); // cancelling must reverse the balance
      return;
    case 'confirmTransaction':
      await qConfirm(exec, str(args.id));
      return;
    case 'confirmAllPending':
      await exec("UPDATE transactions SET status = 'confirmed', confirmed_at = ? WHERE status = 'pending'", [
        new Date().toISOString(),
      ]);
      return;
    case 'setBudget': {
      const bo = await getJson<Record<string, number>>(exec, 'budgetOverrides', {});
      bo[str(args.categoryId)] = Number(args.amount);
      await setJson(exec, 'budgetOverrides', bo);
      return;
    }
    case 'createAccount': {
      const ledgerId = str(args.ledgerId || 'personal');
      const name = str(args.name).trim();
      if (!name) throw new Error('Account name is required');
      const type = str(args.type || 'savings');
      if (!isAccountType(type)) throw new Error(`Unknown account type "${type}"`);
      await qCreateAccount(exec, {
        id: str(args.id || newId('acct')),
        ledgerId,
        name,
        type,
        currency: str(args.currency || 'SGD'),
        groupId: args.groupId ? str(args.groupId) : null,
        openingBalance: Number(args.openingBalance ?? 0),
        color: args.color ? str(args.color) : null,
        last4: args.last4 ? str(args.last4) : null,
      });
      return;
    }
    case 'updateAccount': {
      const patch = (args.patch ?? {}) as AccountPatch;
      if (patch.name !== undefined && !str(patch.name).trim()) throw new Error('Account name is required');
      if (patch.type !== undefined && !isAccountType(str(patch.type))) {
        throw new Error(`Unknown account type "${patch.type}"`);
      }
      await qUpdateAccount(exec, str(args.id), patch);
      return;
    }
    case 'archiveAccount':
      await qArchiveAccount(exec, str(args.id));
      return;
    case 'deleteAccount':
      await qDeleteAccount(exec, str(args.id));
      return;
    case 'updateRecurringSplit': {
      await exec(
        `UPDATE recurring_splits SET amount_pct = ?
          WHERE id = (SELECT id FROM recurring_splits WHERE template_id = ? ORDER BY sort_order LIMIT 1 OFFSET ?)`,
        [Number(args.pct), str(args.templateId), Number(args.index)],
      );
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
    case 'createCategory': {
      const ledgerId = str(args.ledgerId || 'personal');
      const name = str(args.name).trim();
      if (!name) throw new Error('Category name is required');
      const type = args.type ? str(args.type) : 'expense';
      const icon = args.icon ? str(args.icon) : null;
      const rows = await exec('SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM categories WHERE ledger_id = ?', [ledgerId]);
      await exec('INSERT INTO categories (id,ledger_id,name,parent_name,type,icon,sort_order) VALUES (?,?,?,?,?,?,?)', [
        newId('cat'), ledgerId, name, null, type, icon, Number(rows[0]?.n ?? 0),
      ]);
      return;
    }
    case 'renameCategory': {
      const name = str(args.name).trim();
      if (!name) throw new Error('Category name is required');
      await exec('UPDATE categories SET name = ? WHERE id = ?', [name, str(args.id)]);
      return;
    }
    case 'createGoal': {
      const ledgerId = str(args.ledgerId || 'personal');
      const name = str(args.name).trim();
      const target = Number(args.target);
      if (!name) throw new Error('Goal name is required');
      if (!(target > 0)) throw new Error('Goal target must be greater than 0');
      const eta = args.eta ? str(args.eta) : null;
      const hue = args.hue != null ? Number(args.hue) : 200;
      const rows = await exec('SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM goals WHERE ledger_id = ?', [ledgerId]);
      await exec('INSERT INTO goals (id,ledger_id,name,target,saved,eta,hue,sort_order,created_at) VALUES (?,?,?,?,?,?,?,?,?)', [
        newId('goal'), ledgerId, name, target, 0, eta, hue, Number(rows[0]?.n ?? 0), new Date().toISOString(),
      ]);
      return;
    }
    case 'contributeGoal': {
      const amount = Number(args.amount);
      if (!Number.isFinite(amount)) throw new Error('Invalid contribution amount');
      await exec('UPDATE goals SET saved = MAX(0, saved + ?) WHERE id = ?', [amount, str(args.id)]);
      return;
    }
    case 'createTag': {
      const name = str(args.name).trim();
      if (!name) throw new Error('Tag name is required');
      await exec('INSERT INTO tags (id,ledger_id,name,color) VALUES (?,?,?,?)', [
        args.id ? str(args.id) : newId('tag'), str(args.ledgerId || 'personal'), name, args.color ? str(args.color) : null,
      ]);
      return;
    }
    case 'setTransactionTags': {
      const txId = str(args.id);
      const tagIds = Array.isArray(args.tagIds) ? (args.tagIds as unknown[]).map(str) : [];
      await exec('DELETE FROM transaction_tags WHERE transaction_id = ?', [txId]);
      for (const tagId of tagIds) {
        await exec('INSERT OR IGNORE INTO transaction_tags (transaction_id, tag_id) VALUES (?, ?)', [txId, tagId]);
      }
      return;
    }
    case 'createSubscription': {
      const ledgerId = str(args.ledgerId || 'personal');
      const name = str(args.name).trim();
      const amount = Number(args.amount);
      if (!name) throw new Error('Subscription name is required');
      if (!(amount > 0)) throw new Error('Subscription amount must be greater than 0');
      const rows = await exec('SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM subscriptions WHERE ledger_id = ?', [ledgerId]);
      await exec(
        'INSERT INTO subscriptions (id,ledger_id,name,amount,cadence,next_date,hue,sort_order,created_at) VALUES (?,?,?,?,?,?,?,?,?)',
        [newId('sub'), ledgerId, name, amount, args.cadence ? str(args.cadence) : 'monthly', args.next ? str(args.next) : null, args.hue != null ? Number(args.hue) : 200, Number(rows[0]?.n ?? 0), new Date().toISOString()],
      );
      return;
    }
    case 'deleteCategory':
      await qDeleteCategory(exec, str(args.id));
      return;
    case 'deleteGoal':
      await qDeleteGoal(exec, str(args.id));
      return;
    case 'deleteTag':
      await qDeleteTag(exec, str(args.id));
      return;
    case 'deleteSubscription':
      await qDeleteSubscription(exec, str(args.id));
      return;
    case 'deleteRecurring':
      await qDeleteRecurring(exec, str(args.id));
      return;
    case 'deleteTransfer':
      await qDeleteTransfer(exec, str(args.id));
      return;
    case 'deleteCounterparty':
      await qDeleteCounterparty(exec, str(args.id));
      return;
    case 'postRecurring':
      await postRecurring(exec, args);
      return;
    case 'reset':
      await resetDb(exec);
      return;
    default:
      throw new Error(`Unknown action: ${action}`);
  }
}
