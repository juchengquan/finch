'use client';

import Link from 'next/link';
import { Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { SearchButton } from '@/components/command-palette';
import { useLedger } from '@/components/ledger-provider';
import { useMoney } from '@/components/use-money';
import { useFinanceStore } from '@/lib/store';
import { MOCK } from '@/lib/data';
import { CategoryRow } from '@/components/CategoryRow';
import { periodOf, periodRange, type Frequency } from '@/lib/budgets/period';
import { cn } from '@/lib/utils';

const DEFAULT_ANCHOR = '2026-05-01';

export default function BudgetsPage() {
  const { short } = useMoney();
  const { active, activeId } = useLedger();
  const allTxns = useFinanceStore((s) => s.transactions);
  const budgetByCategory = useFinanceStore((s) => s.budgetByCategory);
  const budgetMetaByCategory = useFinanceStore((s) => s.budgetMetaByCategory);

  // Each category's "spent" is now scoped to ITS budget's current period —
  // weekly budgets show week-to-date, quarterly show quarter-to-date, and
  // unbudgeted categories fall back to month-to-date.
  const today = new Date().toISOString().slice(0, 10);
  const ledgerTxns = allTxns.filter((t) => (t.ledgerId ?? 'personal') === activeId);
  const spentOf = (categoryId: string, freq: Frequency, anchor: string) => {
    const period = periodOf(today, freq, anchor);
    const { from, to } = periodRange(period, freq);
    let total = 0;
    for (const t of ledgerTxns) {
      if (t.category !== categoryId) continue;
      if (t.pending || t.amount >= 0 || t.transferGroupId || t.isAdjustment) continue;
      if (t.date < from || t.date > to) continue;
      total += -t.amount;
    }
    return total;
  };

  const categories = MOCK.categories
    .filter((c) => ((c as { ledger?: string }).ledger ?? 'personal') === activeId)
    .map((c) => {
      const meta = budgetMetaByCategory[c.id];
      const freq: Frequency = meta?.frequency ?? 'monthly';
      const anchor = meta?.startDate ?? DEFAULT_ANCHOR;
      return {
        ...c,
        spent: spentOf(c.id, freq, anchor),
        budget: budgetByCategory[c.id] ?? c.budget,
      };
    });
  const totalSpent = categories.reduce((s, c) => s + c.spent, 0);
  const totalBudget = categories.reduce((s, c) => s + c.budget, 0);
  const pct = totalBudget ? Math.round((totalSpent / totalBudget) * 100) : 0;

  if (categories.length === 0) {
    return (
      <MobilePage>
        <ScreenHeader title="Budgets" trailing={<SearchButton />} />
        <div className="text-muted-foreground px-5 pt-16 text-center text-sm">
          No budgets in <span className="text-foreground font-medium">{active.name}</span> yet.
        </div>
      </MobilePage>
    );
  }

  return (
    <MobilePage
      header={
        <ScreenHeader
          title="Budgets"
          trailing={<SearchButton />}
        />
      }
    >
      <div className="px-5 pt-1 pb-[22px]">
        <div className="text-muted-foreground text-[10px] tracking-wider uppercase">Spent of budget</div>
        <div className="mt-1.5 flex items-baseline justify-between gap-3">
          <div className="font-serif text-4xl leading-none -tracking-[1px]">{short(totalSpent)}</div>
          <div className="text-muted-foreground text-xs">
            <span className="text-foreground font-medium">{pct}%</span> of{' '}
            <span className="font-mono">{short(totalBudget)}</span>
          </div>
        </div>
        <div className="bg-secondary relative mt-3 h-2 overflow-hidden rounded-full">
          <div
            className={cn('h-full rounded-full', pct > 100 ? 'bg-destructive' : 'bg-primary')}
            style={{ width: `${Math.min(pct, 100)}%` }}
          />
        </div>
        <div className="bg-success/10 text-success mt-2.5 inline-flex items-center gap-1.5 rounded-[10px] px-2.5 py-1 text-[11px] font-medium">
          <Icon name="check" size={12} />
          On track for May
        </div>
      </div>

      <div className="hidden gap-3 px-5 pb-4 md:grid md:grid-cols-3">
        <div className="bg-card border-border rounded-xl border p-4">
          <div className="text-muted-foreground text-[10px] tracking-wider uppercase">Spent</div>
          <div className="mt-1 font-serif text-2xl">{short(totalSpent)}</div>
        </div>
        <div className="bg-card border-border rounded-xl border p-4">
          <div className="text-muted-foreground text-[10px] tracking-wider uppercase">Remaining</div>
          <div className="mt-1 font-serif text-2xl">{short(Math.max(totalBudget - totalSpent, 0))}</div>
        </div>
        <div className="bg-card border-border rounded-xl border p-4">
          <div className="text-muted-foreground text-[10px] tracking-wider uppercase">Over budget</div>
          <div className="mt-1 font-serif text-2xl">{categories.filter((c) => c.spent > c.budget).length}</div>
        </div>
      </div>

      <div className="px-5 pb-[22px]">
        <div className="bg-card border-border rounded-xl border p-3.5">
          <div className="mb-2 flex items-baseline justify-between">
            <div className="font-serif text-lg italic">Categories</div>
            <span className="text-muted-foreground font-mono text-[10px] tracking-[0.8px]">SPENT / BUDGET</span>
          </div>
          <div className="md:grid md:grid-cols-2 md:gap-x-4">
            {categories.map((c) => (
              <Link key={c.id} href={`/budgets/${c.id}`} className="block">
                <CategoryRow category={c}/>
              </Link>
            ))}
          </div>
        </div>
      </div>
    </MobilePage>
  );
}
