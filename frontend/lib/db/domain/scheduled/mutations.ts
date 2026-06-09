import type { Exec } from '../../core/repo';
import type { ActionName, Args } from '../_args';
import { I18nError } from '@/lib/i18n-error';
import { newId } from '../_shared/ids';
import { postSingle } from '../_shared/post-helpers';
import { postTransfer, postSimple } from '../../core/entries';
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

type Handler<A extends ActionName> = (exec: Exec, args: Args[A]) => Promise<void>;

const str = (v: unknown) => String(v);

export const handlers = {
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
    const date = new Date().toISOString().slice(0, 10);
    const desc = t.description || t.name;

    if (t.type === 'transfer') {
      if (!t.fromAccountId || !t.accountId) throw new I18nError('error.scheduled.missingAccount', { name: t.name }, `"${t.name}" is missing an account`);
      await postTransfer(exec, {
        fromAccountId: t.fromAccountId,
        toAccountId: t.accountId,
        fromAmount: Math.abs(Number(t.amount ?? 0)),
        date,
        note: desc,
        sourceTemplateId: t.id,
      });
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
  },
  generateDueScheduled: async (exec, args: Args['generateDueScheduled']) => {
    const today = args.today ? str(args.today) : new Date().toISOString().slice(0, 10);
    const rows = await exec('SELECT * FROM scheduled_templates WHERE is_active = 1');
    const ts = new Date().toISOString();
    for (const r of rows) {
      const type = String(r.kind);
      if (r.amount == null) continue;
      if (Number(r.splits_enabled)) continue;
      if (type === 'transfer' && r.from_account_id == null) continue;

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

      const existing = await exec('SELECT date FROM entries WHERE source_template_id = ?', [String(r.id)]);
      const have = new Set(existing.map((e) => String(e.date)));
      dates = dates.filter((d) => !have.has(d));
      const max = r.max_executions == null ? null : Number(r.max_executions);
      if (max != null) dates = dates.slice(0, Math.max(0, max - have.size));
      const installmentTotal = r.installment_total == null ? null : Number(r.installment_total);
      if (installmentTotal != null) dates = dates.slice(0, Math.max(0, installmentTotal - have.size));
      if (!dates.length) continue;

      const ledgerId = String(r.ledger_id);
      const acctId = String(r.account_id);
      const description = String(r.description ?? r.name ?? '');

      if (type === 'transfer') {
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
  },
} satisfies Partial<{ [K in ActionName]: Handler<K> }>;
