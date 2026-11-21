import type { Exec, Row } from '../../core/repo';
import type { ActionName, Args } from '../_args';
import { I18nError } from '@/lib/i18n-error';
import { newId } from '../_shared/ids';
import { postSingle } from '../_shared/post-helpers';
import { postTransfer, postSimple, postEntry, type LegInput } from '../../core/entries';
import { resolveCounterpartyIdByName } from '../counterparties/queries';
import { occurrencesUpTo } from '@/lib/recurrence';
import type { ScheduledTemplate } from '@/lib/store';
import { parseInstallmentTotal } from '@/lib/installment';
import {
  createScheduled as qCreateScheduled,
  updateScheduled as qUpdateScheduled,
  deleteScheduled as qDeleteScheduled,
  addScheduledSplit as qAddScheduledSplit,
  removeScheduledSplit as qRemoveScheduledSplit,
  getScheduled as qGetScheduled,
  type ScheduledPatch,
} from './queries';
import { resolveTemplateLedger } from './_helpers';
import { getAppState, setAppState } from '../../queries/appState';
import { handlers as transactionHandlers } from '../transactions/mutations';
import { resolveEntryRef } from '../../core/entries';

type Handler<A extends ActionName> = (exec: Exec, args: Args[A]) => Promise<void>;

const str = (v: unknown) => String(v);

// The time a posting carries: an explicitly requested one, else the template's
// intended time-of-day, else the moment it fires.
//
// Never null, and that is the point: an entry with a NULL time sinks to the BOTTOM
// of its day, since the feed orders by `date DESC, time DESC` and SQLite sorts NULLs
// last. `explicit` is what keeps it deterministic — the app omits it and gets the
// firing moment, the parity fixture pins it, exactly as `date` already works.
function postingTime(explicit?: string): string {
  if (explicit) return explicit;
  const d = new Date();
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

// One generated occurrence's post, skipped when it is refused for want of an
// exchange rate. Skipped, not thrown: rates are per day, so the template's other
// occurrences may still post, and this one stays unposted and so still due —
// posting it by hand says why. The refusal comes from the leg conversion, before
// anything is written. Mirrors the native `Scheduled.materializeDue`.
async function skippingNoRate(post: () => Promise<unknown>): Promise<void> {
  try {
    await post();
  } catch (e) {
    if (!(e instanceof I18nError && e.code === 'error.fx.noRate')) throw e;
  }
}

// Skipped occurrences: app_state 'scheduledSkips', { templateId: [date, …] },
// keys and dates sorted. The native app wrote it first (FinchCore
// `ScheduledSkips`); the web now honours and records it too, so a cancelled
// occurrence stays cancelled instead of being generated again on the next load.
const SKIPS_KEY = 'scheduledSkips';

async function loadSkips(exec: Exec): Promise<Record<string, string[]>> {
  const raw = await getAppState(exec, SKIPS_KEY);
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw) as unknown;
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? (parsed as Record<string, string[]>) : {};
  } catch {
    return {}; // a malformed blob must not stop generation
  }
}

async function saveSkips(exec: Exec, map: Record<string, string[]>): Promise<void> {
  const sorted: Record<string, string[]> = {};
  for (const k of Object.keys(map).sort()) sorted[k] = [...map[k]].sort();
  await setAppState(exec, SKIPS_KEY, JSON.stringify(sorted));
}

function templateOf(r: Row): ScheduledTemplate {
  return {
    startDate: r.start_date == null ? undefined : String(r.start_date),
    nextRun: String(r.next_run ?? ''),
    endDate: r.end_date == null ? null : String(r.end_date),
    frequency: String(r.frequency),
    dayOfMonth: Number(r.day_of_month ?? 1),
    weekDay: r.day_of_week == null ? undefined : Number(r.day_of_week),
  } as ScheduledTemplate;
}

// Record a skip for one occurrence, when there is one to record: the template
// exists, the date is one of its occurrences, and no row fulfils it.
// FinchCore `Scheduled.skip` with its "nothing to skip" refusals as no-ops.
async function skipIfOccurrence(exec: Exec, templateId: string, date: string): Promise<void> {
  const [t] = await exec('SELECT * FROM scheduled_templates WHERE id = ?', [templateId]);
  if (!t) return;
  if (occurrencesUpTo(templateOf(t), date).at(-1) !== date) return;
  const [{ n }] = await exec(
    'SELECT COUNT(*) AS n FROM entries WHERE source_template_id = ? AND COALESCE(occurrence_date, date) = ?',
    [templateId, date],
  );
  if (Number(n) > 0) return;
  const skips = await loadSkips(exec);
  const dates = new Set(skips[templateId] ?? []);
  if (dates.has(date)) return;
  dates.add(date);
  skips[templateId] = [...dates];
  await saveSkips(exec, skips);
}

