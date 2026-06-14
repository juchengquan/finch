'use client';

import Link from 'next/link';
import { useState } from 'react';
import { toast } from 'sonner';
import { useTranslations } from 'next-intl';
import { Dots, Edit, Plus, Tags, Target, X } from '@/components/icons';
import { MobilePage } from '@/components/mobile-page';
import { ScreenHeader } from '@/components/ui/screen-header';
import { SearchButton } from '@/components/command-palette';
import { BudgetFormDialog } from '@/components/budget-form-dialog';
import { EmptyState } from '@/components/empty-state';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useLedger } from '@/components/ledger-provider';
import { useMoney } from '@/components/use-money';
import { useFinanceStore } from '@/lib/store';
import type { BudgetRow, BudgetType } from '@/lib/db/domain/budgets/queries';
import { budgetProgress } from '@/lib/select';
import { cn } from '@/lib/utils';

function BudgetCard({
  budget,
  txns,
  today,
  fmt,
  categories,
}: {
  budget: BudgetRow;
  txns: Parameters<typeof budgetProgress>[1];
  today: string;
  fmt: (n: number) => string;
  categories: Parameters<typeof budgetProgress>[3];
}) {
  const t = useTranslations('budgets.card');
  const p = budgetProgress(budget, txns, today, categories);
  const isIncome = budget.type === 'income';
  const barPct = Math.min(p.pct, 100);
  // Ported from iOS: 3-color banding for expense budgets (green < 70, amber
  // 70–90, red > 90 / over) instead of the 2-state primary/destructive bar.
  const barColor = isIncome
    ? 'bg-success'
    : p.over || p.pct > 90
      ? 'bg-destructive'
      : p.pct >= 70
        ? 'bg-warning'
        : 'bg-primary';
  // Ported from iOS: whole days left in the cycle (UTC, floored at 0).
  const daysLeft = Math.max(
    0,
    Math.ceil((Date.parse(`${p.to}T00:00:00Z`) - Date.parse(`${today.slice(0, 10)}T00:00:00Z`)) / 86_400_000),
  );
  return (
    <Link href={`/budgets/${budget.id}`} className="mb-2 block">
      <div className="bg-card border-border rounded-xl border p-3.5">
        <div className="flex items-baseline justify-between gap-3">
          <div className="flex min-w-0 items-baseline gap-2">
            {budget.pendingAmount != null && (
              <span
                aria-label={t('pendingAria')}
                className="bg-warning size-1.5 shrink-0 self-center rounded-full"
              />
            )}
            <div className="truncate text-sm font-medium">{budget.name}</div>
          </div>
          <div className={cn('shrink-0 font-mono text-[11px]', p.over ? 'text-destructive' : 'text-foreground')}>
            {fmt(p.used)} / {fmt(p.base)}
          </div>
        </div>
        <div className="text-muted-foreground mt-0.5 text-[10px] capitalize">
          {budget.frequency} · {p.from.slice(5)}–{p.to.slice(5)} · {t('daysLeft', { days: daysLeft })}
        </div>
        <div className="bg-secondary relative mt-2 h-[3px] overflow-hidden rounded-sm">
          <div className={cn('h-full', barColor)} style={{ width: `${barPct}%` }} />
        </div>
        <div className={cn('mt-1 text-[11px]', p.over ? 'text-destructive' : 'text-muted-foreground')}>
          {isIncome
            ? t('pctOfTarget', { pct: p.pct })
            : p.over
              ? t('over', { amount: fmt(-p.remaining) })
              : t('left', { amount: fmt(p.remaining) })}
        </div>
      </div>
    </Link>
  );
}

const EMPTY_GROUP_DRAFT = { id: null as string | null, name: '' };

