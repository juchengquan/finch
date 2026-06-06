// Server-side handlers for every store action, operating on the same state
// representation that projectState reads: transactions live in the transactions
// table; pending/scheduled/override slices live in app_state. Each handler is a
// pure SQL mutation; the API route persists the file and returns the new state.

import type { Exec } from './repo';
import {
  getScheduled,
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
import {
  createRule as qCreateRule,
  updateRule as qUpdateRule,
  deleteRule as qDeleteRule,
  type RulePatchInput,
} from './queries/rules';
import type { Action, Condition, NewRule } from '@/lib/rules/types';
import { deleteCategory as qDeleteCategory, updateCategory as qUpdateCategory, type CategoryPatch } from './queries/categories';
import { setTransactionSplits as qSetTransactionSplits, type NewSplitInput } from './queries/transactionSplits';
import {
  deleteCounterparty as qDeleteCounterparty,
  updateCounterparty as qUpdateCounterparty,
  createCounterparty as qCreateCounterparty,
  verifyCounterparty as qVerifyCounterparty,
  unverifyCounterparty as qUnverifyCounterparty,
  resolveCounterpartyIdByName,
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
import { parseInstallmentTotal } from '@/lib/installment';
import { convertToBase } from './queries/rates';
import {
  createHolding as qCreateHolding,
  updateHolding as qUpdateHolding,
  setHoldingPrice as qSetHoldingPrice,
  deleteHolding as qDeleteHolding,
  type HoldingPatch,
} from './queries/holdings';
import {
  addTransaction as qAdd,
  updateTransaction as qUpdate,
  deleteTransactionRow as qDelete,
  confirmTransaction as qConfirm,
  confirmPendingWithMerchant as qConfirmWithMerchant,
  insertTxRow,
  type AddInput,
} from './queries/transactions';
import { seedReference, insertTransactions, seedTransactionTags } from './seed';
import transactionsData from '@/data/transactions.json';
import type { Tx } from '@/lib/store';

const RESET_TABLES = [
  'holdings',
  'transactions',
  'scheduled_splits',
  'scheduled_templates',
  'tags',
  'budgets',
  'budget_groups',
  'transfer_groups',
  'counterparties',
  'categories',
  'accounts',
  'account_groups',
  'exchange_rates',
  'rules',
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

// Turn a UNIQUE violation from a known dedup index into a human message, so a
// double-submit surfaces as a clear toast instead of a raw 500. SQLite reports
// the violated index by its *columns*, not its name (e.g. "UNIQUE constraint
// failed: budgets.ledger_id, budgets.name, ..."), so we match on a distinctive
// column from each backstop index (idx_txn_dedup / idx_budget_unique in
// schema.ts, #5). Any other error propagates unchanged.
const DEDUP_MESSAGES: { signature: string; message: string }[] = [
  { signature: 'transactions.account_id, transactions.date', message: 'This looks like a duplicate — an identical transaction already exists.' },
  { signature: 'budgets.ledger_id, budgets.name', message: 'A budget with this name and cycle already exists.' },
];
async function withDedupMessage<T>(run: () => Promise<T>): Promise<T> {
  try {
    return await run();
  } catch (err) {
    const msg = String((err as Error)?.message ?? err);
    if (msg.includes('UNIQUE constraint failed')) {
      for (const { signature, message } of DEDUP_MESSAGES) {
        if (msg.includes(signature)) throw new Error(message);
      }
    }
    throw err;
  }
}

/** Reject creating/moving a category under one that itself has a parent —
 *  the taxonomy is exactly 2 levels deep. */
async function assertCanBeParent(exec: Exec, parentId: string): Promise<void> {
  const rows = await exec('SELECT parent_id FROM categories WHERE id = ?', [parentId]);
  if (!rows.length) throw new Error('Parent category does not exist');
  if (rows[0].parent_id != null) throw new Error('Categories nest only two levels deep');
}

async function postSingle(
  exec: Exec,
  ledgerId: string,
  accountId: string,
  amount: number,
  description: string,
  date: string,
  sourceTemplateId: string | null = null,
  categoryId: string | null = null,
): Promise<void> {
  await insertTxRow(exec, {
    ledgerId, accountId, date,
    amount, description, categoryId,
    kind: amount > 0 ? 'income' : 'expense',
    sourceTemplateId,
  });
}

async function postScheduled(exec: Exec, args: Args): Promise<void> {
  const templateId = str(args.templateId);
  const ledgerId = 'personal';
  const t = await getScheduled(exec, templateId);
  if (!t) throw new Error('Template not found');
  // Refuse to post more than the installment plan calls for. We block before
  // we touch the account, so a fully-paid plan can't sneak an extra payment
  // through. installmentPaid is the derived count of confirmed posts.
  if (t.installmentTotal != null && (t.installmentPaid ?? 0) >= t.installmentTotal) {
    throw new Error(`"${t.name}" has finished its ${t.installmentTotal}-payment plan`);
  }
  const date = new Date().toISOString().slice(0, 10);
  // The posted transaction's description: the template's own description, or
  // its name as a fallback.
  const desc = t.description || t.name;

  if (t.type === 'transfer') {
    if (!t.fromAccountId || !t.accountId) throw new Error(`"${t.name}" is missing an account`);
    await createTransfer(exec, { fromAccountId: t.fromAccountId, toAccountId: t.accountId, fromAmount: t.amount ?? 0, date, note: desc });
    return;
  }

  if (t.amount == null) throw new Error(`"${t.name}" has a variable amount — add it manually`);
  const sign = t.type === 'income' ? 1 : -1;

  if (t.type === 'income' && t.splits?.length) {
    let posted = 0;
    for (const sp of t.splits) {
      const portion = sp.abs != null ? sp.abs : (t.amount * (sp.pct ?? 0)) / 100;
      if (!portion) continue;
      await postSingle(exec, ledgerId, sp.accountId, portion, `${desc} · ${sp.label}`, date, t.id, t.category ?? null);
      posted++;
    }
    if (!posted) throw new Error(`No split amounts to post for "${t.name}"`);
    return;
  }

  await postSingle(exec, ledgerId, t.accountId, sign * t.amount, desc, date, t.id, t.category ?? null);
}

// Create a transfer: a transfer_group plus two confirmed transactions (out/in)
// that share its id, so it moves both account balances and shows in Activity.
async function createTransfer(exec: Exec, args: Args): Promise<void> {
  const fromId = str(args.fromAccountId);
  const toId = str(args.toAccountId);
  const fromAmount = Math.abs(Number(args.fromAmount));
  const explicitToAmount = args.toAmount != null ? Math.abs(Number(args.toAmount)) : null;
  const date = str(args.date);
  const time = args.time ? str(args.time) : null;
  const note = args.note ? str(args.note) : null;
  // Optional link back to the scheduled template — set when this transfer was
  // auto-generated (or manually posted) from a recurring entry. Stamped on
  // both legs so the dedupe / cap math in generateDueScheduled works.
  const sourceTemplateId = args.sourceTemplateId ? str(args.sourceTemplateId) : null;
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
  const ts = new Date().toISOString();
  await exec(
    'INSERT INTO transfer_groups (id,ledger_id,from_currency,to_currency,exchange_rate,notes,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)',
    [tgId, ledgerId, fromCurrency, toCurrency, rate, note, ts, ts],
  );
  await insertTxRow(exec, {
    ledgerId, accountId: fromId, date, time, amount: -fromAmount,
    description: `Transfer to ${String(to.name)}`,
    currency: fromCurrency, transferGroupId: tgId, notes: note, kind: 'transfer',
    sourceTemplateId,
  });
  await insertTxRow(exec, {
    ledgerId, accountId: toId, date, time, amount: toAmount,
    description: `Transfer from ${String(from.name)}`,
    currency: toCurrency, transferGroupId: tgId, notes: note, kind: 'transfer',
    sourceTemplateId,
  });
}

// Auto-generate transactions for scheduled templates whose occurrences are due
// (on/before `today`). Income/expense rows materialize as UNCONFIRMED (the
// user confirms them from Accounts or the Pending screen — pending rows don't
// affect balances). Transfers materialize as CONFIRMED via createTransfer
// because that's the only mode it supports today and bank transfers truly do
// happen on schedule; the user can delete one if it shouldn't have run.
// Idempotent: occurrences already materialized (any status) are skipped via
// source_template_id + date. Variable-amount and split-income templates are
// left to manual entry.
async function generateDueScheduled(exec: Exec, today: string): Promise<void> {
  const rows = await exec('SELECT * FROM scheduled_templates WHERE is_active = 1');
  const ts = new Date().toISOString();
  for (const r of rows) {
    const type = String(r.kind);
    if (r.amount == null) continue; // variable amount → manual
    if (Number(r.splits_enabled)) continue; // split income → manual
    if (type === 'transfer' && r.from_account_id == null) continue; // transfer missing source → manual

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
    // Installment plans cap at installment_total just like max_executions, so a
    // 24-month phone contract stops generating after 24 occurrences without the
    // user having to remember to flip is_active.
    const installmentTotal = r.installment_total == null ? null : Number(r.installment_total);
    if (installmentTotal != null) dates = dates.slice(0, Math.max(0, installmentTotal - have.size));
    if (!dates.length) continue;

    const ledgerId = String(r.ledger_id);
    const acctId = String(r.account_id);
    const description = String(r.description ?? r.name ?? '');

    if (type === 'transfer') {
      // Cross-account recurring: one createTransfer per due date, both legs
      // stamped with source_template_id so the dedupe + cap math above keeps
      // working (the Set dedupes the two legs that share a date). Same-currency
      // transfers infer the to-amount; cross-currency picks the rate at the
      // occurrence date via convertToBase (matches the manual transfer path).
      const fromAccountId = String(r.from_account_id);
      const fromAmount = Math.abs(Number(r.amount));
      const sourceTemplateId = String(r.id);
      for (const date of dates) {
        await createTransfer(exec, {
          fromAccountId, toAccountId: acctId, fromAmount, date,
          note: description || null, sourceTemplateId,
        });
      }
      continue;
    }

    const amount = (type === 'income' ? 1 : -1) * Number(r.amount);
    const kind = type === 'income' ? 'income' : 'expense';
    const categoryId = r.category_id == null ? null : String(r.category_id);
    // Counterparty is resolved once per template (the description is the same
    // for every occurrence); insertTxRow then receives a concrete id rather
    // than re-running the lookup on each date.
    const cpId = await resolveCounterpartyIdByName(exec, ledgerId, description);
    for (const date of dates) {
      await insertTxRow(exec, {
        ledgerId, accountId: acctId, date,
        amount, description, categoryId, kind,
        status: 'pending',
        sourceTemplateId: String(r.id),
        counterpartyId: cpId,
        timestamp: ts,
      });
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
      const id = await withDedupMessage(() => qAdd(exec, args as unknown as AddInput));
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
      // `source` distinguishes a manual adjust from one posted by the
      // reconcile flow's "post remainder" escape hatch; today it only
      // affects the merchant label, but the value is preserved for future
      // history filtering.
      const source = args.source === 'reconcile' ? 'reconcile' : 'manual';
      await qAdd(exec, {
        ledgerId: String(acct.ledger_id),
        accountId,
        amount: delta,
        currency: String(acct.currency),
        merchant: source === 'reconcile' ? 'Reconciliation adjustment' : 'Balance adjustment',
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
      // qUpdate may return a non-null `oldAccountId` when the patch moved the
      // row to a different account — in which case the source account's
      // balance no longer includes this row and must be recomputed.
      const { oldAccountId } = await qUpdate(exec, id, args.patch as Parameters<typeof qUpdate>[2]);
      await recomputeForTransaction(exec, id); // recompute the row's (now-NEW) account
      if (oldAccountId) {
        await recomputeAccount(exec, oldAccountId);
      }
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
    case 'setCleared': {
      // Toggle a single transaction's cleared-against-statement flag. One UPDATE,
      // no recompute — clearing doesn't move balances.
      const id = str(args.id);
      const cleared = args.cleared === true;
      await exec(
        cleared
          ? "UPDATE transactions SET cleared_at = datetime('now') WHERE id = ?"
          : 'UPDATE transactions SET cleared_at = NULL WHERE id = ?',
        [id],
      );
      return;
    }
    case 'reconcileAccount': {
      // Stamp the reconcile checkpoint on the account; optionally post an
      // Adjustment for the remaining gap so the cleared balance lands exactly
      // on the statement target.
      const accountId = str(args.accountId);
      const statementBalance = Number(args.statementBalance);
      if (!Number.isFinite(statementBalance)) throw new Error('Statement balance is required');
      const statementDate = args.statementDate ? str(args.statementDate) : new Date().toISOString().slice(0, 10);
      const postAdjustment = args.postAdjustment === true;

      // Optional remainder. We compute it server-side from the actual cleared
      // sum so the client can't trick us into posting a phantom delta.
      if (postAdjustment) {
        const [acct] = await exec(
          'SELECT ledger_id, currency, opening_balance FROM accounts WHERE id = ?',
          [accountId],
        );
        if (!acct) throw new Error('Account not found');
        const opening = Number(acct.opening_balance ?? 0);
        const [sum] = await exec(
          `SELECT COALESCE(SUM(
             CASE WHEN currency = ? THEN amount ELSE amount_base END
           ), 0) AS s
             FROM transactions
            WHERE account_id = ?
              AND status = 'confirmed'
              AND cleared_at IS NOT NULL`,
          [String(acct.currency), accountId],
        );
        const cleared = r2(opening + Number(sum.s));
        const delta = r2(statementBalance - cleared);
        if (Math.abs(delta) >= 0.005) {
          await qAdd(exec, {
            ledgerId: String(acct.ledger_id),
            accountId,
            amount: delta,
            currency: String(acct.currency),
            merchant: 'Reconciliation adjustment',
            categoryId: null,
            date: statementDate,
            note: undefined,
            status: 'confirmed',
            kind: 'adjustment',
          });
          // Mark the adjustment itself as cleared — it's part of this
          // reconciliation by construction. SQLite doesn't allow ORDER BY in
          // UPDATE, so we pick the just-inserted id via a subquery.
          await exec(
            `UPDATE transactions
                SET cleared_at = datetime('now')
              WHERE id = (
                SELECT id FROM transactions
                 WHERE account_id = ?
                   AND status = 'confirmed'
                   AND kind = 'adjustment'
                   AND cleared_at IS NULL
                 ORDER BY created_at DESC
                 LIMIT 1
              )`,
            [accountId],
          );
        }
      }
      await exec(
        `UPDATE accounts
            SET last_reconciled_at = ?,
                last_reconciled_balance = ?,
                updated_at = datetime('now')
          WHERE id = ?`,
        [statementDate, statementBalance, accountId],
      );
      return;
    }
    case 'bulkRecategorize': {
      // Category-only bulk update: amounts/dates/accounts don't move, so we
      // skip account balance recompute. Rollover IS affected — invalidate it
      // for both the old and the new category from the earliest affected date.
      const ids = Array.isArray(args.ids) ? args.ids.map(str) : [];
      const categoryId = args.categoryId == null ? null : str(args.categoryId);
      if (!ids.length) return;
      const placeholders = ids.map(() => '?').join(',');
      const before = await exec(
        `SELECT category_id, date FROM transactions WHERE id IN (${placeholders})`,
        ids,
      );
      await exec(
        `UPDATE transactions SET category_id = ? WHERE id IN (${placeholders})`,
        [categoryId, ...ids],
      );
      const cats = new Set<string>();
      if (categoryId) cats.add(categoryId);
      let earliest = '';
      for (const r of before) {
        if (r.category_id != null) cats.add(String(r.category_id));
        const d = String(r.date ?? '');
        if (d && (!earliest || d < earliest)) earliest = d;
      }
      if (cats.size > 0 && earliest) {
        await invalidateRollover(exec, { categoryIds: [...cats], accountIds: [] }, earliest);
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
    case 'confirmPendingWithMerchant': {
      await qConfirmWithMerchant(exec, str(args.id), {
        counterpartyId: args.counterpartyId != null ? str(args.counterpartyId) : null,
        newCounterpartyName: args.newCounterpartyName != null ? str(args.newCounterpartyName) : null,
      });
      await recomputeForTransaction(exec, str(args.id));
      return;
    }
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
      await withDedupMessage(() => qCreateBudget(exec, {
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
        warningPct: args.warningPct != null ? Number(args.warningPct) : 80,
      }));
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
      const accountId = str(args.accountId).trim();
      if (!accountId) throw new Error('A split needs an account');
      await qAddScheduledSplit(exec, str(args.templateId), accountId, Number(args.pct) || 0);
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
      const parentId = args.parentId ? str(args.parentId) : null;
      if (parentId != null) await assertCanBeParent(exec, parentId);
      const rows = await exec('SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM categories WHERE ledger_id = ?', [ledgerId]);
      await exec("INSERT INTO categories (id,ledger_id,parent_id,name,kind,icon,color,sort_order,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,datetime('now'),datetime('now'))", [
        newId('cat'), ledgerId, parentId, name, type, icon, color, Number(rows[0]?.n ?? 0),
      ]);
      return;
    }
    case 'updateCategory': {
      const id = str(args.id);
      const patch = (args.patch ?? {}) as CategoryPatch;
      if (patch.name !== undefined && !str(patch.name).trim()) throw new Error('Category name is required');
      if (patch.parentId !== undefined && patch.parentId !== null) {
        if (patch.parentId === id) throw new Error('A category cannot be its own parent');
        await assertCanBeParent(exec, patch.parentId);
        // Re-parenting a row that itself has children would create 3 levels.
        const kids = await exec('SELECT COUNT(*) AS n FROM categories WHERE parent_id = ?', [id]);
        if (Number(kids[0]?.n ?? 0) > 0) throw new Error('Move or promote this category\'s children before nesting it under another parent');
      }
      await qUpdateCategory(exec, id, patch);
      return;
    }
    case 'updateTag': {
      const patch = (args.patch ?? {}) as TagPatch;
      if (patch.name !== undefined && !str(patch.name).trim()) throw new Error('Tag name is required');
      await qUpdateTag(exec, str(args.id), patch);
      return;
    }
    case 'updateScheduled': {
      const patch = { ...(args.patch ?? {}) } as ScheduledPatch & { installmentTotal?: unknown };
      if (patch.name !== undefined && !str(patch.name).trim()) throw new Error('Template name is required');
      if ('installmentTotal' in patch) {
        patch.installmentTotal = parseInstallmentTotal(patch.installmentTotal);
      }
      await qUpdateScheduled(exec, str(args.id), patch);
      return;
    }
    case 'updateCounterparty': {
      const patch = (args.patch ?? {}) as CounterpartyPatch;
      if (patch.name !== undefined && !str(patch.name).trim()) throw new Error('Merchant name is required');
      await qUpdateCounterparty(exec, str(args.id), patch);
      return;
    }
    case 'createRule': {
      const ledgerId = str(args.ledgerId || 'personal');
      const condition = args.condition as Condition;
      const actions = (Array.isArray(args.actions) ? args.actions : []) as Action[];
      if (!condition) throw new Error('Rule condition is required');
      const input: NewRule = {
        ledgerId,
        name: args.name == null ? null : str(args.name),
        priority: args.priority != null ? Number(args.priority) : 100,
        condition,
        actions,
        isActive: args.isActive !== false,
        runOnEdit: args.runOnEdit === true,
      };
      const id = args.id ? str(args.id) : newId('rule');
      await qCreateRule(exec, id, input);
      return;
    }
    case 'updateRule': {
      const patch = (args.patch ?? {}) as RulePatchInput;
      await qUpdateRule(exec, str(args.id), patch);
      return;
    }
    case 'deleteRule': {
      await qDeleteRule(exec, str(args.id));
      return;
    }
    case 'backfillRule': {
      // Apply one rule against every confirmed transaction in its ledger.
      // Mirrors insertTxRow's post-rule plumbing: set_* fields move on the
      // row, add_tag rows go into transaction_tags. Splits and category-
      // change rollover invalidations are out of scope for this PR — set_*
      // covers the 80% case (the "rename + categorise" workflow).
      const ruleId = str(args.id);
      const [{ listActiveRules }, { applyRules }, { resolveCounterpartyIdByName }] = await Promise.all([
        import('./queries/rules'),
        import('@/lib/rules/engine'),
        import('./queries/counterparties'),
      ]);
      // Load just this rule from the DB (active OR inactive — explicit backfill
      // shouldn't silently skip a disabled rule the user just enabled).
      const ruleRows = await exec('SELECT * FROM rules WHERE id = ?', [ruleId]);
      if (!ruleRows.length) throw new Error('Rule not found');
      const { rowToRule } = await import('./queries/rules');
      const rule = rowToRule(ruleRows[0]);

      // We walk transactions in the rule's ledger only (FK is ON DELETE
      // CASCADE; a deleted ledger can't have orphan rules), confirmed only
      // (pending rows haven't really happened yet — the user can re-confirm
      // to trigger them through the insert hook).
      const { listActiveRules: _unused } = { listActiveRules }; void _unused;
      const txnRows = await exec(
        `SELECT id, ledger_id, account_id, date, amount, amount_base, description, category_id,
                counterparty_id, currency, kind, notes, applied_rule_ids, time
           FROM transactions
          WHERE ledger_id = ? AND status = 'confirmed'`,
        [rule.ledgerId],
      );
      let matched = 0;
      for (const r of txnRows) {
        // Build a minimal Tx synthesizing what evaluateCondition reads.
        const tx = {
          id: String(r.id),
          merchant: String(r.description ?? ''),
          category: r.category_id == null ? null : String(r.category_id),
          amount: Number(r.amount_base),
          nativeAmount: Number(r.amount),
          currency: r.currency == null ? undefined : String(r.currency),
          account: String(r.account_id),
          date: String(r.date),
          time: r.time == null ? undefined : String(r.time),
          note: r.notes == null ? undefined : String(r.notes),
          pending: false,
          kind: r.kind == null ? undefined : (String(r.kind) as 'income' | 'expense' | 'transfer' | 'adjustment' | 'refund'),
          ledgerId: String(r.ledger_id),
          counterpartyId: r.counterparty_id == null ? undefined : String(r.counterparty_id),
        };
        const patch = applyRules(tx, [rule]);
        if (!patch.appliedRuleIds.includes(rule.id)) continue;
        matched++;

        // Apply the patch's set_* fields via a single UPDATE.
        const sets: string[] = [];
        const bind: (string | number | null)[] = [];
        if (patch.categoryId !== undefined) { sets.push('category_id = ?'); bind.push(patch.categoryId); }
        if (patch.counterpartyId !== undefined) { sets.push('counterparty_id = ?'); bind.push(patch.counterpartyId); }
        if (patch.merchant !== undefined) {
          sets.push('description = ?');
          bind.push(patch.merchant);
          // Re-resolve the counterparty link to match the new description.
          const cpId = await resolveCounterpartyIdByName(exec, rule.ledgerId, patch.merchant);
          sets.push('counterparty_id = ?');
          bind.push(cpId);
        }
        if (patch.note !== undefined) { sets.push('notes = ?'); bind.push(patch.note); }
        if (patch.kind !== undefined) { sets.push('kind = ?'); bind.push(patch.kind); }

        // Merge applied_rule_ids — preserve the previous list (audit trail);
        // append the rule id if it's not already there.
        const prevRuleIds: string[] = (() => {
          if (r.applied_rule_ids == null) return [];
          try {
            const v = JSON.parse(String(r.applied_rule_ids));
            return Array.isArray(v) ? v.map(String) : [];
          } catch {
            return [];
          }
        })();
        if (!prevRuleIds.includes(rule.id)) prevRuleIds.push(rule.id);
        sets.push('applied_rule_ids = ?');
        bind.push(JSON.stringify(prevRuleIds));

        if (sets.length > 1 /* at least one user-visible field changed */) {
          sets.push("updated_at = datetime('now')");
          bind.push(tx.id);
          await exec(`UPDATE transactions SET ${sets.join(', ')} WHERE id = ?`, bind);
        }
        if (patch.tagIdsAdd?.length) {
          for (const tagId of patch.tagIdsAdd) {
            await exec(
              'INSERT OR IGNORE INTO transaction_tags (transaction_id, tag_id) VALUES (?, ?)',
              [tx.id, tagId],
            );
          }
        }
      }
      // Stamp the rule's last_applied_at so the /rules row shows "N days ago".
      const { markRuleApplied } = await import('./queries/rules');
      await markRuleApplied(exec, rule.id);
      // The result count travels back to the caller via the standard
      // projectState response — the page derives "matched: N" from the
      // updated applied_rule_ids on the transactions and the
      // last_applied_at stamp on the rule.
      void matched;
      return;
    }
    case 'createTag': {
      const name = str(args.name).trim();
      if (!name) throw new Error('Tag name is required');
      await exec("INSERT INTO tags (id,ledger_id,name,color,created_at,updated_at) VALUES (?,?,?,?,datetime('now'),datetime('now'))", [
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
      const accountId = str(args.accountId ?? '').trim();
      if (!accountId) throw new Error('An account is required');
      await qCreateScheduled(exec, {
        id: str(args.id || newId('sch')),
        ledgerId: str(args.ledgerId || 'personal'),
        name,
        description: args.description ? str(args.description).trim() : null,
        type,
        amount: args.amount == null || args.amount === '' ? null : Number(args.amount),
        frequency,
        dayOfMonth: Number(args.dayOfMonth) || 1,
        weekDay: args.weekDay != null ? Number(args.weekDay) : null,
        accountId,
        fromAccountId: type === 'transfer' && args.fromAccountId ? str(args.fromAccountId).trim() : null,
        autoPost: args.autoPost ? 1 : 0,
        color: args.color ? str(args.color) : null,
        category: args.category ? str(args.category) : null,
        startDate: args.startDate ? str(args.startDate) : new Date().toISOString().slice(0, 10),
        endDate: args.endDate ? str(args.endDate) : null,
        maxExecutions: args.maxExecutions != null ? Number(args.maxExecutions) : null,
        installmentTotal: parseInstallmentTotal(args.installmentTotal),
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
    case 'createHolding': {
      const accountId = str(args.accountId).trim();
      const symbol = str(args.symbol).trim().toUpperCase();
      const shares = Number(args.shares);
      const costBasis = Number(args.costBasis);
      if (!accountId) throw new Error('An investment account is required');
      if (!symbol) throw new Error('Symbol is required');
      if (!(shares > 0)) throw new Error('Shares must be greater than 0');
      if (!(costBasis >= 0)) throw new Error('Cost basis must be 0 or greater');
      const [acct] = await exec('SELECT type, currency, ledger_id FROM accounts WHERE id = ?', [accountId]);
      if (!acct) throw new Error('Account not found');
      if (String(acct.type) !== 'investment') throw new Error('Holdings can only be added to an investment account');
      const ledgerId = str(args.ledgerId || acct.ledger_id || 'personal');
      // Lock currency to the account's so cross-position sums in the
      // account's currency stay correct without per-row conversion. A
      // mismatched override is rejected outright rather than silently
      // coerced — surfaces the misuse instead of corrupting totals.
      const accountCurrency = String(acct.currency ?? 'USD');
      const requested = args.currency ? str(args.currency).trim().toUpperCase() : accountCurrency;
      if (requested !== accountCurrency) {
        throw new Error(`Holding currency must match the account currency (${accountCurrency})`);
      }
      const currency = accountCurrency;
      await qCreateHolding(exec, {
        id: str(args.id || newId('h')),
        ledgerId,
        accountId,
        symbol,
        name: args.name ? str(args.name).trim() : null,
        shares,
        costBasis,
        currency,
        lastPrice: args.lastPrice == null || args.lastPrice === '' ? null : Number(args.lastPrice),
        lastPriceDate: args.lastPriceDate ? str(args.lastPriceDate) : null,
        notes: args.notes ? str(args.notes) : null,
      });
      return;
    }
    case 'updateHolding': {
      const id = str(args.id);
      const patch = (args.patch ?? {}) as Record<string, unknown>;
      const normalized: HoldingPatch = {};
      if (patch.symbol !== undefined) {
        const sym = str(patch.symbol).trim().toUpperCase();
        if (!sym) throw new Error('Symbol cannot be empty');
        normalized.symbol = sym;
      }
      if (patch.name !== undefined) normalized.name = patch.name == null ? null : str(patch.name);
      if (patch.shares !== undefined) {
        const s = Number(patch.shares);
        if (!(s > 0)) throw new Error('Shares must be greater than 0');
        normalized.shares = s;
      }
      if (patch.costBasis !== undefined) {
        const c = Number(patch.costBasis);
        if (!(c >= 0)) throw new Error('Cost basis must be 0 or greater');
        normalized.costBasis = c;
      }
      if (patch.notes !== undefined) normalized.notes = patch.notes == null ? null : str(patch.notes);
      await qUpdateHolding(exec, id, normalized);
      return;
    }
    case 'setHoldingPrice': {
      const id = str(args.id);
      const price = args.price == null ? null : Number(args.price);
      // Clearing the price always clears the date too — the UI never sends a
      // partial-null pair, so this just enforces the "both halves move
      // together" invariant rather than rejecting at the boundary.
      const date = price == null ? null : args.date == null ? null : str(args.date);
      if (price !== null && !(price >= 0)) throw new Error('Price must be 0 or greater');
      if (date !== null && !/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error('Date must be YYYY-MM-DD');
      await qSetHoldingPrice(exec, id, price, date);
      return;
    }
    case 'deleteHolding':
      await qDeleteHolding(exec, str(args.id));
      return;
    case 'changeLedgerBase': {
      const ledgerId = str(args.ledgerId);
      const newBase = str(args.newBase).trim().toUpperCase();
      if (!ledgerId) throw new Error('ledgerId is required');
      if (!/^[A-Z]{3}$/.test(newBase)) throw new Error('newBase must be a 3-letter ISO code');
      const [row] = await exec('SELECT base_currency FROM ledgers WHERE id = ?', [ledgerId]);
      if (!row) throw new Error('Ledger not found');
      if (String(row.base_currency) === newBase) return; // no-op
      const { recomputeAmountBases } = await import('./queries/ledgers');
      await recomputeAmountBases(exec, ledgerId, newBase);
      return;
    }
    default:
      throw new Error(`Unknown action: ${action}`);
  }
}
