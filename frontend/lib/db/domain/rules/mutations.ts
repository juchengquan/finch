import type { Exec } from '../../core/repo';
import type { ActionName, Args } from '../_args';
import { I18nError } from '@/lib/i18n-error';
import { newId } from '../_shared/ids';
import {
  createRule as qCreateRule,
  updateRule as qUpdateRule,
  deleteRule as qDeleteRule,
} from './queries';
import type { RulePatchInput } from './types';
import type { Action, Condition, NewRule } from '@/lib/rules/types';

type Handler<A extends ActionName> = (exec: Exec, args: Args[A]) => Promise<void>;

const str = (v: unknown) => String(v);

export const handlers = {
  createRule: (exec, args: Args['createRule']) => {
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
    return qCreateRule(exec, id, input);
  },
  updateRule: (exec, args: Args['updateRule']) => {
    const patch = (args.patch ?? {}) as RulePatchInput;
    return qUpdateRule(exec, str(args.id), patch);
  },
  deleteRule: (exec, args: Args['deleteRule']) =>
    qDeleteRule(exec, str(args.id)),
  backfillRule: (_exec, _args: Args['backfillRule']) => {
    throw new Error('backfillRule: not yet implemented in per-domain mutations');
  },
} satisfies Partial<{ [K in ActionName]: Handler<K> }>;
