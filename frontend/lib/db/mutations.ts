// Server-side handlers for every store action, operating on the same state
// representation that projectState reads: transactions live in the transactions
// table; pending/scheduled/override slices live in app_state. Each handler is a
// pure SQL mutation; the API route persists the file and returns the new state.

import type { Exec } from './repo';
import {
  listScheduled,
  deleteScheduled as qDeleteScheduled,
  updateScheduled as qUpdateScheduled,
  createScheduled as qCreateScheduled,
  addScheduledSplit as qAddScheduledSplit,
  removeScheduledSplit as qRemoveScheduledSplit,
  type ScheduledPatch,
} from './queries/scheduled';
import {
  recomputeAccount,
  recomputeForTransaction,
  createAccount as qCreateAccount,
  updateAccount as qUpdateAccount,
  archiveAccount as qArchiveAccount,
  deleteAccount as qDeleteAccount,
  type AccountPatch,
} from './queries/accounts';
import {
  createAccountGroup as qCreateAccountGroup,
  updateAccountGroup as qUpdateAccountGroup,
  deleteAccountGroup as qDeleteAccountGroup,
  type AccountGroupPatch,
} from './queries/accountGroups';
import { deleteTag as qDeleteTag, updateTag as qUpdateTag, type TagPatch } from './queries/tags';
import { deleteCategory as qDeleteCategory, updateCategory as qUpdateCategory, type CategoryPatch } from './queries/categories';
import { setTransactionSplits as qSetTransactionSplits, type NewSplitInput } from './queries/transactionSplits';
import {
  deleteCounterparty as qDeleteCounterparty,
  updateCounterparty as qUpdateCounterparty,
  createCounterparty as qCreateCounterparty,
  verifyCounterparty as qVerifyCounterparty,
  unverifyCounterparty as qUnverifyCounterparty,
  addAlias as qAddAlias,
  removeAlias as qRemoveAlias,
  type CounterpartyPatch,
} from './queries/counterparties';
import { deleteTransfer as qDeleteTransfer, updateTransfer as qUpdateTransfer } from './queries/transfers';
import { setExchangeRate as qSetExchangeRate, deleteExchangeRate as qDeleteExchangeRate } from './queries/system';
import { pruneOldRates } from './queries/rates';
import { getAppState, setAppState } from './queries/appState';
import { occurrencesUpTo } from '@/lib/recurrence';
import { invalidateRollover } from '@/lib/budgets/rollover';
import type { ScheduledTemplate } from '@/lib/store';
import {
  createBudget as qCreateBudget,
  updateBudget as qUpdateBudget,
  updateBudgetCycle as qUpdateBudgetCycle,
  stageBudgetAmount as qStageBudgetAmount,
  clearPendingAmount as qClearPendingAmount,
  deleteBudget as qDeleteBudget,
  contributeBudget as qContributeBudget,
  type BudgetPatch,
  type BudgetCyclePatch,
  type BudgetType,
} from './queries/budgets';
import {
  createBudgetGroup as qCreateBudgetGroup,
  updateBudgetGroup as qUpdateBudgetGroup,
  deleteBudgetGroup as qDeleteBudgetGroup,
  type BudgetGroupPatch,
} from './queries/budgetGroups';
import { isAccountType } from '@/lib/account-types';
import { convertToBase, ledgerBaseCurrency } from './queries/rates';
import {
  addTransaction as qAdd,
  updateTransaction as qUpdate,
  deleteTransactionRow as qDelete,
  confirmTransaction as qConfirm,
  type AddInput,
} from './queries/transactions';
import { seedReference, insertTransactions, seedTransactionTags } from './seed';
import transactionsData from '@/data/transactions.json';
import type { Tx } from '@/lib/store';

const RESET_TABLES = [
  'transactions',
  'scheduled_splits',
  'scheduled_templates',
  'sync_log',
  'tags',
  'budgets',
  'budget_groups',
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
}

type Args = Record<string, unknown>;
const str = (v: unknown) => String(v);
const r2 = (n: number) => Math.round(n * 100) / 100;

function newId(prefix: string): string {
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
}

