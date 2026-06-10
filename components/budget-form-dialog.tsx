'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { useTranslations } from 'next-intl';
import { useAppLocale } from '@/components/i18n-provider';
import { Clock, Edit, Plus } from '@/components/icons';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { useLedger } from '@/components/ledger-provider';
import { useFinanceStore, type NewBudgetInput } from '@/lib/store';
import { useMoney } from '@/components/use-money';
import type { BudgetRow, BudgetType } from '@/lib/db/domain/budgets/types';
import { periodLabel, nextPeriod, periodOf, type Frequency } from '@/lib/budgets/period';
import { MOCK } from '@/lib/data';
import { categoryPath } from '@/lib/db/domain/categories/queries';
import { cn } from '@/lib/utils';

const FREQUENCIES = ['daily', 'weekly', 'biweekly', 'monthly', 'quarterly', 'yearly'] as const;

interface BudgetFormDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Provided when editing; omitted to create. */
  budget?: BudgetRow;
  /** Preselect the type for a fresh budget (e.g. the active tab). */
  defaultType?: BudgetType;
}

// Multi-select rendered as a wrapping row of toggle chips. Empty selection means
// "all" (handled by the caller's matching logic), so we surface that hint.
function ChipMultiSelect({
  label,
  options,
  selected,
  onToggle,
}: {
  label: string;
  options: { id: string; name: string }[];
  selected: Set<string>;
  onToggle: (id: string) => void;
}) {
  const t = useTranslations('budgets.form.chip');
  return (
    <div className="flex flex-col gap-1.5">
      <Label>
        {label}{' '}
        <span className="text-muted-foreground font-normal">
          {selected.size ? t('summary', { count: selected.size }) : t('all')}
        </span>
      </Label>
      <div className="flex flex-wrap gap-1.5">
        {options.map((o) => {
          const on = selected.has(o.id);
          return (
            <button
              key={o.id}
              type="button"
              onClick={() => onToggle(o.id)}
              className={cn(
                'rounded-full border px-2.5 py-1 text-xs transition-colors',
                on
                  ? 'border-primary bg-primary/10 text-primary'
                  : 'border-border text-muted-foreground hover:text-foreground',
              )}
            >
              {o.name}
            </button>
          );
        })}
        {options.length === 0 && <span className="text-muted-foreground text-xs">{t('noneAvailable')}</span>}
      </div>
    </div>
  );
}