export const handlers = {
  // Delete a transaction and count the scheduled occurrence it fulfilled as
  // skipped, so the generator doesn't post it again on the next load (it used
  // to: cancel deleted the pending row, the next load re-created it). Only an
  // occurrence dated on or before `today`; one posted early and deleted goes
  // back to upcoming. Same as FinchCore `Scheduled.deleteSkippingOccurrence`.
  deleteTransactionSkippingOccurrence: async (exec, args: Args['deleteTransactionSkippingOccurrence']) => {
    const today = str(args.today ?? '');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(today)) {
      throw new I18nError('error.invalidArgs', {}, 'deleteTransactionSkippingOccurrence requires today as YYYY-MM-DD');
    }
    const ref = await resolveEntryRef(exec, str(args.id));
    if (!ref) return;
    const fulfilled = await exec(
      `SELECT DISTINCT source_template_id AS t, COALESCE(occurrence_date, date) AS d
         FROM entries WHERE id = ? AND source_template_id IS NOT NULL`,
      [ref.entryId],
    );
    await transactionHandlers.deleteTransaction(exec, { id: str(args.id) });
    for (const o of fulfilled) {
      if (String(o.d) <= today) await skipIfOccurrence(exec, String(o.t), String(o.d));
    }
  },
  createScheduled: async (exec, args: Args['createScheduled']) => {
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
  },
  updateScheduled: async (exec, args: Args['updateScheduled']) => {
    const patch = { ...(args.patch ?? {}) } as ScheduledPatch & { installmentTotal?: unknown };
    if (patch.name !== undefined && !str(patch.name).trim()) throw new I18nError('error.required.templateName', {}, 'Template name is required');
    if ('installmentTotal' in patch) {
      patch.installmentTotal = parseInstallmentTotal(patch.installmentTotal);
    }
    await qUpdateScheduled(exec, str(args.id), patch);
  },
  deleteScheduled: (exec, args: Args['deleteScheduled']) =>
    qDeleteScheduled(exec, str(args.id)),
  addScheduledSplit: async (exec, args: Args['addScheduledSplit']) => {
    const accountId = str(args.accountId).trim();
    if (!accountId) throw new I18nError('error.required.splitAccount', {}, 'A split needs an account');
    await qAddScheduledSplit(exec, str(args.templateId), accountId, Number(args.pct) || 0);
  },
  updateScheduledSplit: async (exec, args: Args['updateScheduledSplit']) => {
    await exec(
      `UPDATE scheduled_splits SET amount_pct = ?
        WHERE id = (SELECT id FROM scheduled_splits WHERE template_id = ? ORDER BY sort_order LIMIT 1 OFFSET ?)`,
      [Number(args.pct), str(args.templateId), Number(args.index)],
    );
  },
  removeScheduledSplit: (exec, args: Args['removeScheduledSplit']) =>
    qRemoveScheduledSplit(exec, str(args.templateId), Number(args.index)),
  postScheduled: async (exec, args: Args['postScheduled']) => {
    const templateId = str(args.templateId);
    const t = await qGetScheduled(exec, templateId);
    if (!t) throw new I18nError('error.notFound.template', {}, 'Template not found');
    const ledgerId = await resolveTemplateLedger(exec, templateId);
    if (t.installmentTotal != null && (t.installmentPaid ?? 0) >= t.installmentTotal) {
      throw new I18nError(
        'error.scheduled.installmentDone',
        { name: t.name, total: t.installmentTotal },
        `"${t.name}" has finished its ${t.installmentTotal}-payment plan`,
      );
    }
    // Explicit date wins; otherwise today (unchanged legacy behaviour). The
    // occurrence defaults to the posting date, so a plain post still resolves
    // its own cell.
    const date = args.date ? str(args.date) : new Date().toISOString().slice(0, 10);
    const occurrenceDate = args.occurrenceDate ? str(args.occurrenceDate) : date;
    const desc = t.description || t.name;
    const postTime = postingTime(args.time ? str(args.time) : undefined);

    if (t.type === 'transfer') {
      if (!t.fromAccountId || !t.accountId) throw new I18nError('error.scheduled.missingAccount', { name: t.name }, `"${t.name}" is missing an account`);
      await postTransfer(exec, {
        fromAccountId: t.fromAccountId,
        toAccountId: t.accountId,
        fromAmount: Math.abs(Number(t.amount ?? 0)),
        date,
        time: postTime,
        note: desc,
        sourceTemplateId: t.id,
        occurrenceDate,
      });
      return;
    }

    if (t.amount == null) throw new I18nError('error.scheduled.variableAmount', { name: t.name }, `"${t.name}" has a variable amount — add it manually`);
    const sign = t.type === 'income' ? 1 : -1;

    if (t.type === 'income' && t.splits?.length) {
      // ONE transaction with an account leg per split — the same shape the Add
      // sheet produces for a split payment (mirrors ios/.../Scheduled.swift). This
      // used to call postSingle once per split, so a salary paid into two accounts
      // became two unrelated transactions while the identical split entered by
      // hand became one.
      //
      // A single entry has a single `description`, so each split's own
      // `description` has no per-row home any more. It is carried onto that leg's
      // `memo` instead of being dropped — reproducing EXACTLY the string the old
      // per-split loop used to stamp as that row's own `description`
      // (`${desc} · ${sp.label}`), so an existing split template looks unchanged
      // in the feed after this ships. `memo ?? description` is what the
      // projection shows, so a split with no label gets no memo at all (falls
      // through to the entry's own description) rather than a dangling " · " or
      // a redundant duplicate.
      const legs: LegInput[] = [];
      for (const sp of t.splits) {
        const portion = sp.abs != null ? sp.abs : (t.amount * (sp.pct ?? 0)) / 100;
        if (!portion) continue;
        legs.push({ accountId: sp.accountId, amount: portion, memo: sp.label ? `${desc} · ${sp.label}` : null });
      }
      if (!legs.length) throw new I18nError('error.scheduled.noSplits', { name: t.name }, `No split amounts to post for "${t.name}"`);
      await postEntry(exec, {
        ledgerId, date, time: postTime, description: desc, kind: 'income',
        legs, autoBalanceCategoryId: t.category ?? null,
        sourceTemplateId: t.id, occurrenceDate,
      });
      return;
    }

    await postSingle(exec, ledgerId, t.accountId, sign * t.amount, desc, date, t.id, t.category ?? null, occurrenceDate, postTime);
  },
  generateDueScheduled: async (exec, args: Args['generateDueScheduled']) => {
    const today = args.today ? str(args.today) : new Date().toISOString().slice(0, 10);
    const genTime = postingTime(args.time ? str(args.time) : undefined);
    const rows = await exec('SELECT * FROM scheduled_templates WHERE is_active = 1');
    const skips = await loadSkips(exec);
    const ts = new Date().toISOString();
    for (const r of rows) {
      // Each template in its own SAVEPOINT: one that throws (only imported data can
      // hold one, e.g. a transfer from an account to itself) rolls back its own rows
      // and is passed over, instead of failing the sweep — every other template's
      // rows with it, on every load. Mirrors the native `Scheduled.materializeDue`.
      const sp = `gd_${Date.now().toString(36)}${Math.floor(Math.random() * 1e4)}`;
      await exec(`SAVEPOINT ${sp}`);
      try {
        await generateDueForTemplate(exec, r, today, genTime, ts, skips[String(r.id)] ?? []);
        await exec(`RELEASE ${sp}`);
      } catch {
        await exec(`ROLLBACK TO ${sp}`);
        await exec(`RELEASE ${sp}`);
      }
    }
  },
} satisfies Partial<{ [K in ActionName]: Handler<K> }>;

