'use client';

import Link from 'next/link';
import { Ring } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { useLedger } from '@/components/ledger-provider';
import { useMoney } from '@/components/use-money';
import { useFinanceStore } from '@/lib/store';
import { categorySpent } from '@/lib/derive';
import { MOCK } from '@/lib/data';
import { CategoryRow } from '@/components/CategoryRow';

export default function BudgetsPage() {
  const { short } = useMoney();
  const { active, activeId } = useLedger();
  const allTxns = useFinanceStore((s) => s.transactions);
  const ledgerTxns = allTxns.filter((t) => (t.ledgerId ?? 'personal') === activeId);

  const categories = MOCK.categories
    .filter((c) => ((c as { ledger?: string }).ledger ?? 'personal') === activeId)
    .map((c) => ({ ...c, spent: categorySpent(ledgerTxns, c.id) }));
  const totalSpent = categories.reduce((s, c) => s + c.spent, 0);
  const totalBudget = categories.reduce((s, c) => s + c.budget, 0);
  const pct = totalBudget ? Math.round((totalSpent / totalBudget) * 100) : 0;

  if (categories.length === 0) {
    return (
      <MobilePage>
        <ScreenHeader title="Budgets" trailing={<IconButton icon="search" />} />
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
          trailing={<IconButton icon="search"/>}
        />
      }
    >
      <div className="px-5 pb-[22px]">
        <PageHeader
          label="Spent of budget"
          value={<Ring value={totalSpent} max={totalBudget} size={120} stroke={10} color="var(--primary)" track="var(--secondary)">
            <div className="text-center">
              <div className="font-serif text-[28px] leading-none -tracking-[0.6px]">{pct}%</div>
              <div className="text-muted-foreground mt-0.5 text-[9px] tracking-[1px]">USED</div>
            </div>
          </Ring>}
          sublabel={<>of <span className="font-mono">{short(totalBudget)}</span></>}
          trend={{ text: 'On track for May', icon: 'check', color: 'pos' }}
        />
      </div>

      <div className="px-5 pb-[22px]">
        <div className="bg-card border-border rounded-xl border p-3.5">
          <div className="mb-2 flex items-baseline justify-between">
            <div className="font-serif text-lg italic">Categories</div>
            <span className="text-muted-foreground font-mono text-[10px] tracking-[0.8px]">SPENT / BUDGET</span>
          </div>
          {categories.map((c) => (
            <Link key={c.id} href={`/budgets/${c.id}`} className="block">
              <CategoryRow category={c}/>
            </Link>
          ))}
        </div>
      </div>
    </MobilePage>
  );
}
