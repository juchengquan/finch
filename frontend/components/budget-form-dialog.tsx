'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Icon } from '@/components/primitives';
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
import { useLedger } from '@/components/ledger-provider';
import { useFinanceStore, type NewBudgetInput } from '@/lib/store';
import type { BudgetRow, BudgetType } from '@/lib/db/queries/budgets';
import { MOCK } from '@/lib/data';
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
  return (
    <div className="flex flex-col gap-1.5">
      <Label>
        {label}{' '}
        <span className="text-muted-foreground font-normal">
          {selected.size ? `· ${selected.size}` : '· all'}
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
        {options.length === 0 && <span className="text-muted-foreground text-xs">None available</span>}
      </div>
    </div>
  );
}

export function BudgetFormDialog({ open, onOpenChange, budget, defaultType = 'expense' }: BudgetFormDialogProps) {
  const { active, activeId } = useLedger();
  const accounts = useFinanceStore((s) => s.accounts);
  const storeCats = useFinanceStore((s) => s.categories);
  const budgetGroups = useFinanceStore((s) => s.budgetGroups);
  const createBudget = useFinanceStore((s) => s.createBudget);
  const updateBudget = useFinanceStore((s) => s.updateBudget);

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
  const ledgerCats = (storeCats.length
    ? storeCats.filter((c) => c.ledgerId === activeId).map((c) => ({ id: c.id, name: c.name }))
    : MOCK.categories
        .filter((c) => ((c as { ledger?: string }).ledger ?? 'personal') === activeId)
        .map((c) => ({ id: c.id, name: c.name })));

  const toggle = (set: Set<string>, setter: (s: Set<string>) => void, id: string) => {
    const next = new Set(set);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setter(next);
  };

  const submit = () => {
    const n = name.trim();
    const amt = parseFloat(amount);
    if (!n) return void toast.error('Enter a budget name');
    if (!(amt > 0)) return void toast.error(`Enter a ${type === 'income' ? 'target' : 'limit'} greater than 0`);
    const group = groupId === 'none' ? null : groupId;

    if (editing && budget) {
      updateBudget(budget.id, {
        name: n,
        type,
        amount: amt,
        groupId: group,
        frequency,
        startDate,
        isRecurring: recurring ? 1 : 0,
        rollover: type === 'expense' && rollover ? 1 : 0,
        accountIds: [...accountIds],
        categoryIds: [...categoryIds],
      });
      toast.success('Budget updated', { description: n });
    } else {
      const input: NewBudgetInput = {
        name: n,
        type,
        amount: amt,
        groupId: group,
        frequency,
        startDate,
        isRecurring: recurring,
        rollover: type === 'expense' && rollover,
        accountIds: [...accountIds],
        categoryIds: [...categoryIds],
        ledgerId: activeId,
      };
      createBudget(input);
      toast.success('Budget created', { description: n });
    }
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[88vh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{editing ? 'Edit budget' : 'New budget'}</DialogTitle>
          <DialogDescription>
            {type === 'income' ? 'Track income/savings progress' : 'Track spending against a limit'} in {active.name}.
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-col gap-3">
          {/* Type toggle */}
          <div className="bg-secondary inline-flex rounded-full p-1">
            {(['expense', 'income'] as BudgetType[]).map((t) => (
              <button
                key={t}
                type="button"
                onClick={() => {
                  setType(t);
                  if (!editing) setRecurring(t === 'expense');
                }}
                className={cn(
                  'flex-1 rounded-full px-4 py-1.5 text-[13px] font-medium capitalize transition-colors',
                  type === t ? 'bg-background text-foreground shadow-sm' : 'text-muted-foreground',
                )}
              >
                {t}
              </button>
            ))}
          </div>

          <div className="flex flex-col gap-1.5">
            <Label htmlFor="b-name">Name</Label>
            <Input id="b-name" value={name} onChange={(e) => setName(e.target.value)} autoFocus placeholder={type === 'income' ? 'e.g. Salary, New car' : 'e.g. Groceries'} />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="b-amount">{type === 'income' ? 'Target' : 'Limit'}</Label>
              <Input id="b-amount" type="number" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.00" />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="b-group">Group</Label>
              <Select value={groupId} onValueChange={setGroupId}>
                <SelectTrigger id="b-group" className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">No group</SelectItem>
                  {ledgerGroups.map((g) => <SelectItem key={g.id} value={g.id}>{g.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="b-freq">Cycle</Label>
              <Select value={frequency} onValueChange={setFrequency}>
                <SelectTrigger id="b-freq" className="w-full capitalize"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {FREQUENCIES.map((f) => <SelectItem key={f} value={f} className="capitalize">{f}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="b-start">Start date</Label>
              <Input id="b-start" type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} />
            </div>
          </div>

          <label className="flex cursor-pointer items-center justify-between gap-3 text-sm">
            <span>
              Recurring
              <span className="text-muted-foreground"> · {recurring ? 'repeats each cycle' : type === 'income' ? 'one-shot goal (manual contributions)' : 'one-time'}</span>
            </span>
            <input type="checkbox" checked={recurring} onChange={(e) => setRecurring(e.target.checked)} className="size-4 cursor-pointer" />
          </label>

          {type === 'expense' && (
            <label className="flex cursor-pointer items-center justify-between gap-3 text-sm">
              <span>Roll over unused budget</span>
              <input type="checkbox" checked={rollover} onChange={(e) => setRollover(e.target.checked)} className="size-4 cursor-pointer" />
            </label>
          )}

          <ChipMultiSelect label="Categories" options={ledgerCats} selected={categoryIds} onToggle={(id) => toggle(categoryIds, setCategoryIds, id)} />
          <ChipMultiSelect label="Accounts" options={ledgerAccounts} selected={accountIds} onToggle={(id) => toggle(accountIds, setAccountIds, id)} />
        </div>

        <DialogFooter>
          <DialogClose asChild>
            <Button variant="outline">Cancel</Button>
          </DialogClose>
          <Button onClick={submit}>
            <Icon name={editing ? 'edit' : 'plus'} size={14} />
            {editing ? 'Save' : 'Create'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