// One template row's due occurrences, posted. `generateDueScheduled` runs it.
async function generateDueForTemplate(
  exec: Exec, r: Row, today: string, genTime: string, ts: string, skipped: string[],
): Promise<void> {
  const type = String(r.kind);
  if (r.amount == null) return;
  if (Number(r.splits_enabled)) return;
  if (type === 'transfer' && r.from_account_id == null) return;

  // Skipped occurrences leave the list before the caps below, so they spend
  // none of them: a skip is not an execution (FinchCore `dueOccurrences`).
  const skippedSet = new Set(skipped);
  let dates = occurrencesUpTo(templateOf(r), today).filter((d) => !skippedSet.has(d));
  if (!dates.length) return;

  // Resolution keys on occurrenceDate ?? date (see Resolvers), so "already
  // posted" must key on the same coalesce — not the raw posting date —
  // or an occurrence posted under a different transaction date (e.g. paid
  // late) is not recognised and gets regenerated as a duplicate.
  const existing = await exec(
    'SELECT COALESCE(occurrence_date, date) AS date FROM entries WHERE source_template_id = ?',
    [String(r.id)],
  );
  const have = new Set(existing.map((e) => String(e.date)));
  dates = dates.filter((d) => !have.has(d));
  const max = r.max_executions == null ? null : Number(r.max_executions);
  if (max != null) dates = dates.slice(0, Math.max(0, max - have.size));
  const installmentTotal = r.installment_total == null ? null : Number(r.installment_total);
  if (installmentTotal != null) dates = dates.slice(0, Math.max(0, installmentTotal - have.size));
  if (!dates.length) return;

  const ledgerId = String(r.ledger_id);
  const acctId = String(r.account_id);
  const description = String(r.description ?? r.name ?? '');

  if (type === 'transfer') {
    const fromAccountId = String(r.from_account_id);
    const fromAmount = Math.abs(Number(r.amount));
    const sourceTemplateId = String(r.id);
    for (const date of dates) {
      await skippingNoRate(() => postTransfer(exec, {
        fromAccountId, toAccountId: acctId, fromAmount, date, time: genTime,
        note: description || null, sourceTemplateId, occurrenceDate: date, timestamp: ts,
      }));
    }
    return;
  }

  const amount = (type === 'income' ? 1 : -1) * Number(r.amount);
  const categoryId = r.category_id == null ? null : String(r.category_id);
  const cpId = await resolveCounterpartyIdByName(exec, description);
  for (const date of dates) {
    await skippingNoRate(() => postSimple(exec, {
      ledgerId, accountId: acctId, date, time: genTime,
      amount, description, categoryId,
      kind: type === 'income' ? 'income' : 'expense',
      status: 'pending',
      sourceTemplateId: String(r.id),
      occurrenceDate: date,
      counterpartyId: cpId,
      timestamp: ts,
    }));
  }
}