// Insert one confirmed transaction row directly (used for transfers, which carry
// a transfer_group_id). The insert trigger moves the account balance.
async function insertTxRow(
  exec: Exec,
  row: {
    ledgerId: string;
    accountId: string;
    date: string;
    amount: number;
    description: string;
    currency: string;
    transferGroupId: string | null;
    note: string | null;
    kind: 'income' | 'expense' | 'transfer' | 'adjustment';
  },
): Promise<void> {
  const ts = new Date().toISOString();
  // `amount` is native (in `row.currency`, the account's currency). `amount_base`
  // is the ledger-base figure for cross-account reports — convert + lock the rate.
  // These rows are confirmed, so the insert trigger moves the account balance.
  const ledgerBase = await ledgerBaseCurrency(exec, row.ledgerId);
  const conv = await convertToBase(exec, row.amount, row.currency, ledgerBase, row.date);
  await exec(
    `INSERT INTO transactions
      (id,ledger_id,account_id,date,time,amount,amount_base,exchange_rate,
       description,category_id,transfer_group_id,kind,status,confirmed_at,
       currency,notes,created_at)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
    [
      newId('t'), row.ledgerId, row.accountId, row.date, null, row.amount, conv.amountBase, conv.rate,
      row.description, null, row.transferGroupId, row.kind, 'confirmed', ts,
      row.currency, row.note, ts,
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
  const [acct] = await exec('SELECT currency FROM accounts WHERE id = ?', [accountId]);
  await insertTxRow(exec, {
    ledgerId, accountId, date, amount, description,
    currency: String(acct?.currency ?? 'USD'),
    transferGroupId: null, note: null, kind: amount > 0 ? 'income' : 'expense',
  });
}

async function postScheduled(exec: Exec, args: Args): Promise<void> {
  const templateId = str(args.templateId);
  const ledgerId = 'personal';
  const scheduled = await listScheduled(exec, ledgerId);
  const t = scheduled.find((r) => r.id === templateId);
  if (!t) throw new Error('Template not found');
  const date = new Date().toISOString().slice(0, 10);

  if (t.type === 'transfer') {
    const fromId = await resolveAccountId(exec, ledgerId, t.from ?? '');
    const toId = await resolveAccountId(exec, ledgerId, t.account);
    if (!fromId || !toId) throw new Error(`Couldn't match the accounts for "${t.name}"`);
    await createTransfer(exec, { fromAccountId: fromId, toAccountId: toId, fromAmount: t.amount ?? 0, date, note: t.name });
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
  const fromAmount = Math.abs(Number(args.fromAmount));
  const explicitToAmount = args.toAmount != null ? Math.abs(Number(args.toAmount)) : null;
  const date = str(args.date);
  const note = args.note ? str(args.note) : null;
  if (!fromAmount) throw new Error('Transfer amount must be greater than 0');
  if (fromId === toId) throw new Error('Pick two different accounts');

  const [from] = await exec('SELECT ledger_id, currency, name FROM accounts WHERE id = ?', [fromId]);
  const [to] = await exec('SELECT currency, name FROM accounts WHERE id = ?', [toId]);
  if (!from || !to) throw new Error('Account not found');

  const ledgerId = String(from.ledger_id);
  const fromCurrency = String(from.currency);
  const toCurrency = String(to.currency);
  // When `toAmount` isn't supplied, derive it (and the rate) from the rates
  // table. When the caller pins it, use it verbatim and recompute the rate.
  let toAmount: number;
  let rate: number;
  if (explicitToAmount != null) {
    if (!(explicitToAmount > 0)) throw new Error('Received amount must be greater than 0');
    if (fromCurrency === toCurrency && Math.abs(explicitToAmount - fromAmount) > 0.005) {
      throw new Error('Same-currency transfer amounts must match');
    }
    toAmount = explicitToAmount;
    rate = fromCurrency === toCurrency ? 1 : Math.round((toAmount / fromAmount) * 1e6) / 1e6;
  } else {
    const conv = await convertToBase(exec, fromAmount, fromCurrency, toCurrency, date);
    toAmount = conv.amountBase;
    rate = conv.rate;
  }
  const tgId = newId('tg');
  await exec(
    'INSERT INTO transfer_groups (id,ledger_id,created_at,amount_base,from_currency,to_currency,exchange_rate,notes) VALUES (?,?,?,?,?,?,?,?)',
    [tgId, ledgerId, date, fromAmount, fromCurrency, toCurrency, rate, note],
  );
  await insertTxRow(exec, {
    ledgerId, accountId: fromId, date, amount: -fromAmount, description: `Transfer to ${String(to.name)}`,
    currency: fromCurrency, transferGroupId: tgId, note, kind: 'transfer',
  });
  await insertTxRow(exec, {
    ledgerId, accountId: toId, date, amount: toAmount, description: `Transfer from ${String(from.name)}`,
    currency: toCurrency, transferGroupId: tgId, note, kind: 'transfer',
  });
}

// Auto-generate transactions for scheduled templates whose occurrences are due
// (on/before `today`), as UNCONFIRMED (status='pending') rows linked to the
// template via source_template_id. Pending rows don't affect balances; the user
// confirms them from Accounts or the Pending screen. Idempotent: occurrences
// already materialized (any status) are skipped via source_template_id + date.
// v1 covers fixed-amount income/expense; transfers, variable, and split
// templates are left to manual entry.
async function generateDueScheduled(exec: Exec, today: string): Promise<void> {
  const rows = await exec('SELECT * FROM scheduled_templates WHERE is_active = 1');
  const ts = new Date().toISOString();
  for (const r of rows) {
    const type = String(r.type);
    if (type === 'transfer') continue;
    if (r.amount == null) continue; // variable amount → manual
    if (Number(r.splits_enabled)) continue; // split income → manual

    const template = {
      startDate: r.start_date == null ? undefined : String(r.start_date),
      nextRun: String(r.next_run ?? ''),
      endDate: r.end_date == null ? null : String(r.end_date),
      frequency: String(r.frequency),
      dayOfMonth: Number(r.day_of_month ?? 1),
      weekDay: r.day_of_week == null ? undefined : Number(r.day_of_week),
    } as ScheduledTemplate;

    let dates = occurrencesUpTo(template, today);
    if (!dates.length) continue;

    const existing = await exec('SELECT date FROM transactions WHERE source_template_id = ?', [String(r.id)]);
    const have = new Set(existing.map((e) => String(e.date)));
    dates = dates.filter((d) => !have.has(d));
    const max = r.max_executions == null ? null : Number(r.max_executions);
    if (max != null) dates = dates.slice(0, Math.max(0, max - have.size));
    if (!dates.length) continue;

    const ledgerId = String(r.ledger_id);
    const acctId = await resolveAccountId(exec, ledgerId, String(r.account_name ?? ''));
    if (!acctId) continue;
    const [acct] = await exec('SELECT currency FROM accounts WHERE id = ?', [acctId]);
    const currency = String(acct?.currency ?? 'USD');
    const ledgerBase = await ledgerBaseCurrency(exec, ledgerId);
    const amount = (type === 'income' ? 1 : -1) * Number(r.amount);
    const kind = type === 'income' ? 'income' : 'expense';
    const categoryId = r.category_id == null ? null : String(r.category_id);

    for (const date of dates) {
      // `amount` is native (account currency); `amount_base` is the ledger-base
      // figure for reports — convert + lock the rate per occurrence date. Pending
      // rows don't move the balance (the insert trigger fires only on confirmed).
      const conv = await convertToBase(exec, amount, currency, ledgerBase, date);
      await exec(
        `INSERT INTO transactions
          (id,ledger_id,account_id,date,time,amount,amount_base,exchange_rate,
           description,category_id,transfer_group_id,kind,status,confirmed_at,
           currency,notes,source_template_id,created_at)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
        [
          newId('t'), ledgerId, acctId, date, null, amount, conv.amountBase, conv.rate,
          String(r.name ?? ''), categoryId, null, kind, 'pending', null,
          currency, null, String(r.id), ts,
        ],
      );
    }
  }
}

// Capture a transaction's date + every category/account it touches (parent +
// transaction_splits). Used by the tx-mutation cases to feed
// invalidateRollover() with the before/after state of an edit.
async function txTouches(
  exec: Exec,
  id: string,
): Promise<{ date: string; accountId: string; categoryIds: string[] } | null> {
  const [tx] = await exec('SELECT date, account_id, category_id FROM transactions WHERE id = ?', [id]);
  if (!tx) return null;
  const splits = await exec('SELECT category_id FROM transaction_splits WHERE transaction_id = ?', [id]);
  const categoryIds = new Set<string>();
  if (tx.category_id) categoryIds.add(String(tx.category_id));
  for (const s of splits) if (s.category_id) categoryIds.add(String(s.category_id));
  return { date: String(tx.date), accountId: String(tx.account_id), categoryIds: [...categoryIds] };
}

function mergeTouches(
  a: { date: string; accountId: string; categoryIds: string[] } | null,
  b: { date: string; accountId: string; categoryIds: string[] } | null,
): { earliestDate: string; categoryIds: string[]; accountIds: string[] } | null {
  if (!a && !b) return null;
  const dates = [a?.date, b?.date].filter((d): d is string => Boolean(d));
  const earliestDate = dates.sort()[0];
  const cats = new Set<string>([...(a?.categoryIds ?? []), ...(b?.categoryIds ?? [])]);
  const accts = new Set<string>([...(a ? [a.accountId] : []), ...(b ? [b.accountId] : [])]);
  return { earliestDate, categoryIds: [...cats], accountIds: [...accts] };
}

export async function applyMutation(exec: Exec, action: string, args: Args): Promise<void> {
  switch (action) {
    case 'addTransaction': {
      const id = await qAdd(exec, args as unknown as AddInput);
      const touches = await txTouches(exec, id);
      if (touches) {
        await invalidateRollover(
          exec,
          { categoryIds: touches.categoryIds, accountIds: [touches.accountId] },
          touches.date,
        );
      }
      return;
    }
    case 'adjustAccountBalance': {
      const accountId = str(args.accountId);
      const target = Number(args.targetBalance);
      if (!Number.isFinite(target)) throw new Error('Enter a target balance');
      const [acct] = await exec('SELECT ledger_id, current_balance, currency FROM accounts WHERE id = ?', [accountId]);
      if (!acct) throw new Error('Account not found');
      const delta = r2(target - Number(acct.current_balance));
      if (delta === 0) return; // already at target — no-op
      await qAdd(exec, {
        ledgerId: String(acct.ledger_id),
        accountId,
        amount: delta,
        currency: String(acct.currency),
        merchant: 'Balance adjustment',
        categoryId: null,
        date: args.date ? str(args.date) : new Date().toISOString().slice(0, 10),
        note: args.note ? str(args.note) : undefined,
        status: 'confirmed',
        kind: 'adjustment',
      });
      return;
    }
    case 'updateTransaction': {
      const id = str(args.id);
      const before = await txTouches(exec, id);
      await qUpdate(exec, id, args.patch as Parameters<typeof qUpdate>[2]);
      await recomputeForTransaction(exec, id); // an amount/date edit shifts balances
      const after = await txTouches(exec, id);
      const merged = mergeTouches(before, after);
      if (merged) {
        await invalidateRollover(
          exec,
          { categoryIds: merged.categoryIds, accountIds: merged.accountIds },
          merged.earliestDate,
        );
      }
      return;
    }
    case 'deleteTransaction': {
      const id = str(args.id);
      const before = await txTouches(exec, id);
      // Hard delete (tags/splits cascade); recompute the affected account after,
      // using the id captured before the row is gone.
      const acctId = await qDelete(exec, id);
      if (acctId) await recomputeAccount(exec, acctId);
      if (before) {
        await invalidateRollover(
          exec,
          { categoryIds: before.categoryIds, accountIds: [before.accountId] },
          before.date,
        );
      }
      return;
    }
    case 'confirmTransaction':
      await qConfirm(exec, str(args.id));
      // Confirming pulls the row into the balance (pending was excluded).
      await recomputeForTransaction(exec, str(args.id));
      return;
    case 'confirmAllPending': {
      const pendingAccts = await exec("SELECT DISTINCT account_id FROM transactions WHERE status = 'pending'");
      await exec("UPDATE transactions SET status = 'confirmed', confirmed_at = ? WHERE status = 'pending'", [
        new Date().toISOString(),
      ]);
      for (const r of pendingAccts) await recomputeAccount(exec, String(r.account_id));
      return;
    }
    // --- Named budgets (the redesign entity) + budget groups ---
    case 'createBudget': {
      const ledgerId = str(args.ledgerId || 'personal');
      const name = str(args.name).trim();
      if (!name) throw new Error('Budget name is required');
      const type: BudgetType = str(args.type) === 'income' ? 'income' : 'expense';
      const amount = Number(args.amount);
      if (!(amount > 0)) throw new Error('Budget amount must be greater than 0');
      const strList = (v: unknown): string[] => (Array.isArray(v) ? (v as unknown[]).map(str) : []);
      await qCreateBudget(exec, {
        id: str(args.id || newId('bgt')),
        ledgerId,
        groupId: args.groupId ? str(args.groupId) : null,
        name,
        type,
        amount,
        saved: args.saved != null ? Number(args.saved) : 0,
        frequency: str(args.frequency || 'monthly'),
        startDate: str(args.startDate || new Date().toISOString().slice(0, 10)),
        endDate: args.endDate ? str(args.endDate) : null,
        isRecurring: args.isRecurring != null ? Number(args.isRecurring) : type === 'income' ? 0 : 1,
        rollover: args.rollover ? 1 : 0,
        rolloverLimit: args.rolloverLimit == null ? null : Number(args.rolloverLimit),
        accountIds: strList(args.accountIds),
        categoryIds: strList(args.categoryIds),
        tagIds: strList(args.tagIds),
        warningPct: args.warningPct != null ? Number(args.warningPct) : 80,
      });
      return;
    }
    case 'updateBudget': {
      const patch = (args.patch ?? {}) as BudgetPatch;
      if (patch.name !== undefined && !str(patch.name).trim()) throw new Error('Budget name is required');
      if (patch.amount !== undefined && !(Number(patch.amount) > 0)) throw new Error('Budget amount must be greater than 0');
      // Amount-only edits on existing recurring budgets stage to
      // pending_amount instead of writing the active amount — the next
      // period boundary commits the change (BUDGET_CYCLES_PLAN §2).
      const patchKeys = Object.keys(patch).filter((k) => (patch as Record<string, unknown>)[k] !== undefined);
      const amountOnly = patchKeys.length === 1 && patchKeys[0] === 'amount';
      if (amountOnly) {
        const id = str(args.id);
        const [row] = await exec('SELECT is_recurring FROM budgets WHERE id = ?', [id]);
        if (row && Number(row.is_recurring) === 1) {
          await qStageBudgetAmount(exec, id, Number(patch.amount));
          return;
        }
      }
      await qUpdateBudget(exec, str(args.id), patch);
      return;
    }
    case 'updateBudgetCycle': {
      const patch = (args.patch ?? {}) as BudgetCyclePatch;
      const validFreqs = ['daily','weekly','biweekly','monthly','quarterly','yearly'];
      if (!validFreqs.includes(patch.frequency)) throw new Error(`Unknown frequency "${patch.frequency}"`);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(patch.startDate)) throw new Error('startDate must be YYYY-MM-DD');
      if (patch.amount !== undefined && !(Number(patch.amount) > 0)) throw new Error('Budget amount must be greater than 0');
      await qUpdateBudgetCycle(exec, str(args.id), patch);
      return;
    }
    case 'clearPendingAmount':
      await qClearPendingAmount(exec, str(args.id));
      return;
    // Entity delete uses `removeBudget` to avoid colliding with the legacy
    // per-category `deleteBudget` action above.
    case 'removeBudget':
      await qDeleteBudget(exec, str(args.id));
      return;
    case 'contributeBudget': {
      const amount = Number(args.amount);
      if (!Number.isFinite(amount)) throw new Error('Invalid contribution amount');
      await qContributeBudget(exec, str(args.id), amount);
      return;
    }
    case 'createBudgetGroup': {
      const name = str(args.name).trim();
      if (!name) throw new Error('Group name is required');
      await qCreateBudgetGroup(exec, {
        id: str(args.id || newId('bgg')),
        ledgerId: str(args.ledgerId || 'personal'),
        name,
      });
      return;
    }
    case 'updateBudgetGroup': {
      const patch = (args.patch ?? {}) as BudgetGroupPatch;
      if (patch.name !== undefined && !str(patch.name).trim()) throw new Error('Group name is required');
      await qUpdateBudgetGroup(exec, str(args.id), patch);
      return;
    }
    case 'deleteBudgetGroup':
      await qDeleteBudgetGroup(exec, str(args.id));
      return;
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
    case 'createAccountGroup': {
      const name = str(args.name).trim();
      if (!name) throw new Error('Group name is required');
      await qCreateAccountGroup(exec, {
        id: str(args.id || newId('ag')),
        ledgerId: str(args.ledgerId || 'personal'),
        name,
      });
      return;
    }
    case 'updateAccountGroup': {
      const patch = (args.patch ?? {}) as AccountGroupPatch;
      if (patch.name !== undefined && !str(patch.name).trim()) throw new Error('Group name is required');
      await qUpdateAccountGroup(exec, str(args.id), patch);
      return;
    }
    case 'deleteAccountGroup':
      await qDeleteAccountGroup(exec, str(args.id));
      return;
    case 'updateScheduledSplit': {
      await exec(
        `UPDATE scheduled_splits SET amount_pct = ?
          WHERE id = (SELECT id FROM scheduled_splits WHERE template_id = ? ORDER BY sort_order LIMIT 1 OFFSET ?)`,
        [Number(args.pct), str(args.templateId), Number(args.index)],
      );
      return;
    }
    case 'addScheduledSplit': {
      const account = str(args.account).trim();
      if (!account) throw new Error('A split needs an account');
      await qAddScheduledSplit(exec, str(args.templateId), account, Number(args.pct) || 0);
      return;
    }
    case 'removeScheduledSplit': {
      await qRemoveScheduledSplit(exec, str(args.templateId), Number(args.index));
      return;
    }
    case 'verifyCounterparty':
      await qVerifyCounterparty(exec, str(args.id));
      return;
    case 'unverifyCounterparty':
      await qUnverifyCounterparty(exec, str(args.id));
      return;
    case 'addAlias':
      await qAddAlias(exec, str(args.id), str(args.alias).trim());
      return;
    case 'removeAlias':
      await qRemoveAlias(exec, str(args.id), str(args.alias));
      return;
    case 'createTransfer':
      await createTransfer(exec, args);
      return;
    case 'updateTransfer':
      await qUpdateTransfer(exec, str(args.id), (args.patch ?? {}) as Parameters<typeof qUpdateTransfer>[2]);
      return;
    case 'createCategory': {
      const ledgerId = str(args.ledgerId || 'personal');
      const name = str(args.name).trim();
      if (!name) throw new Error('Category name is required');
      const type = args.type ? str(args.type) : 'expense';
      const icon = args.icon ? str(args.icon) : null;
      const color = args.color ? str(args.color) : null;
      const rows = await exec('SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM categories WHERE ledger_id = ?', [ledgerId]);
      await exec('INSERT INTO categories (id,ledger_id,name,type,icon,color,sort_order) VALUES (?,?,?,?,?,?,?)', [
        newId('cat'), ledgerId, name, type, icon, color, Number(rows[0]?.n ?? 0),
      ]);
      return;
    }
    case 'renameCategory': {
      const name = str(args.name).trim();
      if (!name) throw new Error('Category name is required');
      await exec('UPDATE categories SET name = ? WHERE id = ?', [name, str(args.id)]);
      return;
    }
    case 'updateCategory': {
      const patch = (args.patch ?? {}) as CategoryPatch;
      if (patch.name !== undefined && !str(patch.name).trim()) throw new Error('Category name is required');
      await qUpdateCategory(exec, str(args.id), patch);
      return;
    }
    case 'updateTag': {
      const patch = (args.patch ?? {}) as TagPatch;
      if (patch.name !== undefined && !str(patch.name).trim()) throw new Error('Tag name is required');
      await qUpdateTag(exec, str(args.id), patch);
      return;
    }
    case 'updateScheduled': {
      const patch = (args.patch ?? {}) as ScheduledPatch;
      if (patch.name !== undefined && !str(patch.name).trim()) throw new Error('Template name is required');
      await qUpdateScheduled(exec, str(args.id), patch);
      return;
    }
    case 'updateCounterparty': {
      const patch = (args.patch ?? {}) as CounterpartyPatch;
      if (patch.name !== undefined && !str(patch.name).trim()) throw new Error('Merchant name is required');
      await qUpdateCounterparty(exec, str(args.id), patch);
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
    case 'setTransactionSplits': {
      const txId = str(args.id);
      const raw = Array.isArray(args.splits) ? (args.splits as unknown[]) : [];
      const splits: NewSplitInput[] = raw.map((s) => {
        const o = s as Record<string, unknown>;
        return {
          categoryId: o.categoryId == null ? null : str(o.categoryId),
          amount: Number(o.amount),
          description: o.description == null ? null : str(o.description),
        };
      });
      const before = await txTouches(exec, txId);
      await qSetTransactionSplits(exec, txId, splits);
      const after = await txTouches(exec, txId);
      const merged = mergeTouches(before, after);
      if (merged) {
        await invalidateRollover(
          exec,
          { categoryIds: merged.categoryIds, accountIds: merged.accountIds },
          merged.earliestDate,
        );
      }
      return;
    }
    case 'deleteCategory':
      await qDeleteCategory(exec, str(args.id));
      return;
    case 'deleteTag':
      await qDeleteTag(exec, str(args.id));
      return;
    case 'createScheduled': {
      const name = str(args.name).trim();
      if (!name) throw new Error('Template name is required');
      const type = str(args.type || 'expense');
      if (!['income', 'expense', 'transfer'].includes(type)) throw new Error(`Unknown type "${type}"`);
      const frequency = str(args.frequency || 'monthly');
      if (!['once', 'daily', 'weekly', 'biweekly', 'monthly', 'quarterly', 'yearly'].includes(frequency)) {
        throw new Error(`Unknown frequency "${frequency}"`);
      }
      const account = str(args.account ?? '').trim();
      if (!account) throw new Error('An account is required');
      await qCreateScheduled(exec, {
        id: str(args.id || newId('sch')),
        ledgerId: str(args.ledgerId || 'personal'),
        name,
        type,
        amount: args.amount == null || args.amount === '' ? null : Number(args.amount),
        frequency,
        dayOfMonth: Number(args.dayOfMonth) || 1,
        weekDay: args.weekDay != null ? Number(args.weekDay) : null,
        account,
        from: type === 'transfer' && args.from ? str(args.from).trim() : null,
        autoPost: args.autoPost ? 1 : 0,
        color: args.color ? str(args.color) : null,
        category: args.category ? str(args.category) : null,
        startDate: args.startDate ? str(args.startDate) : new Date().toISOString().slice(0, 10),
        endDate: args.endDate ? str(args.endDate) : null,
        maxExecutions: args.maxExecutions != null ? Number(args.maxExecutions) : null,
      });
      return;
    }
    case 'deleteScheduled':
      await qDeleteScheduled(exec, str(args.id));
      return;
    case 'deleteTransfer':
      await qDeleteTransfer(exec, str(args.id));
      return;
    case 'createCounterparty': {
      const name = str(args.name).trim();
      if (!name) throw new Error('Merchant name is required');
      await qCreateCounterparty(exec, {
        id: str(args.id || newId('cp')),
        ledgerId: str(args.ledgerId || 'personal'),
        name,
        category: args.category ? str(args.category) : null,
      });
      return;
    }
    case 'deleteCounterparty':
      await qDeleteCounterparty(exec, str(args.id));
      return;
    case 'setExchangeRate': {
      const date = str(args.date);
      const currency = str(args.currency).trim().toUpperCase();
      const rate = Number(args.rate);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error('Date must be YYYY-MM-DD');
      if (!currency) throw new Error('Currency is required');
      if (!(rate > 0)) throw new Error('Rate must be greater than 0');
      if (currency === 'USD') throw new Error('USD is the hub currency and is not stored');
      await qSetExchangeRate(exec, { date, currency, rate, source: args.source ? str(args.source) : null });
      // Cache-prune to the rolling retention window on every write.
      await pruneOldRates(exec);
      return;
    }
    case 'deleteExchangeRate':
      await qDeleteExchangeRate(exec, str(args.date), str(args.currency).toUpperCase());
      return;
    case 'postScheduled':
      await postScheduled(exec, args);
      return;
    case 'setMobileTabIds': {
      const ids = Array.isArray(args.ids) ? args.ids.filter((v): v is string => typeof v === 'string') : [];
      await setAppState(exec, 'mobileTabs', JSON.stringify(ids));
      return;
    }
    case 'setDisplayCurrency': {
      // Merge the single ledger's choice into the stored map so a concurrent
      // edit to a different ledger isn't clobbered.
      const ledgerId = str(args.ledgerId);
      const currency = str(args.currency);
      const raw = await getAppState(exec, 'displayCurrencyByLedger');
      let map: Record<string, string> = {};
      if (raw) {
        try {
          const parsed = JSON.parse(raw);
          if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) map = parsed as Record<string, string>;
        } catch {
          /* ignore malformed value */
        }
      }
      map[ledgerId] = currency;
      await setAppState(exec, 'displayCurrencyByLedger', JSON.stringify(map));
      return;
    }
    case 'generateDueScheduled': {
      const today = args.today ? str(args.today) : new Date().toISOString().slice(0, 10);
      await generateDueScheduled(exec, today);
      return;
    }
    case 'reset':
      await resetDb(exec);
      return;
    default:
      throw new Error(`Unknown action: ${action}`);
  }
}
