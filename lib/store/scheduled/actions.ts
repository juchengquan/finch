// frontend/lib/store/scheduled/actions.ts — scheduled template action creators.
// Extracted from lib/store.ts:834-861 (updateScheduledSplit, addScheduledSplit,
// removeScheduledSplit) + lib/store.ts:1008-1045 (createScheduled, updateScheduled,
// deleteScheduled).

import { newId } from '../_shared/ids';
import { syncMutation } from '../hydrate';
import type { SetState, GetState } from '../_shared/types';

export const scheduledActions = (set: SetState, get: GetState) => ({
  createScheduled: (input: {
    name: string;
    description?: string | null;
    type?: string;
    amount?: number | null;
    frequency?: string;
    dayOfMonth?: number;
    weekDay?: number;
    accountId: string;
    account?: string;
    fromAccountId?: string;
    from?: string;
    autoPost?: boolean;
    color?: string | null;
    category?: string | null;
    startDate?: string;
    endDate?: string | null;
    maxExecutions?: number | null;
    installmentTotal?: number | null;
    ledgerId?: string;
  }): string => {
    const id = newId('sch', { long: false });
    const ledgerId = input.ledgerId ?? 'personal';
    const type = input.type ?? 'expense';
    const frequency = input.frequency ?? 'monthly';
    const dayOfMonth = input.dayOfMonth ?? 1;
    const weekDay = input.weekDay;
    const autoPost = input.autoPost ? 1 : 0;
    const amount = input.amount ?? null;
    const color = input.color ?? null;
    const description = input.description ?? null;
    const accountId = input.accountId;
    const account = input.account ?? '';
    const fromAccountId = input.fromAccountId;
    const category = input.category ?? null;
    const startDate = input.startDate ?? '';
    const endDate = input.endDate ?? null;
    const maxExecutions = input.maxExecutions ?? null;
    const installmentTotal = input.installmentTotal ?? null;
    set((s) => ({
      scheduled: [
        ...s.scheduled,
        { id, name: input.name, description, type, amount, frequency, dayOfMonth, weekDay, accountId, account, fromAccountId, from: input.from, autoPost, nextRun: '', lastRun: '', color, category, startDate, endDate, maxExecutions, installmentTotal, installmentPaid: 0 },
      ],
    }));
    syncMutation('createScheduled', { id, ledgerId, name: input.name, description, type, amount, frequency, dayOfMonth, weekDay: weekDay ?? null, accountId, fromAccountId: fromAccountId ?? null, autoPost: !!input.autoPost, color, category, startDate, endDate, maxExecutions, installmentTotal });
    return id;
  },

  updateScheduled: (
    id: string,
    patch: {
      name?: string;
      description?: string | null;
      amount?: number | null;
      frequency?: string;
      dayOfMonth?: number;
      weekDay?: number;
      autoPost?: number;
      color?: string | null;
      category?: string | null;
      endDate?: string | null;
      maxExecutions?: number | null;
      installmentTotal?: number | null;
    },
  ): void => {
    set((s) => ({ scheduled: s.scheduled.map((t) => (t.id === id ? { ...t, ...patch } : t)) }));
    syncMutation('updateScheduled', { id, patch });
  },

  deleteScheduled: (id: string): void => {
    set((s) => ({ scheduled: s.scheduled.filter((t) => t.id !== id) }));
    syncMutation('deleteScheduled', { id });
  },

  updateScheduledSplit: (templateId: string, index: number, pct: number): void => {
    set((s) => ({
      scheduled: s.scheduled.map((t) =>
        t.id === templateId && t.splits
          ? { ...t, splits: t.splits.map((sp, i) => (i === index ? { ...sp, pct } : sp)) }
          : t,
      ),
    }));
    syncMutation('updateScheduledSplit', { templateId, index, pct });
  },

  addScheduledSplit: (templateId: string, accountId: string, account: string, pct: number): void => {
    set((s) => ({
      scheduled: s.scheduled.map((t) =>
        t.id === templateId ? { ...t, splits: [...(t.splits ?? []), { accountId, account, pct, abs: null, label: '' }] } : t,
      ),
    }));
    syncMutation('addScheduledSplit', { templateId, accountId, pct });
  },

  removeScheduledSplit: (templateId: string, index: number): void => {
    set((s) => ({
      scheduled: s.scheduled.map((t) =>
        t.id === templateId && t.splits ? { ...t, splits: t.splits.filter((_, i) => i !== index) } : t,
      ),
    }));
    syncMutation('removeScheduledSplit', { templateId, index });
  },
});
