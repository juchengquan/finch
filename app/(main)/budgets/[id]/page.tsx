'use client';

import { useState } from 'react';
import { useParams } from 'next/navigation';
import Link from 'next/link';
import { toast } from 'sonner';
import { Ring, Money, Icon, CatBar } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { MOCK, acctById } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { categorySpend, currentMonth } from '@/lib/select';
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
  DialogTrigger,
} from '@/components/ui/dialog';
import { cn } from '@/lib/utils';

export default function BudgetDetailPage() {
  const params = useParams();
  const id = params.id as string;
  const cat = MOCK.categories.find((c) => c.id === id) ?? MOCK.categories[0];
  const allTxns = useFinanceStore((s) => s.transactions);
  const budgetByCategory = useFinanceStore((s) => s.budgetByCategory);
  const budgetRolloverByCategory = useFinanceStore((s) => s.budgetRolloverByCategory);
  const setBudget = useFinanceStore((s) => s.setBudget);
  const deleteBudget = useFinanceStore((s) => s.deleteBudget);
  const setBudgetRollover = useFinanceStore((s) => s.setBudgetRollover);
  const { openTransaction } = useTransactionSheet();

  const catLedger = (cat as { ledger?: string }).ledger ?? 'personal';
  const ledgerTxns = allTxns.filter((t) => (t.ledgerId ?? 'personal') === catLedger);
  const txns = ledgerTxns.filter((t) => t.category === cat.id);
  const hasBudget = budgetByCategory[cat.id] != null;
  const baseAmount = budgetByCategory[cat.id] ?? cat.budget;
  const rolloverInfo = budgetRolloverByCategory[cat.id];
  const carryForward = rolloverInfo?.carryForward ?? 0;
  // budgetProgress already adds carry_forward into the period total; mirror that
  // here so the ring + remaining match what the report screens show.
  const budget = baseAmount + carryForward;

  // Confirmed expense for this category, from the projected store state.
  const spent = categorySpend(allTxns, catLedger, currentMonth(allTxns, catLedger))[cat.id] ?? 0;
  const pct = Math.round((spent / budget) * 100);
  const over = spent > budget;
  const remaining = budget - spent;

  const [draft, setDraft] = useState(String(baseAmount));
  const [rolloverDraft, setRolloverDraft] = useState({
    rollover: rolloverInfo?.rollover ?? false,
    rolloverLimit: rolloverInfo?.rolloverLimit == null ? '' : String(rolloverInfo.rolloverLimit),
  });

  const saveBudget = () => {
    const value = parseFloat(draft);
    if (value > 0) {
      setBudget(cat.id, value);
      toast.success('Budget updated', { description: `${cat.name} · ${value.toLocaleString()}` });
    }
  };

  const saveRollover = () => {
    if (!hasBudget) {
      toast.error('Set a budget for this category first');
      return;
    }
    const trimmed = rolloverDraft.rolloverLimit.trim();
    const limit = trimmed === '' ? null : Number(trimmed);
    if (limit !== null && (!Number.isFinite(limit) || limit < 0)) {
      toast.error('Limit must be a non-negative number');
      return;
    }
    setBudgetRollover(cat.id, { rollover: rolloverDraft.rollover, rolloverLimit: limit });
    toast.success(rolloverDraft.rollover ? 'Rollover enabled' : 'Rollover disabled');
  };

  const removeBudget = () => {
    deleteBudget(cat.id);
    toast.success('Budget removed', { description: cat.name });
  };

  return (
    <MobilePage header={<ScreenHeader title={cat.name} back backHref="/budgets" />}>
      <div className="px-5 pb-[120px]">
        <div className="text-muted-foreground mb-5 flex items-center gap-2 text-xs md:hidden">
          <Link href="/budgets" className="text-muted-foreground">
            Budgets
          </Link>
          <Icon name="chev" size={11} />
          <span className="text-foreground">{cat.name}</span>
        </div>

        <div className="mb-6 flex items-center gap-5">
          <Ring
            value={spent}
            max={budget}
            size={104}
            stroke={10}
            color={over ? 'var(--destructive)' : 'var(--primary)'}
            track="var(--secondary)"
          >
            <div className="text-center">
              <div className="font-serif text-2xl leading-none">{pct}%</div>
              <div className="text-muted-foreground text-[9px] tracking-wider">USED</div>
            </div>
          </Ring>
          <div>
            <div className="font-serif text-3xl">
              <Money value={spent} mono={false} />
            </div>
            <div className="text-muted-foreground mt-1 text-xs">
              of <Money value={budget} />
              {carryForward > 0 && (
                <>
                  {' '}<span className="text-success">(+<Money value={carryForward} /> rolled over)</span>
                </>
              )}
            </div>
            <div
              className={cn(
                'mt-2 inline-flex items-center rounded-[10px] px-2.5 py-1 text-[11px] font-medium',
                over ? 'bg-destructive/10 text-destructive' : 'bg-success/10 text-success',
              )}
            >
              {over ? (
                <>
                  <Money value={-remaining} />
                  &nbsp;over
                </>
              ) : (
                <>
                  <Money value={remaining} />
                  &nbsp;left
                </>
              )}
            </div>
            <div className="mt-3 flex items-center gap-2">
              <Dialog onOpenChange={(open) => open && setDraft(String(baseAmount))}>
                <DialogTrigger asChild>
                  <Button variant="outline" size="sm">
                    <Icon name="edit" size={14} />
                    Edit budget
                  </Button>
                </DialogTrigger>
                <DialogContent>
                  <DialogHeader>
                    <DialogTitle>Edit budget</DialogTitle>
                    <DialogDescription>{cat.name} · monthly limit</DialogDescription>
                  </DialogHeader>
                  <div className="flex items-center gap-2">
                    <span className="text-muted-foreground font-serif text-xl">$</span>
                    <Input
                      type="number"
                      inputMode="decimal"
                      value={draft}
                      onChange={(e) => setDraft(e.target.value)}
                      autoFocus
                    />
                  </div>
                  <DialogFooter>
                    <DialogClose asChild>
                      <Button variant="outline">Cancel</Button>
                    </DialogClose>
                    <DialogClose asChild>
                      <Button onClick={saveBudget}>Save</Button>
                    </DialogClose>
                  </DialogFooter>
                </DialogContent>
              </Dialog>
              {hasBudget && (
                <Dialog
                  onOpenChange={(open) =>
                    open &&
                    setRolloverDraft({
                      rollover: rolloverInfo?.rollover ?? false,
                      rolloverLimit: rolloverInfo?.rolloverLimit == null ? '' : String(rolloverInfo.rolloverLimit),
                    })
                  }
                >
                  <DialogTrigger asChild>
                    <Button variant="outline" size="sm">
                      <Icon name="sync" size={14} />
                      Rollover
                    </Button>
                  </DialogTrigger>
                  <DialogContent>
                    <DialogHeader>
                      <DialogTitle>Budget rollover</DialogTitle>
                      <DialogDescription>
                        When on, unused budget carries forward. The current carry-forward (<Money value={carryForward} />)
                        is set manually for now.
                      </DialogDescription>
                    </DialogHeader>
                    <div className="flex flex-col gap-3">
                      <label className="flex cursor-pointer items-center justify-between gap-3 text-sm">
                        <span>Roll over unused budget</span>
                        <input
                          type="checkbox"
                          checked={rolloverDraft.rollover}
                          onChange={(e) => setRolloverDraft((d) => ({ ...d, rollover: e.target.checked }))}
                          className="size-4 cursor-pointer"
                        />
                      </label>
                      <div className="flex flex-col gap-1.5">
                        <label htmlFor="rollover-limit" className="text-muted-foreground text-xs">
                          Cap (leave blank for uncapped)
                        </label>
                        <div className="flex items-center gap-2">
                          <span className="text-muted-foreground font-serif text-xl">$</span>
                          <Input
                            id="rollover-limit"
                            type="number"
                            inputMode="decimal"
                            min="0"
                            placeholder="No cap"
                            value={rolloverDraft.rolloverLimit}
                            onChange={(e) => setRolloverDraft((d) => ({ ...d, rolloverLimit: e.target.value }))}
                            disabled={!rolloverDraft.rollover}
                          />
                        </div>
                      </div>
                    </div>
                    <DialogFooter>
                      <DialogClose asChild>
                        <Button variant="outline">Cancel</Button>
                      </DialogClose>
                      <DialogClose asChild>
                        <Button onClick={saveRollover}>Save</Button>
                      </DialogClose>
                    </DialogFooter>
                  </DialogContent>
                </Dialog>
              )}
              {hasBudget && (
                <Button variant="ghost" size="sm" className="text-destructive hover:text-destructive" onClick={removeBudget}>
                  <Icon name="trash" size={14} />
                  Remove
                </Button>
              )}
            </div>
          </div>
        </div>

        <div className="mb-2 flex items-baseline justify-between px-1">
          <div className="font-serif text-lg italic">Transactions</div>
          <span className="text-muted-foreground font-mono text-[10px] tracking-wider">{txns.length}</span>
        </div>
        <div className="bg-card border-border overflow-hidden rounded-xl border">
          {txns.length === 0 && (
            <div className="text-muted-foreground p-4 text-center text-sm">No transactions yet</div>
          )}
          {txns.map((t, i) => (
            <button
              key={t.id}
              type="button"
              onClick={() => openTransaction(t.id)}
              className={cn('hover:bg-secondary/40 flex w-full items-center gap-3 p-3.5 text-left', i && 'border-border border-t')}
            >
              <CatBar hue={cat.hue} />
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
    </MobilePage>
  );
}