export default function BudgetsPage() {
  const { fmt } = useMoney();
  const { active, activeId } = useLedger();
  const t = useTranslations('budgets');
  const tCommon = useTranslations('common');
  const allTxns = useFinanceStore((s) => s.transactions);
  const budgets = useFinanceStore((s) => s.budgets);
  const budgetGroups = useFinanceStore((s) => s.budgetGroups);
  const allCategories = useFinanceStore((s) => s.categories);
  const createBudgetGroup = useFinanceStore((s) => s.createBudgetGroup);
  const updateBudgetGroup = useFinanceStore((s) => s.updateBudgetGroup);
  const deleteBudgetGroup = useFinanceStore((s) => s.deleteBudgetGroup);

  const [tab, setTab] = useState<BudgetType>('expense');
  const [formOpen, setFormOpen] = useState(false);
  const [editBudget, setEditBudget] = useState<BudgetRow | undefined>(undefined);
  const [groupOpen, setGroupOpen] = useState(false);
  const [groupDraft, setGroupDraft] = useState(EMPTY_GROUP_DRAFT);
  const [confirmDelGroup, setConfirmDelGroup] = useState<string | null>(null);

  const ledgerTxns = allTxns.filter((t) => (t.ledgerId ?? 'personal') === activeId);
  // Use the latest transaction date as "today" so cycle windows line up with the
  // seed/demo data deterministically (no Date() → no hydration mismatch).
  const today = ledgerTxns.reduce((m, t) => (t.date > m ? t.date : m), '') || '2026-05-30';

  const ledgerGroups = budgetGroups.filter((g) => g.ledgerId === activeId);
  const typed = budgets.filter((b) => b.ledgerId === activeId && b.type === tab);
  const ungrouped = typed.filter((b) => !b.groupId || !ledgerGroups.some((g) => g.id === b.groupId));

  const openCreate = () => {
    setEditBudget(undefined);
    setFormOpen(true);
  };
  const openCreateGroup = () => {
    setGroupDraft(EMPTY_GROUP_DRAFT);
    setGroupOpen(true);
  };
  const openEditGroup = (id: string, name: string) => {
    setGroupDraft({ id, name });
    setGroupOpen(true);
  };
  const saveGroup = () => {
    const name = groupDraft.name.trim();
    if (!name) return void toast.error(t('groupDialog.nameRequired'));
    if (groupDraft.id) {
      updateBudgetGroup(groupDraft.id, { name });
      toast.success(t('groupDialog.updatedToast'));
    } else {
      createBudgetGroup({ name, ledgerId: activeId });
      toast.success(t('groupDialog.createdToast'), { description: name });
    }
    setGroupOpen(false);
  };
  const confirmDelete = () => {
    if (!confirmDelGroup) return;
    deleteBudgetGroup(confirmDelGroup);
    toast.success(t('deleteGroupDialog.deletedToast'));
    setConfirmDelGroup(null);
  };

  const addMenuItems = (
    <>
      <DropdownMenuItem onSelect={openCreate}>
        <Target size={14} />
        {t('menu.newBudget')}
      </DropdownMenuItem>
      <DropdownMenuItem onSelect={openCreateGroup}>
        <Tags size={14} />
        {t('menu.newGroup')}
      </DropdownMenuItem>
    </>
  );

  const trailing = (
    <div className="flex items-center gap-1">
      <SearchButton />
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            aria-label={t('addAria')}
            className="border-border text-foreground flex size-9 cursor-pointer items-center justify-center rounded-full border"
          >
            <Plus size={16} />
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">{addMenuItems}</DropdownMenuContent>
      </DropdownMenu>
    </div>
  );

  const tabLabel = t(`tabs.${tab}`);

  const renderGroup = (key: string, name: string, items: BudgetRow[], groupId: string | null) => (
    <div key={key} className="mb-5">
      <div className="mb-1.5 flex items-center justify-between px-1">
        <div className="font-serif text-lg italic">{name}</div>
        {groupId && (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <button
                type="button"
                aria-label={t('groupActionsAria', { name })}
                className="text-muted-foreground hover:text-foreground flex size-7 items-center justify-center rounded-md"
              >
                <Dots size={14} />
              </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem onSelect={() => openEditGroup(groupId, name)}>
                <Edit size={14} />
                {t('groupActions.rename')}
              </DropdownMenuItem>
              <DropdownMenuItem variant="destructive" onSelect={() => setConfirmDelGroup(groupId)}>
                <X size={14} />
                {t('groupActions.delete')}
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        )}
      </div>
      {items.length === 0 ? (
        <EmptyState variant="card" size="sm" title={t('emptyGroup', { type: tabLabel })} />
      ) : (
        <div className="md:grid md:grid-cols-2 md:gap-x-4">
          {items.map((b) => (
            <BudgetCard key={b.id} budget={b} txns={ledgerTxns} today={today} fmt={fmt} categories={allCategories} />
          ))}
        </div>
      )}
    </div>
  );

  return (
    <MobilePage header={<ScreenHeader title={t('title')} trailing={trailing} />}>
      <div className="flex items-center justify-between px-5 pt-1">
        <div className="bg-secondary mb-5 inline-flex rounded-full p-1">
          {(['expense', 'income'] as BudgetType[]).map((tv) => (
            <button
              key={tv}
              type="button"
              onClick={() => setTab(tv)}
              className={cn(
                'rounded-full px-4 py-1.5 text-[13px] font-medium transition-colors',
                tab === tv ? 'bg-background text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground',
              )}
            >
              {t(`tabs.${tv}`)}
            </button>
          ))}
        </div>
        {/* Desktop add action: the mobile ScreenHeader (and its + button) is
            md:hidden, so surface the same menu here for md+ viewports. */}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button size="sm" variant="outline" className="mb-5 hidden md:inline-flex">
              <Plus size={14} />
              {t('newButton')}
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">{addMenuItems}</DropdownMenuContent>
        </DropdownMenu>
      </div>

      <div className="px-5 pb-[120px]">
        {typed.length === 0 && ledgerGroups.length === 0 ? (
          <EmptyState
            icon="target"
            title={t.rich('empty.title', {
              type: tabLabel,
              ledger: () => <span className="text-foreground font-medium">{active.name}</span>,
            })}
            description={t('empty.description')}
          />
        ) : (
          <>
            {ledgerGroups.map((g) => renderGroup(g.id, g.name, typed.filter((b) => b.groupId === g.id), g.id))}
            {ungrouped.length > 0 && renderGroup('__ungrouped__', t('ungroupedLabel'), ungrouped, null)}
          </>
        )}
      </div>

      <BudgetFormDialog open={formOpen} onOpenChange={setFormOpen} budget={editBudget} defaultType={tab} />

      <Dialog open={groupOpen} onOpenChange={setGroupOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{groupDraft.id ? t('groupDialog.renameTitle') : t('groupDialog.newTitle')}</DialogTitle>
            <DialogDescription>{t('groupDialog.description')}</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="bg-name">{t('groupDialog.name')}</Label>
            <Input
              id="bg-name"
              value={groupDraft.name}
              onChange={(e) => setGroupDraft((d) => ({ ...d, name: e.target.value }))}
              onKeyDown={(e) => e.key === 'Enter' && saveGroup()}
              autoFocus
            />
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">{tCommon('cancel')}</Button>
            </DialogClose>
            <Button onClick={saveGroup}>{groupDraft.id ? tCommon('save') : tCommon('create')}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={!!confirmDelGroup} onOpenChange={(o) => !o && setConfirmDelGroup(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t('deleteGroupDialog.title')}</DialogTitle>
            <DialogDescription>{t('deleteGroupDialog.description')}</DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">{tCommon('cancel')}</Button>
            </DialogClose>
            <Button variant="destructive" onClick={confirmDelete}>
              {tCommon('delete')}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MobilePage>
  );
}
