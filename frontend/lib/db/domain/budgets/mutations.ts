import type { Exec } from '../../core/repo';
import type { ActionName, Args } from '../_args';
import { I18nError } from '@/lib/i18n-error';
import { newId } from '../_shared/ids';
import { withDedupMessage } from '../_shared/with-dedup-message';
import {
  createBudget as qCreateBudget,
  updateBudget as qUpdateBudget,
  updateBudgetCycle as qUpdateBudgetCycle,
  stageBudgetAmount,
  clearPendingAmount as qClearPendingAmount,
  deleteBudget as qDeleteBudget,
  contributeBudget as qContributeBudget,
  type BudgetPatch,
  type BudgetCyclePatch,
  type BudgetType,
} from './queries';
import {
  createBudgetGroup as qCreateBudgetGroup,
  updateBudgetGroup as qUpdateBudgetGroup,
  deleteBudgetGroup as qDeleteBudgetGroup,
  type BudgetGroupPatch,
} from '../budgetGroups/queries';

type Handler<A extends ActionName> = (exec: Exec, args: Args[A]) => Promise<void>;

const str = (v: unknown) => String(v);

export const handlers = {
  createBudget: async (exec, args: Args['createBudget']) => {
    const ledgerId = str(args.ledgerId || 'personal');
    const name = str(args.name).trim();
    if (!name) throw new I18nError('error.required.budgetName', {}, 'Budget name is required');
    const type: BudgetType = str(args.type) === 'income' ? 'income' : 'expense';
    const amount = Number(args.amount);
    if (!(amount > 0)) throw new I18nError('error.budget.amountGt0', {}, 'Budget amount must be greater than 0');
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
      tagIds: strList(args.tagIds),
      counterpartyIds: strList(args.counterpartyIds),
      warningPct: args.warningPct != null ? Number(args.warningPct) : 80,
    }));
  },
  updateBudget: async (exec, args: Args['updateBudget']) => {
    const patch = (args.patch ?? {}) as BudgetPatch;
    if (patch.name !== undefined && !str(patch.name).trim()) throw new I18nError('error.required.budgetName', {}, 'Budget name is required');
    if (patch.amount !== undefined && !(Number(patch.amount) > 0)) throw new I18nError('error.budget.amountGt0', {}, 'Budget amount must be greater than 0');
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
    await qUpdateBudget(exec, str(args.id), patch);
  },
  updateBudgetCycle: async (exec, args: Args['updateBudgetCycle']) => {
    const patch = (args.patch ?? {}) as BudgetCyclePatch;
    const validFreqs = ['daily','weekly','biweekly','monthly','quarterly','yearly'];
    if (!validFreqs.includes(patch.frequency)) throw new I18nError('error.budget.unknownFreq', { freq: String(patch.frequency) }, `Unknown frequency "${patch.frequency}"`);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(patch.startDate)) throw new I18nError('error.budget.dateFormat', {}, 'startDate must be YYYY-MM-DD');
    if (patch.amount !== undefined && !(Number(patch.amount) > 0)) throw new I18nError('error.budget.amountGt0', {}, 'Budget amount must be greater than 0');
    await qUpdateBudgetCycle(exec, str(args.id), patch);
  },
  clearPendingAmount: (exec, args: Args['clearPendingAmount']) =>
    qClearPendingAmount(exec, str(args.id)),
  removeBudget: (exec, args: Args['removeBudget']) =>
    qDeleteBudget(exec, str(args.id)),
  contributeBudget: async (exec, args: Args['contributeBudget']) => {
    const amount = Number(args.amount);
    if (!Number.isFinite(amount)) throw new I18nError('error.budget.invalidContribution', {}, 'Invalid contribution amount');
    await qContributeBudget(exec, str(args.id), amount);
  },
  createBudgetGroup: async (exec, args: Args['createBudgetGroup']) => {
    const name = str(args.name).trim();
    if (!name) throw new I18nError('error.required.groupName', {}, 'Group name is required');
    await qCreateBudgetGroup(exec, {
      id: str(args.id || newId('bgg')),
      ledgerId: str(args.ledgerId || 'personal'),
      name,
      color: args.color ?? null,
    });
  },
  updateBudgetGroup: async (exec, args: Args['updateBudgetGroup']) => {
    const patch = (args.patch ?? {}) as BudgetGroupPatch;
    if (patch.name !== undefined && !str(patch.name).trim()) throw new I18nError('error.required.groupName', {}, 'Group name is required');
    await qUpdateBudgetGroup(exec, str(args.id), patch);
  },
  deleteBudgetGroup: (exec, args: Args['deleteBudgetGroup']) =>
    qDeleteBudgetGroup(exec, str(args.id)),
} satisfies Partial<{ [K in ActionName]: Handler<K> }>;