export function BudgetFormDialog({ open, onOpenChange, budget, defaultType = 'expense' }: BudgetFormDialogProps) {
  const { active, activeId } = useLedger();
  const { fmt } = useMoney();
  const t = useTranslations('budgets.form');
  const tCommon = useTranslations('common');
  const { locale } = useAppLocale();
  const accounts = useFinanceStore((s) => s.accounts);
  const storeCats = useFinanceStore((s) => s.categories);
  const budgetGroups = useFinanceStore((s) => s.budgetGroups);
  const createBudget = useFinanceStore((s) => s.createBudget);
  const updateBudget = useFinanceStore((s) => s.updateBudget);
  const updateBudgetCycle = useFinanceStore((s) => s.updateBudgetCycle);
  const clearPendingAmount = useFinanceStore((s) => s.clearPendingAmount);

  const editing = !!budget;
  const [name, setName] = useState(budget?.name ?? '');
  const [type, setType] = useState<BudgetType>(budget?.type ?? defaultType);
  const [groupId, setGroupId] = useState<string>(budget?.groupId ?? 'none');
  const [amount, setAmount] = useState(budget ? String(budget.amount) : '');
  const [frequency, setFrequency] = useState(budget?.frequency ?? 'monthly');
  const [startDate, setStartDate] = useState(budget?.startDate ?? '2026-05-01');
  const [recurring, setRecurring] = useState(budget ? budget.isRecurring === 1 : defaultType === 'expense');
  const [rollover, setRollover] = useState(budget ? budget.rollover === 1 : false);
  const [accountIds, setAccountIds] = useState<Set<string>>(new Set(budget?.accountIds ?? []));
  const [categoryIds, setCategoryIds] = useState<Set<string>>(new Set(budget?.categoryIds ?? []));

  const ledgerAccounts = accounts
    .filter((a) => a.ledgerId === activeId)
    .map((a) => ({ id: a.id, name: a.name }));
  const ledgerGroups = budgetGroups.filter((g) => g.ledgerId === activeId);
  // Labels render as `Parent › Child › Leaf` so descendants are
  // unambiguous in the filter chip multiselect (CATEGORIES_LEVEL3_PLAN
  // §5.1). Recursive budget matching (§4.2) means picking a parent here
  // also catches every descendant at match time.
  const projectedLedgerCats = storeCats.filter((c) => c.ledgerId === activeId);
  const projectedLedgerCatById = new Map(projectedLedgerCats.map((c) => [c.id, c]));
  const ledgerCats = (storeCats.length
    ? projectedLedgerCats
        .map((c) => ({ id: c.id, name: categoryPath(c, projectedLedgerCatById) }))
        .sort((a, b) => a.name.localeCompare(b.name))
    : MOCK.categories
        .filter((c) => ((c as { ledger?: string }).ledger ?? 'personal') === activeId)
        .map((c) => ({ id: c.id, name: c.name })));

  const toggle = (set: Set<string>, setter: (s: Set<string>) => void, id: string) => {
    const next = new Set(set);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setter(next);
  };

  // What's actually changed vs the source row — drives the cycle-change /
  // amount-staging routing per BUDGET_CYCLES_PLAN §4.
  const cycleChanged = editing && budget != null
    && (frequency !== budget.frequency || startDate !== budget.startDate);
  const amountChanged = editing && budget != null
    && parseFloat(amount || '0') !== budget.amount;
  const recurringNow = editing ? (budget?.isRecurring === 1) : recurring;
  const stagingPath = editing && !cycleChanged && amountChanged && recurringNow
    && [name.trim()].every((v) => v === budget?.name) // only the amount differed
    && groupId === (budget?.groupId ?? 'none')
    && (recurring ? 1 : 0) === (budget?.isRecurring ?? 1)
    && (type === 'expense' && rollover ? 1 : 0) === (budget?.rollover ?? 0)
    && JSON.stringify([...accountIds].sort()) === JSON.stringify([...(budget?.accountIds ?? [])].sort())
    && JSON.stringify([...categoryIds].sort()) === JSON.stringify([...(budget?.categoryIds ?? [])].sort())
    && type === budget?.type;

  // Period-label hint for "takes effect next period" / "applies now".
  const nextPeriodLabel = editing && budget != null && recurringNow
    ? (() => {
        try {
          const today = new Date().toISOString().slice(0, 10);
          const current = periodOf(today, budget.frequency as Frequency, budget.startDate);
          const np = nextPeriod(current, budget.frequency as Frequency, budget.startDate);
          return periodLabel(np, budget.frequency as Frequency, budget.startDate, locale);
        } catch {
          return null;
        }
      })()
    : null;

  const submitHint = !editing
    ? null
    : cycleChanged
      ? t('hint.cycleImmediate')
      : stagingPath && nextPeriodLabel
        ? t('hint.amountStaged', { period: nextPeriodLabel })
        : amountChanged || cycleChanged
          ? t('hint.saveImmediate')
          : t('hint.saveChanges');

  const submit = () => {
    const n = name.trim();
    const amt = parseFloat(amount);
    if (!n) return void toast.error(t('errors.name'));
    if (!(amt > 0)) return void toast.error(type === 'income' ? t('errors.targetGt0') : t('errors.limitGt0'));
    const group = groupId === 'none' ? null : groupId;
    const cats = [...categoryIds];
    const accts = [...accountIds];
    const rolloverInt = type === 'expense' && rollover && frequency !== 'daily' ? 1 : 0;

    if (editing && budget) {
      if (cycleChanged) {
        // Cycle change is immediate per §4a: amount carries over,
        // pending_amount discarded, last_rolled_period reset.
        updateBudgetCycle(budget.id, {
          frequency,
          startDate,
          amount: amountChanged ? amt : undefined,
        });
        // Bundle any non-cycle edits through updateBudget; the server's
        // amount-staging rule won't trigger because the patch isn't
        // amount-only.
        const sidePatch = {
          name: n !== budget.name ? n : undefined,
          type: type !== budget.type ? type : undefined,
          groupId: group !== (budget.groupId ?? null) ? group : undefined,
          isRecurring: (recurring ? 1 : 0) !== budget.isRecurring ? (recurring ? 1 : 0) : undefined,
          rollover: rolloverInt !== budget.rollover ? rolloverInt : undefined,
          accountIds: JSON.stringify(accts.sort()) !== JSON.stringify([...budget.accountIds].sort()) ? accts : undefined,
          categoryIds: JSON.stringify(cats.sort()) !== JSON.stringify([...budget.categoryIds].sort()) ? cats : undefined,
        };
        const hasSide = Object.values(sidePatch).some((v) => v !== undefined);
        if (hasSide) updateBudget(budget.id, sidePatch);
        toast.success(t('toasts.cycleUpdated'), { description: `${n} · ${t(`frequencies.${frequency as Frequency}`)}` });
      } else {
        updateBudget(budget.id, {
          name: n,
          type,
          amount: amt,
          groupId: group,
          isRecurring: recurring ? 1 : 0,
          rollover: rolloverInt,
          accountIds: accts,
          categoryIds: cats,
        });
        toast.success(
          stagingPath ? t('toasts.amountStaged') : t('toasts.updated'),
          { description: stagingPath && nextPeriodLabel ? t('toasts.stagedTakesEffect', { period: nextPeriodLabel }) : n },
        );
      }
    } else {
      const input: NewBudgetInput = {
        name: n,
        type,
        amount: amt,
        groupId: group,
        frequency,
        startDate,
        isRecurring: recurring,
        rollover: type === 'expense' && rollover && frequency !== 'daily',
        accountIds: accts,
        categoryIds: cats,
        ledgerId: activeId,
      };
      createBudget(input);
      toast.success(t('toasts.created'), { description: n });
    }
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[88vh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{editing ? t('editTitle') : t('newTitle')}</DialogTitle>
          <DialogDescription>
            {type === 'income' ? t('incomeDescription', { ledger: active.name }) : t('expenseDescription', { ledger: active.name })}
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-col gap-3">
          {/* Type toggle */}
          <div className="bg-secondary inline-flex rounded-full p-1">
            {(['expense', 'income'] as BudgetType[]).map((tv) => (
              <button
                key={tv}
                type="button"
                onClick={() => {
                  setType(tv);
                  if (!editing) setRecurring(tv === 'expense');
                }}
                className={cn(
                  'flex-1 rounded-full px-4 py-1.5 text-[13px] font-medium transition-colors',
                  type === tv ? 'bg-background text-foreground shadow-sm' : 'text-muted-foreground',
                )}
              >
                {t(`types.${tv}`)}
              </button>
            ))}
          </div>

          <div className="flex flex-col gap-1.5">
            <Label htmlFor="b-name">{t('name')}</Label>
            <Input id="b-name" value={name} onChange={(e) => setName(e.target.value)} autoFocus placeholder={type === 'income' ? t('incomePlaceholder') : t('expensePlaceholder')} />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="b-amount">{type === 'income' ? t('target') : t('limit')}</Label>
              <Input id="b-amount" type="number" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.00" />
              {budget?.pendingAmount != null && (
                <div className="text-warning bg-warning/10 mt-0.5 flex items-center justify-between gap-2 rounded-md px-2 py-1 text-[11px]">
                  <span>
                    <Clock size={11} className="-mt-0.5 mr-1 inline" />
                    {nextPeriodLabel
                      ? t('pendingChipWithPeriod', { amount: fmt(budget.pendingAmount), period: nextPeriodLabel })
                      : t('pendingChip', { amount: fmt(budget.pendingAmount) })}
                  </span>
                  <button
                    type="button"
                    className="hover:underline"
                    onClick={() => clearPendingAmount(budget.id)}
                  >
                    {t('clearPending')}
                  </button>
                </div>
              )}
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="b-group">{t('group')}</Label>
              <Select value={groupId} onValueChange={setGroupId}>
                <SelectTrigger id="b-group" className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">{t('noGroup')}</SelectItem>
                  {ledgerGroups.map((g) => <SelectItem key={g.id} value={g.id}>{g.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="b-freq">{t('cycle')}</Label>
              <Select value={frequency} onValueChange={setFrequency}>
                <SelectTrigger id="b-freq" className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {FREQUENCIES.map((f) => <SelectItem key={f} value={f}>{t(`frequencies.${f}`)}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="b-start">{t('startDate')}</Label>
              <Input id="b-start" type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} />
            </div>
          </div>

          <div className="flex items-center justify-between gap-3 text-sm">
            <Label htmlFor="b-recurring" className="cursor-pointer font-normal">
              {t('recurring')}
              <span className="text-muted-foreground">{t('recurringSuffix', { hint: recurring ? t('recurringRepeats') : type === 'income' ? t('recurringOneShotGoal') : t('recurringOneTime') })}</span>
            </Label>
            <Switch id="b-recurring" checked={recurring} onCheckedChange={setRecurring} />
          </div>

          {type === 'expense' && (
            <div className={cn('flex items-center justify-between gap-3 text-sm', frequency === 'daily' && 'opacity-50')}>
              <Label
                htmlFor="b-rollover"
                className={cn('font-normal', frequency === 'daily' ? 'cursor-not-allowed' : 'cursor-pointer')}
              >
                {t('rollover')}
                {frequency === 'daily' && (
                  <span className="text-muted-foreground ml-2 text-[11px]">{t('rolloverDailyHint')}</span>
                )}
              </Label>
              <Switch
                id="b-rollover"
                checked={rollover && frequency !== 'daily'}
                disabled={frequency === 'daily'}
                onCheckedChange={setRollover}
              />
            </div>
          )}

          <ChipMultiSelect label={t('categories')} options={ledgerCats} selected={categoryIds} onToggle={(id) => toggle(categoryIds, setCategoryIds, id)} />
          <ChipMultiSelect label={t('accounts')} options={ledgerAccounts} selected={accountIds} onToggle={(id) => toggle(accountIds, setAccountIds, id)} />
        </div>

        {submitHint && (
          <div className="text-muted-foreground mt-1 text-[11px]">{submitHint}</div>
        )}

        <DialogFooter>
          <DialogClose asChild>
            <Button variant="outline">{tCommon('cancel')}</Button>
          </DialogClose>
          <Button onClick={submit}>
            {editing ? <Edit size={14} /> : <Plus size={14} />}
            {editing ? tCommon('save') : tCommon('create')}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
