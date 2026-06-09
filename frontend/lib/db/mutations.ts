// Server-side handlers for every store action, operating on the same state
// representation that projectState reads: transactions live in the transactions
// table; pending/scheduled/override slices live in app_state. Each handler is a
// pure SQL mutation; the API route persists the file and returns the new state.

import type { Exec } from './core/repo';
import { ensureSystemCategories } from './core/entries';
import {
  getScheduled,
  deleteScheduled,
  updateScheduled,
  createScheduled,
  addScheduledSplit,
  removeScheduledSplit,
  type ScheduledPatch,
} from './domain/scheduled/queries';
import {
  createAccount,
  updateAccount,
  archiveAccount,
  unarchiveAccount,
  deleteAccount,
  type AccountPatch,
} from './domain/accounts/queries';
import {
  createAccountGroup,
  updateAccountGroup,
  deleteAccountGroup,
  type AccountGroupPatch,
} from './domain/accountGroups/queries';
import { deleteTag, updateTag, type TagPatch } from './domain/tags/queries';
import {
  createRule,
  updateRule,
  deleteRule,
  type RulePatchInput,
} from './domain/rules/queries';
import type { Action, Condition, NewRule } from '@/lib/rules/types';
import { deleteCategory, updateCategory, type CategoryPatch } from './domain/categories/queries';
// qSetTransactionSplits removed: setTransactionSplits is now inline via rebuildEntry (B3b)
import {
  deleteCounterparty,
  updateCounterparty,
  createCounterparty,
  verifyCounterparty,
  unverifyCounterparty,
  resolveCounterpartyIdByName,
  type CounterpartyPatch,
} from './domain/counterparties/queries';
import { deleteTransfer, updateTransfer } from './domain/transfers/queries';
import { setExchangeRate, deleteExchangeRate } from './domain/_app/system';
import { getAppState, setAppState } from './domain/_app/appState';
import { occurrencesUpTo } from '@/lib/recurrence';
import { invalidateRollover } from '@/lib/budgets/rollover';
import type { ScheduledTemplate } from '@/lib/store';
import {
  createBudget,
  updateBudget,
  updateBudgetCycle,
  stageBudgetAmount,
  clearPendingAmount,
  deleteBudget,
  contributeBudget,
  type BudgetPatch,
  type BudgetCyclePatch,
  type BudgetType,
} from './domain/budgets/queries';
import {
  createBudgetGroup,
  updateBudgetGroup,
  deleteBudgetGroup,
  type BudgetGroupPatch,
} from './domain/budgetGroups/queries';
import { isAccountType } from '@/lib/account-types';
import { parseInstallmentTotal } from '@/lib/installment';
// convertToBase not needed in mutations.ts (used within entries.ts and transactions.ts adapters)
import {
  createHolding,
  updateHolding,
  setHoldingPrice,
  deleteHolding,
  type HoldingPatch,
} from './domain/holdings/queries';
import {
  addTransaction,
  updateTransaction,
  deleteTransactionRow,
  confirmTransaction,
  confirmPendingWithMerchant,
  type AddInput,
} from './domain/transactions/queries';
import {
  postTransfer, postAdjustment, postSimple,
  rebuildEntry, resolveEntryRef,
  recomputeAccountFromPostings,
} from './core/entries';
import { seedReference, insertTransactions, seedTransactionTags } from './core/seed';
import {
  deleteAttachment,
  getAttachmentFile,
  getAttachmentRelPathsForTransaction,
} from './domain/attachments/queries';
import { resolveAttachmentPath } from './core/paths';
import { unlink } from 'node:fs/promises';
import transactionsData from '@/data/transactions.json';
import type { Tx } from '@/lib/store';
import { I18nError } from '@/lib/i18n-error';

/** Merge a partial backup-config update into the app_state slice. Reads the
 *  existing JSON, overrides the named keys, writes back. Concurrent
 *  setBackupFrequency / setBackupRetention can't clobber each other this way.
 *  Defaults mirror `lib/db/state.ts::readBackupConfig`. */
async function mergeBackupConfig(
  exec: Exec,
  patch: Partial<{ frequencyMs: number; retention: number }>,
): Promise<void> {
  const raw = await getAppState(exec, 'backupConfig');
  let cur: { frequencyMs: number; retention: number } = { frequencyMs: 60 * 60 * 1000, retention: 14 };
  if (raw) {
    try {
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        const f = Number((parsed as { frequencyMs?: unknown }).frequencyMs);
        const r = Number((parsed as { retention?: unknown }).retention);
        if (Number.isFinite(f)) cur.frequencyMs = Math.trunc(f);
        if (Number.isFinite(r) && r > 0) cur.retention = Math.trunc(r);
      }
    } catch {
      /* keep defaults */
    }
  }
  cur = { ...cur, ...patch };
  await setAppState(exec, 'backupConfig', JSON.stringify(cur));
}

/** Best-effort attachment-file cleanup. Called AFTER the DB row(s) are gone:
 *  if the unlink fails (missing file, EBUSY on Windows in dev, etc.) the
 *  orphan is harmless — `lib/db/queries/attachments.ts` will never surface a
 *  row pointing at it again, and a future vacuum can sweep it. The opposite
 *  order (unlink first, then delete) would risk a phantom DB row pointing
 *  at a missing file. RECEIPT_PHOTOS_PLAN §3.3. */
async function unlinkAttachmentFiles(relPaths: string[]): Promise<void> {
  if (!relPaths.length) return;
  for (const rel of relPaths) {
    const abs = resolveAttachmentPath(rel);
    if (!abs) continue;
    await unlink(abs).catch(() => {});
  }
}

