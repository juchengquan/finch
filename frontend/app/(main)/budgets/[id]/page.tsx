'use client';

import { useState } from 'react';
import { useParams } from 'next/navigation';
import Link from 'next/link';
import { toast } from 'sonner';
import { useTranslations } from 'next-intl';
import { useAppLocale } from '@/components/i18n-provider';
import { CatBar } from '@/components/ui/cat-bar';
import { Money, Ring } from '@/components/primitives';
import { Chev, Clock, Edit, Plus, X } from '@/components/icons';
import { RefundBadge } from '@/components/ui/refund-badge';
import { MobilePage } from '@/components/MobileComponents';
import { ScreenHeader } from '@/components/ui/screen-header';
import { acctById, catById } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { useMoney } from '@/components/use-money';
import { budgetProgress, kindOf } from '@/lib/select';
import { BudgetFormDialog } from '@/components/budget-form-dialog';
import { periodLabel, nextPeriod, type Frequency } from '@/lib/budgets/period';
import type { BudgetRow } from '@/lib/db/domain/budgets/queries';
import { useTransactionDialog } from '@/components/transaction-dialog';
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
  const t = useTranslations('budgets.detail');
  const tNav = useTranslations('nav');
  const tCommon = useTranslations('common');
  const { locale } = useAppLocale();
  const allTxns = useFinanceStore((s) => s.transactions);
  const allCategories = useFinanceStore((s) => s.categories);
  const removeBudget = useFinanceStore((s) => s.removeBudget);
  const contributeBudget = useFinanceStore((s) => s.contributeBudget);
  const { openTransaction } = useTransactionDialog();
  const [editOpen, setEditOpen] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [contribOpen, setContribOpen] = useState(false);
  const [contrib, setContrib] = useState('');

  const ledgerTxns = allTxns.filter((tx) => (tx.ledgerId ?? 'personal') === budget.ledgerId);
  const today = ledgerTxns.reduce((m, tx) => (tx.date > m ? tx.date : m), '') || '2026-05-30';
  const p = budgetProgress(budget, ledgerTxns, today, allCategories);
  const isIncome = budget.type === 'income';
  const oneShot = isIncome && budget.isRecurring === 0;

  const accountSet = new Set(budget.accountIds);
  const categorySet = new Set(budget.categoryIds);
  // Transactions inside the cycle window that match the budget's filters.
  const matched = ledgerTxns
    .filter((tx) => !tx.pending && kindOf(tx) !== 'transfer' && kindOf(tx) !== 'adjustment')
    .filter((tx) => tx.date >= p.from && tx.date <= p.to)
    .filter((tx) => (accountSet.size ? accountSet.has(tx.account) : true))
    .filter((tx) => (categorySet.size ? tx.category != null && categorySet.has(tx.category) : true))
    .filter((tx) => (isIncome ? tx.amount > 0 : tx.amount < 0))
    .sort((a, b) => (a.date < b.date ? 1 : -1));

  const chip = (label: string) => (
    <span key={label} className="bg-secondary text-secondary-foreground rounded-full px-2 py-0.5 text-[11px]">
      {label}
    </span>
  );

  const submitContribution = () => {
    const amt = parseFloat(contrib);
    if (!(amt > 0)) return void toast.error(t('contributeDialog.amountError'));
    contributeBudget(budget.id, amt);
    toast.success(t('contributeDialog.addedToast'), {
      description: t('contributeDialog.addedDescription', { name: budget.name, amount: fmt(amt) }),
    });
    setContrib('');
    setContribOpen(false);
  };

  return (
    <MobilePage header={<ScreenHeader title={budget.name} back backHref="/budgets" />}>
      <div className="px-5 pb-[120px]">
        <div className="text-muted-foreground mb-5 flex items-center gap-2 text-xs md:hidden">
          <Link href="/budgets" className="text-muted-foreground">{tNav('budgets')}</Link>
          <Chev size={11} />
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
              <div className="text-muted-foreground text-[9px] tracking-wider">{isIncome ? t('saved') : t('used')}</div>
            </div>
          </Ring>
          <div className="min-w-0">
            <div className="font-serif text-3xl">
              <Money value={p.used} mono={false} />
            </div>
            <div className="text-muted-foreground mt-1 text-xs">
              {t('of')} <Money value={p.base} /> · <span className="capitalize">{budget.frequency}</span>
              {budget.carryForward > 0 && (
                <span className="text-success">
                  {' '}{t('carried', { amount: fmt(budget.carryForward) })}
                </span>
              )}
            </div>
            <div className="text-muted-foreground mt-0.5 text-[11px]">
              {periodLabel(p.from, budget.frequency as Frequency, budget.startDate, locale)} · {p.from.replace(/-/g, '/')}–{p.to.replace(/-/g, '/')}
            </div>
            {budget.pendingAmount != null && (
              <div className="text-warning bg-warning/10 mt-1.5 inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-[11px]">
                <Clock size={11} />
                {t('pendingFromNext', {
                  amount: fmt(budget.pendingAmount),
                  period: periodLabel(
                    nextPeriod(p.from, budget.frequency as Frequency, budget.startDate),
                    budget.frequency as Frequency,
                    budget.startDate,
                    locale,
                  ),
                })}
              </div>
            )}
            <div
              className={cn(
                'mt-2 inline-flex items-center rounded-[10px] px-2.5 py-1 text-[11px] font-medium',
                p.over ? 'bg-destructive/10 text-destructive' : 'bg-success/10 text-success',
              )}
            >
              {isIncome
                ? t('toGo', { amount: fmt(p.remaining < 0 ? 0 : p.remaining) })
                : p.over
                  ? t('over', { amount: fmt(-p.remaining) })
                  : t('left', { amount: fmt(p.remaining) })}
            </div>
            <div className="mt-3 flex flex-wrap items-center gap-2">
              <Button variant="outline" size="sm" onClick={() => setEditOpen(true)}>
                <Edit size={14} />{t('editButton')}
              </Button>
              {oneShot && (
                <Button variant="outline" size="sm" onClick={() => { setContrib(''); setContribOpen(true); }}>
                  <Plus size={14} />{t('contributeButton')}
                </Button>
              )}
              <Button variant="ghost" size="sm" className="text-destructive hover:text-destructive" onClick={() => setConfirmDelete(true)}>
                <X size={14} />{t('deleteButton')}
              </Button>
            </div>
          </div>
        </div>

        {(budget.categoryIds.length > 0 || budget.accountIds.length > 0) && (
          <div className="mb-5 flex flex-wrap gap-1.5">
            {budget.categoryIds.map((cid) => chip(catById(cid).name))}
            {budget.accountIds.map((aid) => chip(acctById(aid).name))}
          </div>
        )}

        <div className="mb-2 flex items-baseline justify-between px-1">
          <div className="font-serif text-lg italic">{isIncome ? t('incomeTitle') : t('transactionsTitle')}</div>
          <span className="text-muted-foreground font-mono text-[10px] tracking-wider">{matched.length}</span>
        </div>
        <div className="bg-card border-border overflow-hidden rounded-xl border">
          {matched.length === 0 && (
            <div className="text-muted-foreground p-4 text-center text-sm">
              {oneShot ? t('manualOnly') : t('noneInCycle')}
            </div>
          )}
          {matched.map((tx, i) => (
            <button
              key={tx.id}
              type="button"
              onClick={() => openTransaction(tx.id)}
              className={cn('hover:bg-secondary/40 flex w-full items-center gap-3 p-3.5 text-left', i && 'border-border border-t')}
            >
              <CatBar color={catById(tx.category).color} />
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-1.5">
                  <span className="truncate text-sm font-medium">{tx.merchant}</span>
                  {tx.kind === 'refund' && <RefundBadge />}
                </div>
                <div className="text-muted-foreground mt-0.5 text-[11px]">
                  {tx.date.replace(/-/g, '/')}{tx.time ? ' ' + tx.time.slice(0, 5) : ''} · {acctById(tx.account).name}
                </div>
              </div>
              <Money value={tx.amount} className="text-sm font-medium" />
            </button>
          ))}
        </div>
      </div>

      <BudgetFormDialog open={editOpen} onOpenChange={setEditOpen} budget={budget} />

      <Dialog open={contribOpen} onOpenChange={setContribOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t('contributeDialog.title', { name: budget.name })}</DialogTitle>
            <DialogDescription>{t('contributeDialog.description')}</DialogDescription>
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
              <Button variant="outline">{tCommon('cancel')}</Button>
            </DialogClose>
            <Button onClick={submitContribution}>{t('contributeDialog.submit')}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={confirmDelete} onOpenChange={setConfirmDelete}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t('deleteDialog.title')}</DialogTitle>
            <DialogDescription>{t('deleteDialog.description', { name: budget.name })}</DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">{tCommon('cancel')}</Button>
            </DialogClose>
            <Button
              variant="destructive"
              onClick={() => {
                removeBudget(budget.id);
                toast.success(t('deleteDialog.deletedToast'), { description: budget.name });
                window.history.back();
              }}
            >
              {tCommon('delete')}
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
  const t = useTranslations('budgets.detail');
  if (namedBudget) return <NamedBudgetDetail budget={namedBudget} />;
  return (
    <MobilePage header={<ScreenHeader title={t('fallbackTitle')} back backHref="/budgets" />}>
      <div className="text-muted-foreground px-5 pt-16 text-center text-sm">{t('notFound')}</div>
    </MobilePage>
  );
}
