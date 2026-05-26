'use client';

import Link from 'next/link';
import { Ring } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { useCurrency } from '@/components/currency-provider';
import { MOCK, fmtMoneyShort } from '@/lib/data';
import { CategoryRow } from '@/components/CategoryRow';

export default function BudgetsPage() {
  const { currency } = useCurrency();
  const totalSpent = MOCK.categories.reduce((s, c) => s + c.spent, 0);
  const totalBudget = MOCK.categories.reduce((s, c) => s + c.budget, 0);
  const pct = Math.round((totalSpent / totalBudget) * 100);

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
          sublabel={<>of <span className="font-mono">{fmtMoneyShort(totalBudget, currency)}</span></>}
          trend={{ text: 'On track for May', icon: 'check', color: 'pos' }}
        />
      </div>

      <div className="px-5 pb-[22px]">
        <div className="bg-card border-border rounded-xl border p-3.5">
          <div className="mb-2 flex items-baseline justify-between">
            <div className="font-serif text-lg italic">Categories</div>
            <span className="text-muted-foreground font-mono text-[10px] tracking-[0.8px]">SPENT / BUDGET</span>
          </div>
          {MOCK.categories.map((c) => (
            <Link key={c.id} href={`/budgets/${c.id}`} className="block">
              <CategoryRow category={c}/>
            </Link>
          ))}
        </div>
      </div>
    </MobilePage>
  );
}