const RESET_TABLES = [
  'holdings',
  'entry_attachments',
  'entry_tags',
  'postings',
  'entries',
  'scheduled_splits',
  'scheduled_templates',
  'tags',
  'budgets',
  'budget_groups',
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
const DEDUP_MESSAGES: { signature: string; code: string; message: string }[] = [
  { signature: 'entries.ledger_id, entries.dedup_hash', code: 'error.duplicate.txn', message: 'This looks like a duplicate — an identical transaction already exists.' },
  { signature: 'budgets.ledger_id, budgets.name', code: 'error.duplicate.budget', message: 'A budget with this name and cycle already exists.' },
];
async function withDedupMessage<T>(run: () => Promise<T>): Promise<T> {
  try {
    return await run();
  } catch (err) {
    const msg = String((err as Error)?.message ?? err);
    if (msg.includes('UNIQUE constraint failed')) {
      for (const { signature, code, message } of DEDUP_MESSAGES) {
        if (msg.includes(signature)) throw new I18nError(code, {}, message);
      }
    }
    throw err;
  }
}

// Categories nest at most 3 levels (CATEGORIES_LEVEL3_PLAN).
// The cap lives here, not in SQL — a self-referential CHECK is hard to
// express cleanly in SQLite. The 10-hop ceiling in each walker is a safety
// net against a malformed cycle in a hand-edited DB; real depth is ≤ 3.

/** Depth of `id` from the root, counting `id` itself. Top-level = 1. */
async function categoryDepth(exec: Exec, id: string): Promise<number> {
  let cur: string | null = id;
  let depth = 0;
  for (let hop = 0; cur != null && hop < 10; hop++) {
    const rows = await exec('SELECT parent_id FROM categories WHERE id = ?', [cur]);
    if (!rows.length) throw new I18nError('error.notFound.category', {}, 'Category does not exist');
    depth++;
    cur = rows[0].parent_id == null ? null : String(rows[0].parent_id);
  }
  return depth;
}

/** Max depth of the subtree rooted at `id`. A leaf = 1, with one level of
 *  children = 2, with grandchildren = 3. BFS the descendants level-by-level. */
async function subtreeDepth(exec: Exec, id: string): Promise<number> {
  let frontier = [id];
  let depth = 1;
  for (let hop = 0; hop < 10; hop++) {
    if (!frontier.length) break;
    const placeholders = frontier.map(() => '?').join(',');
    const rows = await exec(
      `SELECT id FROM categories WHERE parent_id IN (${placeholders})`,
      frontier,
    );
    if (!rows.length) break;
    depth++;
    frontier = rows.map((r) => String(r.id));
  }
  return depth;
}

/** Whether `candidateId` is `ancestorId` itself or sits anywhere in its
 *  subtree. Used to forbid moving a node under its own descendant
 *  (a fast cycle check). */
async function isInSubtreeOf(
  exec: Exec,
  candidateId: string,
  ancestorId: string,
): Promise<boolean> {
  let cur: string | null = candidateId;
  for (let hop = 0; cur != null && hop < 10; hop++) {
    if (cur === ancestorId) return true;
    const rows = await exec('SELECT parent_id FROM categories WHERE id = ?', [cur]);
    if (!rows.length) return false;
    cur = rows[0].parent_id == null ? null : String(rows[0].parent_id);
  }
  return false;
}

/** Reject creating a child under a parent that would push the chain past
 *  3 levels. Used by `createCategory` (new node = +1 level). */
async function assertCanBeParent(exec: Exec, parentId: string): Promise<void> {
  const d = await categoryDepth(exec, parentId);
  if (d >= 3) throw new I18nError('error.category.depthCap', {}, 'Categories nest at most three levels deep');
}

/** Reject moving the subtree rooted at `movingId` under `newParentId` when
 *  the result would exceed 3 levels. Combines parent depth with the
 *  subtree's own depth (a level-2 node with grandchildren can only land
 *  under a top-level node — not under another level-2 node, which would
 *  push the grandchildren to level 4). */
async function assertSubtreeFitsUnder(
  exec: Exec,
  movingId: string,
  newParentId: string,
): Promise<void> {
  const pd = await categoryDepth(exec, newParentId);
  const sd = await subtreeDepth(exec, movingId);
  if (pd + sd > 3) {
    throw new I18nError('error.category.depthCap', {}, 'Categories nest at most three levels deep');
  }
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
  await postSimple(exec, {
    ledgerId, accountId, date,
    amount, description, categoryId,
    kind: amount > 0 ? 'income' : 'expense',
    sourceTemplateId,
  });
}

/** Read a template's owning ledger directly off the row. Used by postScheduled
 *  in lieu of the previous 'personal' hardcode (LEDGER_CRUD_PLAN §1 fix). */
async function resolveTemplateLedger(exec: Exec, templateId: string): Promise<string> {
  const rows = await exec('SELECT ledger_id FROM scheduled_templates WHERE id = ?', [templateId]);
  if (!rows.length) throw new I18nError('error.notFound.template', {}, 'Template not found');
  return String(rows[0].ledger_id);
}

async function postScheduled(exec: Exec, args: Args): Promise<void> {
  const templateId = str(args.templateId);
  const t = await getScheduled(exec, templateId);
  if (!t) throw new I18nError('error.notFound.template', {}, 'Template not found');
  // Use the template's own ledger, not a hardcoded 'personal'. Templates can
  // live in any ledger; posting one to the wrong ledger would orphan the
  // resulting transaction's ledger_id from its source. (LEDGER_CRUD_PLAN §1
  // gap fix.)
  const ledgerId = await resolveTemplateLedger(exec, templateId);
  // Refuse to post more than the installment plan calls for. We block before
  // we touch the account, so a fully-paid plan can't sneak an extra payment
  // through. installmentPaid is the derived count of confirmed posts.
  if (t.installmentTotal != null && (t.installmentPaid ?? 0) >= t.installmentTotal) {
    throw new I18nError(
      'error.scheduled.installmentDone',
      { name: t.name, total: t.installmentTotal },
      `"${t.name}" has finished its ${t.installmentTotal}-payment plan`,
    );
  }
  const date = new Date().toISOString().slice(0, 10);
  // The posted transaction's description: the template's own description, or
  // its name as a fallback.
  const desc = t.description || t.name;

  if (t.type === 'transfer') {
    if (!t.fromAccountId || !t.accountId) throw new I18nError('error.scheduled.missingAccount', { name: t.name }, `"${t.name}" is missing an account`);
    await createTransfer(exec, { fromAccountId: t.fromAccountId, toAccountId: t.accountId, fromAmount: t.amount ?? 0, date, note: desc });
    return;
  }

  if (t.amount == null) throw new I18nError('error.scheduled.variableAmount', { name: t.name }, `"${t.name}" has a variable amount — add it manually`);
  const sign = t.type === 'income' ? 1 : -1;

  if (t.type === 'income' && t.splits?.length) {
    let posted = 0;
    for (const sp of t.splits) {
      const portion = sp.abs != null ? sp.abs : (t.amount * (sp.pct ?? 0)) / 100;
      if (!portion) continue;
      await postSingle(exec, ledgerId, sp.accountId, portion, `${desc} · ${sp.label}`, date, t.id, t.category ?? null);
      posted++;
    }
    if (!posted) throw new I18nError('error.scheduled.noSplits', { name: t.name }, `No split amounts to post for "${t.name}"`);
    return;
  }

  await postSingle(exec, ledgerId, t.accountId, sign * t.amount, desc, date, t.id, t.category ?? null);
}

// Create a transfer: delegates to postTransfer which creates an entry with two
// account legs (DOUBLE_ENTRY_PLAN §6). No transfer_groups INSERT.
async function createTransfer(exec: Exec, args: Args): Promise<void> {
  const fromId = str(args.fromAccountId);
  const toId = str(args.toAccountId);
  const fromAmount = Math.abs(Number(args.fromAmount));
  const explicitToAmount = args.toAmount != null ? Math.abs(Number(args.toAmount)) : null;
  const date = str(args.date);
  const time = args.time ? str(args.time) : null;
  const note = args.note ? str(args.note) : null;
  const sourceTemplateId = args.sourceTemplateId ? str(args.sourceTemplateId) : null;

  if (!fromAmount) throw new I18nError('error.transfer.amountGt0', {}, 'Transfer amount must be greater than 0');
  if (fromId === toId) throw new I18nError('error.transfer.sameAccount', {}, 'Pick two different accounts');

  const [from] = await exec('SELECT currency, name FROM accounts WHERE id = ?', [fromId]);
  const [to] = await exec('SELECT currency, name FROM accounts WHERE id = ?', [toId]);
  if (!from || !to) throw new I18nError('error.notFound.account', {}, 'Account not found');

  const fromCurrency = String(from.currency);
  const toCurrency = String(to.currency);
  if (explicitToAmount != null) {
    if (!(explicitToAmount > 0)) throw new I18nError('error.transfer.receivedGt0', {}, 'Received amount must be greater than 0');
    if (fromCurrency === toCurrency && Math.abs(explicitToAmount - fromAmount) > 0.005) {
      throw new I18nError('error.transfer.sameCurrencyMismatch', {}, 'Same-currency transfer amounts must match');
    }
  }

  // postTransfer handles all validation + residue; re-raise with the same I18nError codes.
  await postTransfer(exec, {
    fromAccountId: fromId,
    toAccountId: toId,
    fromAmount,
    toAmount: explicitToAmount,
    date,
    time,
    note,
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

    // Dedup: check against entries table (source_template_id).
    const existing = await exec('SELECT date FROM entries WHERE source_template_id = ?', [String(r.id)]);
    const have = new Set(existing.map((e) => String(e.date)));
    dates = dates.filter((d) => !have.has(d));
    const max = r.max_executions == null ? null : Number(r.max_executions);
    if (max != null) dates = dates.slice(0, Math.max(0, max - have.size));
    // Installment plans cap at installment_total just like max_executions.
    const installmentTotal = r.installment_total == null ? null : Number(r.installment_total);
    if (installmentTotal != null) dates = dates.slice(0, Math.max(0, installmentTotal - have.size));
    if (!dates.length) continue;

    const ledgerId = String(r.ledger_id);
    const acctId = String(r.account_id);
    const description = String(r.description ?? r.name ?? '');

    if (type === 'transfer') {
      // Cross-account recurring: one postTransfer per due date.
      const fromAccountId = String(r.from_account_id);
      const fromAmount = Math.abs(Number(r.amount));
      const sourceTemplateId = String(r.id);
      for (const date of dates) {
        await postTransfer(exec, {
          fromAccountId, toAccountId: acctId, fromAmount, date,
          note: description || null, sourceTemplateId, timestamp: ts,
        });
      }
      continue;
    }

    const amount = (type === 'income' ? 1 : -1) * Number(r.amount);
    const categoryId = r.category_id == null ? null : String(r.category_id);
    // Counterparty resolved once per template (same description for every occurrence).
    const cpId = await resolveCounterpartyIdByName(exec, ledgerId, description);
    for (const date of dates) {
      await postSimple(exec, {
        ledgerId, accountId: acctId, date,
        amount, description, categoryId,
        kind: type === 'income' ? 'income' : 'expense',
        status: 'pending',
        sourceTemplateId: String(r.id),
        counterpartyId: cpId,
        timestamp: ts,
      });
    }
  }
}

// Capture a transaction's date + every category/account it touches.
// Used by the tx-mutation cases to feed invalidateRollover() with the
// before/after state of an edit. Now entries-based (B3b).
async function txTouches(
  exec: Exec,
  id: string,
): Promise<{ date: string; accountId: string; categoryIds: string[] } | null> {
  const ref = await resolveEntryRef(exec, id);
  if (!ref) return null;
  const { entryId } = ref;
  const [e] = await exec('SELECT date FROM entries WHERE id = ?', [entryId]);
  if (!e) return null;
  const postings = await exec(
    'SELECT account_id, category_id FROM postings WHERE entry_id = ?',
    [entryId],
  );
  const categoryIds = new Set<string>();
  let accountId: string | null = null;
  for (const p of postings) {
    if (p.account_id != null && accountId == null) accountId = String(p.account_id);
    if (p.category_id != null) categoryIds.add(String(p.category_id));
  }
  if (!accountId) return null;
  return { date: String(e.date), accountId, categoryIds: [...categoryIds] };
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
      const id = await withDedupMessage(() => addTransaction(exec, args as unknown as AddInput));
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
      if (!Number.isFinite(target)) throw new I18nError('error.adjust.targetRequired', {}, 'Enter a target balance');
      const [acct] = await exec('SELECT ledger_id, current_balance FROM accounts WHERE id = ?', [accountId]);
      if (!acct) throw new I18nError('error.notFound.account', {}, 'Account not found');
      const delta = r2(target - Number(acct.current_balance));
      // postAdjustment handles the zero no-op internally (returns null).
      const source = args.source === 'reconcile' ? 'reconcile' : 'manual';
      await postAdjustment(exec, {
        ledgerId: String(acct.ledger_id),
        accountId,
        delta,
        date: args.date ? str(args.date) : new Date().toISOString().slice(0, 10),
        note: args.note ? str(args.note) : undefined,
        source,
      });
      return;
    }
    case 'updateTransaction': {
      const id = str(args.id);
      const before = await txTouches(exec, id);
      // updateTransaction (entries adapter) handles all account recomputes internally via
      // rebuildEntry. The returned oldAccountId tells us if recompute is needed
      // for the OLD account — rebuildEntry already does the NEW account.
      const { oldAccountId } = await updateTransaction(exec, id, args.patch as Parameters<typeof updateTransaction>[2]);
      if (oldAccountId) {
        await recomputeAccountFromPostings(exec, oldAccountId);
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
      // Toggle a single posting's cleared-against-statement flag. Resolves the
      // client's account-posting id to get the posting row id (§4.2).
      const id = str(args.id);
      const cleared = args.cleared === true;
      const ref = await resolveEntryRef(exec, id);
      const postingId = ref?.postingId ?? id;
      await exec(
        cleared
          ? "UPDATE postings SET cleared_at = datetime('now') WHERE id = ?"
          : 'UPDATE postings SET cleared_at = NULL WHERE id = ?',
        [postingId],
      );
      return;
    }
    case 'setReviewed': {
      // Toggle a single entry's review-triage flag.
      const id = str(args.id);
      const reviewed = args.reviewed === true;
      const ref = await resolveEntryRef(exec, id);
      const entryId = ref?.entryId ?? id;
      await exec(
        reviewed
          ? "UPDATE entries SET reviewed_at = datetime('now') WHERE id = ?"
          : 'UPDATE entries SET reviewed_at = NULL WHERE id = ?',
        [entryId],
      );
      return;
    }
    case 'markAllReviewed': {
      // Bulk-clear the review queue for a ledger (optionally scoped to one account).
      const ledgerId = str(args.ledgerId || 'personal');
      const accountId = args.accountId ? str(args.accountId) : null;
      if (accountId) {
        // Scope to entries that have at least one account leg for this account.
        await exec(
          `UPDATE entries SET reviewed_at = datetime('now')
            WHERE ledger_id = ? AND reviewed_at IS NULL
              AND EXISTS (SELECT 1 FROM postings p WHERE p.entry_id = entries.id AND p.account_id = ?)`,
          [ledgerId, accountId],
        );
      } else {
        await exec(
          `UPDATE entries SET reviewed_at = datetime('now') WHERE ledger_id = ? AND reviewed_at IS NULL`,
          [ledgerId],
        );
      }
      return;
    }
    case 'reconcileAccount': {
      // Stamp the reconcile checkpoint on the account; optionally post an
      // Adjustment for the remaining gap so the cleared balance lands exactly
      // on the statement target.
      const accountId = str(args.accountId);
      const statementBalance = Number(args.statementBalance);
      if (!Number.isFinite(statementBalance)) throw new I18nError('error.reconcile.statementBalance', {}, 'Statement balance is required');
      const statementDate = args.statementDate ? str(args.statementDate) : new Date().toISOString().slice(0, 10);
      const doPostAdjustment = args.postAdjustment === true;

      if (doPostAdjustment) {
        const [acct] = await exec('SELECT ledger_id FROM accounts WHERE id = ?', [accountId]);
        if (!acct) throw new I18nError('error.notFound.account', {}, 'Account not found');
        // Cleared sum from postings — no opening_balance term (opening entry is pre-cleared,
        // so it's already in the sum per DOUBLE_ENTRY_PLAN §6).
        const [sum] = await exec(
          `SELECT COALESCE(SUM(p.amount), 0) AS s
             FROM postings p JOIN entries e ON e.id = p.entry_id
            WHERE p.account_id = ?
              AND e.status = 'confirmed'
              AND p.cleared_at IS NOT NULL`,
          [accountId],
        );
        const cleared = r2(Number(sum.s));
        const delta = r2(statementBalance - cleared);
        if (Math.abs(delta) >= 0.005) {
          const adjResult = await postAdjustment(exec, {
            ledgerId: String(acct.ledger_id),
            accountId,
            delta,
            date: statementDate,
            source: 'reconcile',
          });
          // Mark the new adjustment entry's account leg as cleared.
          if (adjResult) {
            await exec(
              `UPDATE postings SET cleared_at = datetime('now')
                WHERE entry_id = ? AND account_id IS NOT NULL`,
              [adjResult.entryId],
            );
          }
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
      // Each id is an account-posting id; resolve to entryId + load the account
      // leg, then rebuildEntry with the same account leg + the new category leg.
      const ids = Array.isArray(args.ids) ? args.ids.map(str) : [];
      const categoryId = args.categoryId == null ? null : str(args.categoryId);
      if (!ids.length) return;

      const cats = new Set<string>();
      if (categoryId) cats.add(categoryId);
      let earliest = '';

      for (const id of ids) {
        const ref = await resolveEntryRef(exec, id);
        if (!ref) continue;
        const { entryId } = ref;

        const [entry] = await exec('SELECT date FROM entries WHERE id = ?', [entryId]);
        if (!entry) continue;
        const d = String(entry.date ?? '');
        if (d && (!earliest || d < earliest)) earliest = d;

        // Load the category legs to collect old category IDs for rollover.
        const catLegs = await exec(
          'SELECT category_id FROM postings WHERE entry_id = ? AND category_id IS NOT NULL',
          [entryId],
        );
        for (const leg of catLegs) cats.add(String(leg.category_id));

        // Load the account leg to forward verbatim (amounts/account don't change).
        const [acctLeg] = await exec(
          `SELECT id, account_id, amount, amount_base, exchange_rate, currency, cleared_at, memo
             FROM postings WHERE entry_id = ? AND account_id IS NOT NULL LIMIT 1`,
          [entryId],
        );
        if (!acctLeg) continue;

        // For split entries (≥2 category legs) the spec says: no-op on legs.
        if (catLegs.length >= 2) continue;

        const legs: import('./core/entries').LegInput[] = [
          {
            id: String(acctLeg.id),
            accountId: String(acctLeg.account_id),
            amount: Number(acctLeg.amount),
            amountBase: Number(acctLeg.amount_base),
            exchangeRate: Number(acctLeg.exchange_rate ?? 1),
            clearedAt: acctLeg.cleared_at == null ? null : String(acctLeg.cleared_at),
            memo: acctLeg.memo == null ? null : String(acctLeg.memo),
          },
        ];
        // Always include a category leg (categoryId = null = uncategorized is valid
        // and satisfies the shape check for expense/income/refund entries).
        legs.push({ categoryId: categoryId ?? null, amountBase: -Number(acctLeg.amount_base) });
        await rebuildEntry(exec, entryId, { legs });
      }

      if (cats.size > 0 && earliest) {
        await invalidateRollover(exec, { categoryIds: [...cats], accountIds: [] }, earliest);
      }
      return;
    }
    case 'deleteTransaction': {
      const id = str(args.id);
      const before = await txTouches(exec, id);
      // Collect attachment rel_paths BEFORE the FK CASCADE fires — afterwards
      // the rows are gone and we can't recover them. The actual unlinks run
      // at the bottom of this case, after the DB state is settled.
      const attachmentPaths = await getAttachmentRelPathsForTransaction(exec, id);
      // Hard delete: deleteEntry (called by deleteTransactionRow) handles
      // recomputeAccountFromPostings for every affected account internally.
      await deleteTransactionRow(exec, id);
      if (before) {
        await invalidateRollover(
          exec,
          { categoryIds: before.categoryIds, accountIds: [before.accountId] },
          before.date,
        );
      }
      await unlinkAttachmentFiles(attachmentPaths);
      return;
    }
    case 'removeAttachment': {
      // Toggle off a single receipt — delete the pointer row, then unlink the
      // file. The user-visible model is "the receipt is gone" regardless of
      // which step technically fails (RECEIPT_PHOTOS_PLAN §3.3).
      const id = str(args.id);
      const row = await getAttachmentFile(exec, id);
      if (!row) return; // already gone — idempotent
      await deleteAttachment(exec, id);
      await unlinkAttachmentFiles([row.relPath]);
      return;
    }
    case 'confirmTransaction':
      // confirmTransaction (entries adapter) calls recomputeAccountFromPostings internally.
      await confirmTransaction(exec, str(args.id));
      return;
    case 'confirmPendingWithMerchant': {
      // confirmPendingWithMerchant (entries adapter) calls recomputeAccountFromPostings internally.
      await confirmPendingWithMerchant(exec, str(args.id), {
        counterpartyId: args.counterpartyId != null ? str(args.counterpartyId) : null,
        newCounterpartyName: args.newCounterpartyName != null ? str(args.newCounterpartyName) : null,
      });
      return;
    }
    case 'confirmAllPending': {
      // Collect affected account ids from postings before the UPDATE so we can
      // recompute balances after all entries are confirmed.
      const pendingAccts = await exec(
        `SELECT DISTINCT p.account_id
           FROM postings p JOIN entries e ON e.id = p.entry_id
          WHERE e.status = 'pending' AND p.account_id IS NOT NULL`,
      );
      await exec(
        "UPDATE entries SET status = 'confirmed', confirmed_at = ?, updated_at = datetime('now') WHERE status = 'pending'",
        [new Date().toISOString()],
      );
      for (const r of pendingAccts) await recomputeAccountFromPostings(exec, String(r.account_id));
      return;
    }
    // --- Named budgets (the redesign entity) + budget groups ---
    case 'createBudget': {
      const ledgerId = str(args.ledgerId || 'personal');
      const name = str(args.name).trim();
      if (!name) throw new I18nError('error.required.budgetName', {}, 'Budget name is required');
      const type: BudgetType = str(args.type) === 'income' ? 'income' : 'expense';
      const amount = Number(args.amount);
      if (!(amount > 0)) throw new I18nError('error.budget.amountGt0', {}, 'Budget amount must be greater than 0');
      const strList = (v: unknown): string[] => (Array.isArray(v) ? (v as unknown[]).map(str) : []);
      await withDedupMessage(() => createBudget(exec, {
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
      if (patch.name !== undefined && !str(patch.name).trim()) throw new I18nError('error.required.budgetName', {}, 'Budget name is required');
      if (patch.amount !== undefined && !(Number(patch.amount) > 0)) throw new I18nError('error.budget.amountGt0', {}, 'Budget amount must be greater than 0');
      // Amount-only edits on existing recurring budgets stage to
      // pending_amount instead of writing the active amount — the next
      // period boundary commits the change (BUDGET_CYCLES_PLAN §2).
      const patchKeys = Object.keys(patch).filter((k) => (patch as Record<string, unknown>)[k] !== undefined);
      const amountOnly = patchKeys.length === 1 && patchKeys[0] === 'amount';
      if (amountOnly) {
        const id = str(args.id);
        const [row] = await exec('SELECT is_recurring FROM budgets WHERE id = ?', [id]);
        if (row && Number(row.is_recurring) === 1) {
          await stageBudgetAmount(exec, id, Number(patch.amount));
          return;
        }
      }
      await updateBudget(exec, str(args.id), patch);
      return;
    }
    case 'updateBudgetCycle': {
      const patch = (args.patch ?? {}) as BudgetCyclePatch;
      const validFreqs = ['daily','weekly','biweekly','monthly','quarterly','yearly'];
      if (!validFreqs.includes(patch.frequency)) throw new I18nError('error.budget.unknownFreq', { freq: String(patch.frequency) }, `Unknown frequency "${patch.frequency}"`);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(patch.startDate)) throw new I18nError('error.budget.dateFormat', {}, 'startDate must be YYYY-MM-DD');
      if (patch.amount !== undefined && !(Number(patch.amount) > 0)) throw new I18nError('error.budget.amountGt0', {}, 'Budget amount must be greater than 0');
      await updateBudgetCycle(exec, str(args.id), patch);
      return;
    }
    case 'clearPendingAmount':
      await clearPendingAmount(exec, str(args.id));
      return;
    // Entity delete uses `removeBudget` to avoid colliding with the legacy
    // per-category `deleteBudget` action above.
    case 'removeBudget':
      await deleteBudget(exec, str(args.id));
      return;
    case 'contributeBudget': {
      const amount = Number(args.amount);
      if (!Number.isFinite(amount)) throw new I18nError('error.budget.invalidContribution', {}, 'Invalid contribution amount');
      await contributeBudget(exec, str(args.id), amount);
      return;
    }
    case 'createBudgetGroup': {
      const name = str(args.name).trim();
      if (!name) throw new I18nError('error.required.groupName', {}, 'Group name is required');
      await createBudgetGroup(exec, {
        id: str(args.id || newId('bgg')),
        ledgerId: str(args.ledgerId || 'personal'),
        name,
      });
      return;
    }
    case 'updateBudgetGroup': {
      const patch = (args.patch ?? {}) as BudgetGroupPatch;
      if (patch.name !== undefined && !str(patch.name).trim()) throw new I18nError('error.required.groupName', {}, 'Group name is required');
      await updateBudgetGroup(exec, str(args.id), patch);
      return;
    }
    case 'deleteBudgetGroup':
      await deleteBudgetGroup(exec, str(args.id));
      return;
    case 'createAccount': {
      const ledgerId = str(args.ledgerId || 'personal');
      const name = str(args.name).trim();
      if (!name) throw new I18nError('error.required.accountName', {}, 'Account name is required');
      const type = str(args.type || 'savings');
      if (!isAccountType(type)) throw new I18nError('error.account.unknownType', { type }, `Unknown account type "${type}"`);
      await createAccount(exec, {
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
      if (patch.name !== undefined && !str(patch.name).trim()) throw new I18nError('error.required.accountName', {}, 'Account name is required');
      if (patch.type !== undefined && !isAccountType(str(patch.type))) {
        throw new I18nError('error.account.unknownType', { type: String(patch.type) }, `Unknown account type "${patch.type}"`);
      }
      await updateAccount(exec, str(args.id), patch);
      return;
    }
    case 'archiveAccount':
      await archiveAccount(exec, str(args.id));
      return;
    case 'unarchiveAccount':
      await unarchiveAccount(exec, str(args.id));
      return;
    case 'deleteAccount':
      await deleteAccount(exec, str(args.id));
      return;
    case 'createAccountGroup': {
      const name = str(args.name).trim();
      if (!name) throw new I18nError('error.required.groupName', {}, 'Group name is required');
      await createAccountGroup(exec, {
        id: str(args.id || newId('ag')),
        ledgerId: str(args.ledgerId || 'personal'),
        name,
      });
      return;
    }
    case 'updateAccountGroup': {
      const patch = (args.patch ?? {}) as AccountGroupPatch;
      if (patch.name !== undefined && !str(patch.name).trim()) throw new I18nError('error.required.groupName', {}, 'Group name is required');
      await updateAccountGroup(exec, str(args.id), patch);
      return;
    }
    case 'deleteAccountGroup':
      await deleteAccountGroup(exec, str(args.id));
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
      if (!accountId) throw new I18nError('error.required.splitAccount', {}, 'A split needs an account');
      await addScheduledSplit(exec, str(args.templateId), accountId, Number(args.pct) || 0);
      return;
    }
    case 'removeScheduledSplit': {
      await removeScheduledSplit(exec, str(args.templateId), Number(args.index));
      return;
    }
    case 'verifyCounterparty':
      await verifyCounterparty(exec, str(args.id));
      return;
    case 'unverifyCounterparty':
      await unverifyCounterparty(exec, str(args.id));
      return;
    case 'createTransfer':
      await createTransfer(exec, args);
      return;
    case 'updateTransfer':
      await updateTransfer(exec, str(args.id), (args.patch ?? {}) as Parameters<typeof updateTransfer>[2]);
      return;
    case 'createCategory': {
      const ledgerId = str(args.ledgerId || 'personal');
      const name = str(args.name).trim();
      if (!name) throw new I18nError('error.required.categoryName', {}, 'Category name is required');
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
      if (patch.name !== undefined && !str(patch.name).trim()) throw new I18nError('error.required.categoryName', {}, 'Category name is required');
      if (patch.parentId !== undefined && patch.parentId !== null) {
        if (patch.parentId === id) throw new I18nError('error.category.selfParent', {}, 'A category cannot be its own parent');
        // Cycle defence: the target parent must not live inside the moving
        // subtree (else the move would orphan the chain into a loop).
        if (await isInSubtreeOf(exec, patch.parentId, id)) {
          throw new I18nError('error.category.underDescendant', {}, 'A category cannot be moved under its own descendant');
        }
        // Depth defence: account for the moving subtree, not just the
        // parent's depth. Replaces the old 2-level era guard that
        // categorically refused to re-parent any node that itself had
        // children — at 3 levels that's overcautious; a level-2 node
        // with grandchildren can legitimately move under a top-level
        // parent (the deepest leaf stays at depth 3).
        await assertSubtreeFitsUnder(exec, id, patch.parentId);
      }
      await updateCategory(exec, id, patch);
      return;
    }
    case 'updateTag': {
      const patch = (args.patch ?? {}) as TagPatch;
      if (patch.name !== undefined && !str(patch.name).trim()) throw new I18nError('error.required.tagName', {}, 'Tag name is required');
      await updateTag(exec, str(args.id), patch);
      return;
    }
    case 'updateScheduled': {
      const patch = { ...(args.patch ?? {}) } as ScheduledPatch & { installmentTotal?: unknown };
      if (patch.name !== undefined && !str(patch.name).trim()) throw new I18nError('error.required.templateName', {}, 'Template name is required');
      if ('installmentTotal' in patch) {
        patch.installmentTotal = parseInstallmentTotal(patch.installmentTotal);
      }
      await updateScheduled(exec, str(args.id), patch);
      return;
    }
    case 'updateCounterparty': {
      const patch = (args.patch ?? {}) as CounterpartyPatch;
      if (patch.name !== undefined && !str(patch.name).trim()) throw new I18nError('error.required.merchantName', {}, 'Merchant name is required');
      await updateCounterparty(exec, str(args.id), patch);
      return;
    }
    case 'createRule': {
      const ledgerId = str(args.ledgerId || 'personal');
      const condition = args.condition as Condition;
      const actions = (Array.isArray(args.actions) ? args.actions : []) as Action[];
      if (!condition) throw new I18nError('error.required.ruleCondition', {}, 'Rule condition is required');
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
      await createRule(exec, id, input);
      return;
    }
    case 'updateRule': {
      const patch = (args.patch ?? {}) as RulePatchInput;
      await updateRule(exec, str(args.id), patch);
      return;
    }
    case 'deleteRule': {
      await deleteRule(exec, str(args.id));
      return;
    }
    case 'backfillRule': {
      // Apply one rule against every confirmed transaction in its ledger.
      // Mirrors insertTxRow's post-rule plumbing: set_* fields move on the
      // row, add_tag rows go into transaction_tags. Splits and category-
      // change rollover invalidations are out of scope for this PR — set_*
      // covers the 80% case (the "rename + categorise" workflow).
      const ruleId = str(args.id);
      const [{ applyRules }, { resolveCounterpartyIdByName }] = await Promise.all([
        import('@/lib/rules/engine'),
        import('./queries/counterparties'),
      ]);
      // Load just this rule from the DB (active OR inactive — explicit backfill
      // shouldn't silently skip a disabled rule the user just enabled).
      const ruleRows = await exec('SELECT * FROM rules WHERE id = ?', [ruleId]);
      if (!ruleRows.length) throw new I18nError('error.notFound.rule', {}, 'Rule not found');
      const { rowToRule } = await import('./queries/rules');
      const rule = rowToRule(ruleRows[0]);

      // Walk entries in the rule's ledger only (FK is ON DELETE CASCADE;
      // a deleted ledger can't have orphan rules), confirmed only (pending rows
      // haven't really happened yet — the user can re-confirm to trigger them
      // through the insert hook). Only plain income/expense/refund entries are
      // eligible (transfers and adjustments are structural, not user-categorised).
      const entryRows = await exec(
        `SELECT e.id, e.ledger_id, e.date, e.time, e.description, e.kind,
                e.notes, e.counterparty_id, e.applied_rule_ids,
                p.account_id, p.amount, p.amount_base, p.currency, p.category_id
           FROM entries e
           JOIN postings p ON p.entry_id = e.id AND p.account_id IS NOT NULL
          WHERE e.ledger_id = ? AND e.status = 'confirmed'
            AND e.kind IN ('income', 'expense', 'refund')`,
        [rule.ledgerId],
      );
      let matched = 0;
      for (const r of entryRows) {
        // Build a minimal Tx synthesizing what evaluateCondition reads.
        const tx = {
          id: String(r.id), // entry id; the projection exposes the posting id via state.ts
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

        // Apply the patch's set_* fields via a direct UPDATE on entries.
        const sets: string[] = [];
        const bind: (string | number | null)[] = [];
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
        if (patch.reviewed) { sets.push("reviewed_at = datetime('now')"); }

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
          bind.push(tx.id); // entry id
          await exec(`UPDATE entries SET ${sets.join(', ')} WHERE id = ?`, bind);
        }

        // set_category: use the bulkRecategorize technique — load account leg,
        // rebuild with the new category leg.
        if (patch.categoryId !== undefined) {
          const [acctLeg] = await exec(
            `SELECT id, account_id, amount, amount_base, exchange_rate, cleared_at, memo
               FROM postings WHERE entry_id = ? AND account_id IS NOT NULL LIMIT 1`,
            [tx.id],
          );
          if (acctLeg) {
            const catLegs = await exec(
              'SELECT category_id FROM postings WHERE entry_id = ? AND category_id IS NOT NULL',
              [tx.id],
            );
            // No-op on splits (≥2 category legs) — mirrors bulkRecategorize parity.
            if (catLegs.length < 2) {
              const legs: import('./core/entries').LegInput[] = [
                {
                  id: String(acctLeg.id),
                  accountId: String(acctLeg.account_id),
                  amount: Number(acctLeg.amount),
                  amountBase: Number(acctLeg.amount_base),
                  exchangeRate: Number(acctLeg.exchange_rate ?? 1),
                  clearedAt: acctLeg.cleared_at == null ? null : String(acctLeg.cleared_at),
                  memo: acctLeg.memo == null ? null : String(acctLeg.memo),
                },
              ];
              if (patch.categoryId != null) {
                legs.push({ categoryId: patch.categoryId, amountBase: -Number(acctLeg.amount_base) });
              } else {
                legs.push({ categoryId: null, amountBase: -Number(acctLeg.amount_base) });
              }
              await rebuildEntry(exec, tx.id, { legs });
            }
          }
        }

        if (patch.tagIdsAdd?.length) {
          for (const tagId of patch.tagIdsAdd) {
            await exec(
              'INSERT OR IGNORE INTO entry_tags (entry_id, tag_id) VALUES (?, ?)',
              [tx.id, tagId], // tx.id is the entry id here
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
      if (!name) throw new I18nError('error.required.tagName', {}, 'Tag name is required');
      await exec("INSERT INTO tags (id,ledger_id,name,color,created_at,updated_at) VALUES (?,?,?,?,datetime('now'),datetime('now'))", [
        args.id ? str(args.id) : newId('tag'), str(args.ledgerId || 'personal'), name, args.color ? str(args.color) : null,
      ]);
      return;
    }
    case 'setTransactionTags': {
      const txId = str(args.id);
      const tagIds = Array.isArray(args.tagIds) ? (args.tagIds as unknown[]).map(str) : [];
      // Resolve account-posting id → entry id; fall back to the id itself if
      // it already is an entry id (forward-compat with B4 callers).
      const ref = await resolveEntryRef(exec, txId);
      const entryId = ref?.entryId ?? txId;
      await exec('DELETE FROM entry_tags WHERE entry_id = ?', [entryId]);
      for (const tagId of tagIds) {
        await exec('INSERT OR IGNORE INTO entry_tags (entry_id, tag_id) VALUES (?, ?)', [entryId, tagId]);
      }
      return;
    }
    case 'setTransactionSplits': {
      const txId = str(args.id);
      const rawSplits = Array.isArray(args.splits) ? (args.splits as unknown[]) : [];
      type SplitInput = { categoryId: string | null; amount: number; description: string | null };
      const splits: SplitInput[] = rawSplits.map((s) => {
        const o = s as Record<string, unknown>;
        return {
          categoryId: o.categoryId == null ? null : str(o.categoryId),
          amount: Number(o.amount),
          description: o.description == null ? null : str(o.description),
        };
      });

      const before = await txTouches(exec, txId);
      const ref = await resolveEntryRef(exec, txId);
      if (ref) {
        const { entryId } = ref;
        // Load the account leg — forward verbatim (amounts/account don't change).
        const [acctLeg] = await exec(
          `SELECT id, account_id, amount, amount_base, exchange_rate, cleared_at, memo
             FROM postings WHERE entry_id = ? AND account_id IS NOT NULL LIMIT 1`,
          [entryId],
        );
        if (acctLeg) {
          const totalBase = Math.abs(Number(acctLeg.amount_base));
          const legs: import('./core/entries').LegInput[] = [
            {
              id: String(acctLeg.id),
              accountId: String(acctLeg.account_id),
              amount: Number(acctLeg.amount),
              amountBase: Number(acctLeg.amount_base),
              exchangeRate: Number(acctLeg.exchange_rate ?? 1),
              clearedAt: acctLeg.cleared_at == null ? null : String(acctLeg.cleared_at),
              memo: acctLeg.memo == null ? null : String(acctLeg.memo),
            },
          ];

          if (splits.length === 0) {
            // Clear splits: rebuild with a single uncategorised category leg.
            legs.push({ categoryId: null, amountBase: -Number(acctLeg.amount_base) });
          } else {
            // Must have at least two split rows to be meaningful.
            if (splits.length === 1) {
              throw new I18nError('error.split.minTwo', {}, 'Splits require at least two rows');
            }
            // Validate that splits sum matches the account leg magnitude.
            const splitTotal = splits.reduce((acc, sp) => acc + Math.abs(sp.amount), 0);
            if (splitTotal > 0 && Math.abs(splitTotal - totalBase) > 0.005 * splits.length) {
              throw new I18nError('error.split.sumMismatch', {}, 'Split amounts must sum to the transaction total');
            }
            // Compute base ratio: if amounts in native currency, scale to base.
            const baseRatio = splitTotal > 0 ? totalBase / splitTotal : 1;
            // Last leg absorbs rounding remainders.
            let usedBase = 0;
            for (let i = 0; i < splits.length; i++) {
              const sp = splits[i];
              const isLast = i === splits.length - 1;
              const spBase = isLast
                ? r2(Number(acctLeg.amount_base) + usedBase) // absorb remainder (signed)
                : r2(-Math.abs(sp.amount) * baseRatio * Math.sign(Number(acctLeg.amount_base)));
              if (!isLast) usedBase += spBase;
              legs.push({
                categoryId: sp.categoryId,
                amountBase: spBase,
                memo: sp.description,
              });
            }
          }
          await rebuildEntry(exec, entryId, { legs });
        }
      }
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
      await deleteCategory(exec, str(args.id));
      return;
    case 'deleteTag':
      await deleteTag(exec, str(args.id));
      return;
    case 'createScheduled': {
      const name = str(args.name).trim();
      if (!name) throw new I18nError('error.required.templateName', {}, 'Template name is required');
      const type = str(args.type || 'expense');
      if (!['income', 'expense', 'transfer'].includes(type)) throw new I18nError('error.account.splitTypeUnknown', { type }, `Unknown type "${type}"`);
      const frequency = str(args.frequency || 'monthly');
      if (!['once', 'daily', 'weekly', 'biweekly', 'monthly', 'quarterly', 'yearly'].includes(frequency)) {
        throw new I18nError('error.account.splitFreqUnknown', { freq: frequency }, `Unknown frequency "${frequency}"`);
      }
      const accountId = str(args.accountId ?? '').trim();
      if (!accountId) throw new I18nError('error.required.account', {}, 'An account is required');
      await createScheduled(exec, {
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
      await deleteScheduled(exec, str(args.id));
      return;
    case 'deleteTransfer':
      await deleteTransfer(exec, str(args.id));
      return;
    case 'createCounterparty': {
      const name = str(args.name).trim();
      if (!name) throw new I18nError('error.required.merchantName', {}, 'Merchant name is required');
      await createCounterparty(exec, {
        id: str(args.id || newId('cp')),
        ledgerId: str(args.ledgerId || 'personal'),
        name,
      });
      return;
    }
    case 'deleteCounterparty':
      await deleteCounterparty(exec, str(args.id));
      return;
    case 'setExchangeRate': {
      const date = str(args.date);
      const currency = str(args.currency).trim().toUpperCase();
      const rate = Number(args.rate);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new I18nError('error.fx.dateFormat', {}, 'Date must be YYYY-MM-DD');
      if (!currency) throw new I18nError('error.required.currency', {}, 'Currency is required');
      if (!(rate > 0)) throw new I18nError('error.fx.rateGt0', {}, 'Rate must be greater than 0');
      if (currency === 'USD') throw new I18nError('error.fx.usdHub', {}, 'USD is the hub currency and is not stored');
      await setExchangeRate(exec, { date, currency, rate, source: args.source ? str(args.source) : null });
      return;
    }
    case 'deleteExchangeRate':
      await deleteExchangeRate(exec, str(args.date), str(args.currency).toUpperCase());
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
    case 'setBackupFrequency': {
      // frequencyMs: -1 = off, 0 = on every change, >0 = minimum interval.
      // Merge into the existing slice so retention isn't clobbered.
      const ms = Number(args.frequencyMs);
      const next = Number.isFinite(ms) ? Math.trunc(ms) : 60 * 60 * 1000;
      await mergeBackupConfig(exec, { frequencyMs: next });
      return;
    }
    case 'setBackupRetention': {
      // Number of `.finch.bak` files to keep on disk; must be >= 1.
      const n = Number(args.retention);
      const next = Number.isFinite(n) && n > 0 ? Math.trunc(n) : 14;
      await mergeBackupConfig(exec, { retention: next });
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
      if (!accountId) throw new I18nError('error.required.investmentAccount', {}, 'An investment account is required');
      if (!symbol) throw new I18nError('error.required.symbol', {}, 'Symbol is required');
      if (!(shares > 0)) throw new I18nError('error.holding.sharesGt0', {}, 'Shares must be greater than 0');
      if (!(costBasis >= 0)) throw new I18nError('error.holding.costBasisGte0', {}, 'Cost basis must be 0 or greater');
      const [acct] = await exec('SELECT type, currency, ledger_id FROM accounts WHERE id = ?', [accountId]);
      if (!acct) throw new I18nError('error.notFound.account', {}, 'Account not found');
      if (String(acct.type) !== 'investment') throw new I18nError('error.holding.notInvestment', {}, 'Holdings can only be added to an investment account');
      const ledgerId = str(args.ledgerId || acct.ledger_id || 'personal');
      // Lock currency to the account's so cross-position sums in the
      // account's currency stay correct without per-row conversion. A
      // mismatched override is rejected outright rather than silently
      // coerced — surfaces the misuse instead of corrupting totals.
      const accountCurrency = String(acct.currency ?? 'USD');
      const requested = args.currency ? str(args.currency).trim().toUpperCase() : accountCurrency;
      if (requested !== accountCurrency) {
        throw new I18nError('error.holding.currencyMismatch', { currency: accountCurrency }, `Holding currency must match the account currency (${accountCurrency})`);
      }
      const currency = accountCurrency;
      await createHolding(exec, {
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
        if (!sym) throw new I18nError('error.holding.symbolEmpty', {}, 'Symbol cannot be empty');
        normalized.symbol = sym;
      }
      if (patch.name !== undefined) normalized.name = patch.name == null ? null : str(patch.name);
      if (patch.shares !== undefined) {
        const s = Number(patch.shares);
        if (!(s > 0)) throw new I18nError('error.holding.sharesGt0', {}, 'Shares must be greater than 0');
        normalized.shares = s;
      }
      if (patch.costBasis !== undefined) {
        const c = Number(patch.costBasis);
        if (!(c >= 0)) throw new I18nError('error.holding.costBasisGte0', {}, 'Cost basis must be 0 or greater');
        normalized.costBasis = c;
      }
      if (patch.notes !== undefined) normalized.notes = patch.notes == null ? null : str(patch.notes);
      await updateHolding(exec, id, normalized);
      return;
    }
    case 'setHoldingPrice': {
      const id = str(args.id);
      const price = args.price == null ? null : Number(args.price);
      // Clearing the price always clears the date too — the UI never sends a
      // partial-null pair, so this just enforces the "both halves move
      // together" invariant rather than rejecting at the boundary.
      const date = price == null ? null : args.date == null ? null : str(args.date);
      if (price !== null && !(price >= 0)) throw new I18nError('error.holding.priceGte0', {}, 'Price must be 0 or greater');
      if (date !== null && !/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new I18nError('error.fx.dateFormat', {}, 'Date must be YYYY-MM-DD');
      await setHoldingPrice(exec, id, price, date);
      return;
    }
    case 'deleteHolding':
      await deleteHolding(exec, str(args.id));
      return;
    case 'changeLedgerBase': {
      const ledgerId = str(args.ledgerId);
      const newBase = str(args.newBase).trim().toUpperCase();
      if (!ledgerId) throw new I18nError('error.required.ledgerId', {}, 'ledgerId is required');
      if (!/^[A-Z]{3}$/.test(newBase)) throw new I18nError('error.ledger.newBaseISO', {}, 'newBase must be a 3-letter ISO code');
      const [row] = await exec('SELECT base_currency FROM ledgers WHERE id = ?', [ledgerId]);
      if (!row) throw new I18nError('error.notFound.ledger', {}, 'Ledger not found');
      if (String(row.base_currency) === newBase) return; // no-op
      const { recomputeAmountBases } = await import('./queries/ledgers');
      await recomputeAmountBases(exec, ledgerId, newBase);
      return;
    }
    case 'createLedger': {
      // Ledger CRUD (LEDGER_CRUD_PLAN §4). Validation: non-empty name; valid
      // ISO currency code; non-colliding id (the store picks the id, mirroring
      // every other createX action — server doesn't auto-generate).
      const id = str(args.id);
      const name = str(args.name).trim();
      const base = str(args.base).trim().toUpperCase();
      if (!id) throw new I18nError('error.required.id', {}, 'id is required');
      if (!name) throw new I18nError('error.required.name', {}, 'Name is required');
      if (!/^[A-Z]{3}$/.test(base)) throw new I18nError('error.ledger.baseISO', {}, 'base must be a 3-letter ISO code');
      const collide = await exec('SELECT id FROM ledgers WHERE id = ?', [id]);
      if (collide.length) throw new I18nError('error.ledger.duplicateId', {}, 'Ledger id already exists');
      const color = args.color == null ? null : String(args.color);
      const tagline = args.tagline == null ? null : String(args.tagline);
      const { createLedger } = await import('./domain/ledgers/queries');
      await createLedger(exec, { id, name, base, color, tagline });
      await ensureSystemCategories(exec, id);
      return;
    }
    case 'updateLedger': {
      const id = str(args.id);
      if (!id) throw new I18nError('error.required.id', {}, 'id is required');
      const patch = (args.patch ?? {}) as { name?: string; color?: string | null; tagline?: string | null };
      if (patch.name !== undefined && !String(patch.name).trim()) {
        throw new I18nError('error.ledger.nameEmpty', {}, 'Name cannot be empty');
      }
      const { updateLedger } = await import('./domain/ledgers/queries');
      await updateLedger(exec, id, {
        ...(patch.name !== undefined ? { name: String(patch.name).trim() } : {}),
        ...(patch.color !== undefined ? { color: patch.color == null ? null : String(patch.color) } : {}),
        ...(patch.tagline !== undefined ? { tagline: patch.tagline == null ? null : String(patch.tagline) } : {}),
      });
      return;
    }
    case 'setDefaultLedger': {
      const id = str(args.id);
      if (!id) throw new I18nError('error.required.id', {}, 'id is required');
      const exists = await exec('SELECT id FROM ledgers WHERE id = ?', [id]);
      if (!exists.length) throw new I18nError('error.notFound.ledger', {}, 'Ledger not found');
      const { setDefaultLedger } = await import('./domain/ledgers/queries');
      await setDefaultLedger(exec, id);
      return;
    }
    case 'deleteLedger': {
      // Ordered cascade + attachment-file sweep (LEDGER_CRUD_PLAN §5).
      const id = str(args.id);
      if (!id) throw new I18nError('error.required.id', {}, 'id is required');
      const { deleteLedger } = await import('./domain/ledgers/queries');
      const { relPaths } = await deleteLedger(exec, id);
      // Clean the ledger's key out of the displayCurrencyByLedger map so it
      // doesn't dangle. Other app_state slices are scalar/per-ledger-irrelevant.
      const raw = await getAppState(exec, 'displayCurrencyByLedger');
      if (raw) {
        try {
          const parsed = JSON.parse(raw);
          if (parsed && typeof parsed === 'object' && !Array.isArray(parsed) && id in parsed) {
            delete (parsed as Record<string, unknown>)[id];
            await setAppState(exec, 'displayCurrencyByLedger', JSON.stringify(parsed));
          }
        } catch {
          /* malformed — leave it */
        }
      }
      // Unlink attachment files after the DB rows are gone. Best-effort, same
      // semantics as the per-transaction delete path (RECEIPT_PHOTOS_PLAN §3.3).
      await unlinkAttachmentFiles(relPaths);
      return;
    }
    default:
      throw new I18nError('error.unknownAction', { action }, `Unknown action: ${action}`);
  }
}
