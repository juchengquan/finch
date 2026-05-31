'use client';

import Link from 'next/link';
import { useState } from 'react';
import { toast } from 'sonner';
import { Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { SearchButton } from '@/components/command-palette';
import { BudgetFormDialog } from '@/components/budget-form-dialog';
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
import type { BudgetRow, BudgetType } from '@/lib/db/queries/budgets';
import { budgetProgress } from '@/lib/select';
import { cn } from '@/lib/utils';

function BudgetCard({
  budget,
  txns,
  today,
  fmt,
}: {
  budget: BudgetRow;
  txns: Parameters<typeof budgetProgress>[1];
  today: string;
  fmt: (n: number) => string;
}) {
  const p = budgetProgress(budget, txns, today);
  const isIncome = budget.type === 'income';
  const barPct = Math.min(p.pct, 100);
  return (
    <Link href={`/budgets/${budget.id}`} className="mb-2 block">
      <div className="bg-card border-border rounded-xl border p-3.5">
        <div className="flex items-baseline justify-between gap-3">
          <div className="flex min-w-0 items-baseline gap-2">
            {budget.pendingAmount != null && (
              <span
                aria-label="Amount change pending"
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
          {budget.frequency} · {p.from.slice(5)}–{p.to.slice(5)}
        </div>
        <div className="bg-secondary relative mt-2 h-[3px] overflow-hidden rounded-sm">
          <div
            className={cn('h-full', p.over ? 'bg-destructive' : isIncome ? 'bg-success' : 'bg-primary')}
            style={{ width: `${barPct}%` }}
          />
        </div>
        <div className={cn('mt-1 text-[11px]', p.over ? 'text-destructive' : 'text-muted-foreground')}>
          {isIncome
            ? `${p.pct}% of target`
            : p.over
              ? `${fmt(-p.remaining)} over`
              : `${fmt(p.remaining)} left`}
        </div>
      </div>
    </Link>
  );
}

const EMPTY_GROUP_DRAFT = { id: null as string | null, name: '' };

export default function BudgetsPage() {
  const { fmt } = useMoney();
  const { active, activeId } = useLedger();
  const allTxns = useFinanceStore((s) => s.transactions);
  const budgets = useFinanceStore((s) => s.budgets);
  const budgetGroups = useFinanceStore((s) => s.budgetGroups);
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
    if (!name) return void toast.error('Enter a group name');
    if (groupDraft.id) {
      updateBudgetGroup(groupDraft.id, { name });
      toast.success('Group updated');
    } else {
      createBudgetGroup({ name, ledgerId: activeId });
      toast.success('Group created', { description: name });
    }
    setGroupOpen(false);
  };
  const confirmDelete = () => {
    if (!confirmDelGroup) return;
    deleteBudgetGroup(confirmDelGroup);
    toast.success('Group deleted');
    setConfirmDelGroup(null);
  };

  const addMenuItems = (
    <>
      <DropdownMenuItem onSelect={openCreate}>
        <Icon name="target" size={14} />
        New budget
      </DropdownMenuItem>
      <DropdownMenuItem onSelect={openCreateGroup}>
        <Icon name="tags" size={14} />
        New group
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
            aria-label="Add"
            className="border-border text-foreground flex size-9 cursor-pointer items-center justify-center rounded-full border"
          >
            <Icon name="plus" size={16} />
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">{addMenuItems}</DropdownMenuContent>
      </DropdownMenu>
    </div>
  );

  const renderGroup = (key: string, name: string, items: BudgetRow[], groupId: string | null) => (
    <div key={key} className="mb-5">
      <div className="mb-1.5 flex items-center justify-between px-1">
        <div className="font-serif text-lg italic">{name}</div>
        {groupId && (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <button
                type="button"
                aria-label={`Group actions: ${name}`}
                className="text-muted-foreground hover:text-foreground flex size-7 items-center justify-center rounded-md"
              >
                <Icon name="dots" size={14} />
              </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem onSelect={() => openEditGroup(groupId, name)}>
                <Icon name="edit" size={14} />
                Rename
              </DropdownMenuItem>
              <DropdownMenuItem variant="destructive" onSelect={() => setConfirmDelGroup(groupId)}>
                <Icon name="x" size={14} />
                Delete
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        )}
      </div>
      {items.length === 0 ? (
        <div className="border-border text-muted-foreground rounded-xl border border-dashed py-4 text-center text-xs">
          No {tab} budgets
        </div>
      ) : (
        <div className="md:grid md:grid-cols-2 md:gap-x-4">
          {items.map((b) => (
            <BudgetCard key={b.id} budget={b} txns={ledgerTxns} today={today} fmt={fmt} />
          ))}
        </div>
      )}
    </div>
  );

  return (
    <MobilePage header={<ScreenHeader title="Budgets" trailing={trailing} />}>
      <div className="flex items-center justify-between px-5 pt-1">
        <div className="bg-secondary mb-5 inline-flex rounded-full p-1">
          {(['expense', 'income'] as BudgetType[]).map((t) => (
            <button
              key={t}
              type="button"
              onClick={() => setTab(t)}
              className={cn(
                'rounded-full px-4 py-1.5 text-[13px] font-medium capitalize transition-colors',
                tab === t ? 'bg-background text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground',
              )}
            >
              {t}
            </button>
          ))}
        </div>
        {/* Desktop add action: the mobile ScreenHeader (and its + button) is
            md:hidden, so surface the same menu here for md+ viewports. */}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button size="sm" variant="outline" className="mb-5 hidden md:inline-flex">
              <Icon name="plus" size={14} />
              New
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">{addMenuItems}</DropdownMenuContent>
        </DropdownMenu>
      </div>

      <div className="px-5 pb-[120px]">
        {typed.length === 0 && ledgerGroups.length === 0 ? (
          <div className="text-muted-foreground rounded-xl border border-dashed py-10 text-center text-sm">
            No {tab} budgets in <span className="text-foreground font-medium">{active.name}</span> yet — use the + button.
          </div>
        ) : (
          <>
            {ledgerGroups.map((g) => renderGroup(g.id, g.name, typed.filter((b) => b.groupId === g.id), g.id))}
            {ungrouped.length > 0 && renderGroup('__ungrouped__', 'Ungrouped', ungrouped, null)}
          </>
        )}
      </div>

      <BudgetFormDialog open={formOpen} onOpenChange={setFormOpen} budget={editBudget} defaultType={tab} />

      <Dialog open={groupOpen} onOpenChange={setGroupOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{groupDraft.id ? 'Rename group' : 'New budget group'}</DialogTitle>
            <DialogDescription>Buckets budgets on this screen, like account groups.</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="bg-name">Name</Label>
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
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button onClick={saveGroup}>{groupDraft.id ? 'Save' : 'Create'}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={!!confirmDelGroup} onOpenChange={(o) => !o && setConfirmDelGroup(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete group?</DialogTitle>
            <DialogDescription>
              Budgets in this group are kept and become ungrouped. This can’t be undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button variant="destructive" onClick={confirmDelete}>
              Delete
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MobilePage>
  );
}
