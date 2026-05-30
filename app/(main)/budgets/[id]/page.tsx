'use client';

import { useState } from 'react';
import { useParams } from 'next/navigation';
import Link from 'next/link';
import { toast } from 'sonner';
import { Ring, Money, Icon, CatBar } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { acctById, catById } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { useMoney } from '@/components/use-money';
import { budgetProgress, kindOf } from '@/lib/select';
import { BudgetFormDialog } from '@/components/budget-form-dialog';
import type { BudgetRow } from '@/lib/db/queries/budgets';
import { useTransactionSheet } from '@/components/transaction-sheet';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { cn } from '@/lib/utils';

function NamedBudgetDetail({ budget }: { budget: BudgetRow }) {
  const { fmt } = useMoney();
  const allTxns = useFinanceStore((s) => s.transactions);
  const removeBudget = useFinanceStore((s) => s.removeBudget);
  const contributeBudget = useFinanceStore((s) => s.contributeBudget);
  const { openTransaction } = useTransactionSheet();
  const [editOpen, setEditOpen] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [contribOpen, setContribOpen] = useState(false);
  const [contrib, setContrib] = useState('');

  const ledgerTxns = allTxns.filter((t) => (t.ledgerId ?? 'personal') === budget.ledgerId);
  const today = ledgerTxns.reduce((m, t) => (t.date > m ? t.date : m), '') || '2026-05-30';
  const p = budgetProgress(budget, ledgerTxns, today);
  const isIncome = budget.type === 'income';
  const oneShot = isIncome && budget.isRecurring === 0;

  const accountSet = new Set(budget.accountIds);
  const categorySet = new Set(budget.categoryIds);
  // Transactions inside the cycle window that match the budget's filters.
  const matched = ledgerTxns
    .filter((t) => !t.pending && kindOf(t) !== 'transfer' && kindOf(t) !== 'adjustment')
    .filter((t) => t.date >= p.from && t.date <= p.to)
    .filter((t) => (accountSet.size ? accountSet.has(t.account) : true))
    .filter((t) => (categorySet.size ? t.category != null && categorySet.has(t.category) : true))
    .filter((t) => (isIncome ? t.amount > 0 : t.amount < 0))
    .sort((a, b) => (a.date < b.date ? 1 : -1));

  const chip = (label: string) => (
    <span key={label} className="bg-secondary text-secondary-foreground rounded-full px-2 py-0.5 text-[11px]">
      {label}
    </span>
  );

  const submitContribution = () => {
    const amt = parseFloat(contrib);
    if (!(amt > 0)) return void toast.error('Enter an amount greater than 0');
    contributeBudget(budget.id, amt);
    toast.success('Contribution added', { description: `${budget.name} · +${fmt(amt)}` });
    setContrib('');
    setContribOpen(false);
  };

  return (
    <MobilePage header={<ScreenHeader title={budget.name} back backHref="/budgets" />}>
      <div className="px-5 pb-[120px]">
        <div className="text-muted-foreground mb-5 flex items-center gap-2 text-xs md:hidden">
          <Link href="/budgets" className="text-muted-foreground">Budgets</Link>
          <Icon name="chev" size={11} />
          <span className="text-foreground">{budget.name}</span>
        </div>

        <div className="mb-6 flex items-center gap-5">
          <Ring
            value={p.used}
            max={p.base}
            size={104}
            stroke={10}
            color={p.over ? 'var(--destructive)' : isIncome ? 'var(--success)' : 'var(--primary)'}
            track="var(--secondary)"
          >
            <div className="text-center">
              <div className="font-serif text-2xl leading-none">{p.pct}%</div>
              <div className="text-muted-foreground text-[9px] tracking-wider">{isIncome ? 'SAVED' : 'USED'}</div>
            </div>
          </Ring>
          <div className="min-w-0">
            <div className="font-serif text-3xl">
              <Money value={p.used} mono={false} />
            </div>
            <div className="text-muted-foreground mt-1 text-xs">
              of <Money value={p.base} /> · <span className="capitalize">{budget.frequency}</span>
            </div>
            <div className="text-muted-foreground mt-0.5 text-[11px]">
              {p.from.replace(/-/g, '/')} – {p.to.replace(/-/g, '/')}
            </div>
            <div
              className={cn(
                'mt-2 inline-flex items-center rounded-[10px] px-2.5 py-1 text-[11px] font-medium',
                p.over ? 'bg-destructive/10 text-destructive' : 'bg-success/10 text-success',
              )}
            >
              {isIncome ? (
                <><Money value={p.remaining < 0 ? 0 : p.remaining} />&nbsp;to go</>
              ) : p.over ? (
                <><Money value={-p.remaining} />&nbsp;over</>
              ) : (
                <><Money value={p.remaining} />&nbsp;left</>
              )}
            </div>
            <div className="mt-3 flex flex-wrap items-center gap-2">
              <Button variant="outline" size="sm" onClick={() => setEditOpen(true)}>
                <Icon name="edit" size={14} />Edit
              </Button>
              {oneShot && (
                <Button variant="outline" size="sm" onClick={() => { setContrib(''); setContribOpen(true); }}>
                  <Icon name="plus" size={14} />Contribute
                </Button>
              )}
              <Button variant="ghost" size="sm" className="text-destructive hover:text-destructive" onClick={() => setConfirmDelete(true)}>
                <Icon name="x" size={14} />Delete
              </Button>
            </div>
          </div>
        </div>

        {(budget.categoryIds.length > 0 || budget.accountIds.length > 0) && (
          <div className="mb-5 flex flex-wrap gap-1.5">
            {budget.categoryIds.map((id) => chip(catById(id).name))}
            {budget.accountIds.map((id) => chip(acctById(id).name))}
          </div>
        )}

        <div className="mb-2 flex items-baseline justify-between px-1">
          <div className="font-serif text-lg italic">{isIncome ? 'Income' : 'Transactions'}</div>
          <span className="text-muted-foreground font-mono text-[10px] tracking-wider">{matched.length}</span>
        </div>
        <div className="bg-card border-border overflow-hidden rounded-xl border">
          {matched.length === 0 && (
            <div className="text-muted-foreground p-4 text-center text-sm">
              {oneShot ? 'Progress is tracked via manual contributions.' : 'No transactions in this cycle yet'}
            </div>
          )}
          {matched.map((t, i) => (
            <button
              key={t.id}
              type="button"
              onClick={() => openTransaction(t.id)}
              className={cn('hover:bg-secondary/40 flex w-full items-center gap-3 p-3.5 text-left', i && 'border-border border-t')}
            >
              <CatBar hue={catById(t.category).hue} />
              <div className="min-w-0 flex-1">
                <div className="truncate text-sm font-medium">{t.merchant}</div>
                <div className="text-muted-foreground mt-0.5 text-[11px]">
                  {t.date.replace(/-/g, '/')}{t.time ? ' ' + t.time.slice(0, 5) : ''} · {acctById(t.account).name}
                </div>
              </div>
              <Money value={t.amount} className="text-sm font-medium" />
            </button>
          ))}
        </div>
      </div>

      <BudgetFormDialog open={editOpen} onOpenChange={setEditOpen} budget={budget} />

      <Dialog open={contribOpen} onOpenChange={setContribOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Add to {budget.name}</DialogTitle>
            <DialogDescription>Record a contribution toward this goal.</DialogDescription>
          </DialogHeader>
          <Input
            type="number"
            inputMode="decimal"
            value={contrib}
            onChange={(e) => setContrib(e.target.value)}
            placeholder="0.00"
            autoFocus
            onKeyDown={(e) => e.key === 'Enter' && submitContribution()}
          />
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button onClick={submitContribution}>Add</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={confirmDelete} onOpenChange={setConfirmDelete}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete budget?</DialogTitle>
            <DialogDescription>
              {budget.name} will be permanently removed. Your transactions are unaffected.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button
              variant="destructive"
              onClick={() => {
                removeBudget(budget.id);
                toast.success('Budget deleted', { description: budget.name });
                window.history.back();
              }}
            >
              Delete
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MobilePage>
  );
}

export default function BudgetDetailPage() {
  const params = useParams();
  const id = params.id as string;
  const namedBudget = useFinanceStore((s) => s.budgets.find((b) => b.id === id));
  if (namedBudget) return <NamedBudgetDetail budget={namedBudget} />;
  return (
    <MobilePage header={<ScreenHeader title="Budget" back backHref="/budgets" />}>
      <div className="text-muted-foreground px-5 pt-16 text-center text-sm">Budget not found.</div>
    </MobilePage>
  );
}
