'use client';

import { useState } from 'react';
import { useParams } from 'next/navigation';
import Link from 'next/link';
import { toast } from 'sonner';
import { Ring, Money, Icon, CatBar } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { MOCK, acctById } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { categorySpend } from '@/lib/select';
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
  const budgetOverrides = useFinanceStore((s) => s.budgetOverrides);
  const setBudget = useFinanceStore((s) => s.setBudget);
  const { openTransaction } = useTransactionSheet();

  const catLedger = (cat as { ledger?: string }).ledger ?? 'personal';
  const ledgerTxns = allTxns.filter((t) => (t.ledgerId ?? 'personal') === catLedger);
  const txns = ledgerTxns.filter((t) => t.category === cat.id);
  const budget = budgetOverrides[cat.id] ?? cat.budget;

  // Confirmed expense for this category, from the projected store state.
  const spent = categorySpend(allTxns, catLedger)[cat.id] ?? 0;
  const pct = Math.round((spent / budget) * 100);
  const over = spent > budget;
  const remaining = budget - spent;

  const [draft, setDraft] = useState(String(budget));

  const saveBudget = () => {
    const value = parseFloat(draft);
    if (value > 0) {
      setBudget(cat.id, value);
      toast.success('Budget updated', { description: `${cat.name} · ${value.toLocaleString()}` });
    }
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
            <div className="mt-3">
              <Dialog onOpenChange={(open) => open && setDraft(String(budget))}>
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
                  {t.date.slice(5).replace('-', '/')} · {acctById(t.account).name}
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
