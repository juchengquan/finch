'use client';

import { Donut, Money } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { MOCK } from '@/lib/data';
import { useLedger } from '@/components/ledger-provider';
import { useFinanceStore } from '@/lib/store';
import { categorySpend } from '@/lib/select';
import { toast } from 'sonner';

export default function ReportsPage() {
  const { activeId } = useLedger();
  const allTxns = useFinanceStore((s) => s.transactions);

  // Confirmed expense per category, scoped to the active ledger.
  const spentById = categorySpend(allTxns, activeId);

  const cats = MOCK.categories
    .filter((c) => ((c as { ledger?: string }).ledger ?? 'personal') === activeId)
    .map((c) => ({ ...c, spent: spentById[c.id] ?? 0 }))
    .sort((a, b) => b.spent - a.spent);
  const total = cats.reduce((s, c) => s + c.spent, 0);
  const slices = cats.map((c) => ({ value: c.spent, color: `oklch(0.65 0.13 ${c.hue})` }));

  return (
    <MobilePage
      header={<ScreenHeader title="Reports" trailing={<IconButton icon="doc" aria-label="Export" />} />}
    >
      <div className="px-5 pb-[22px]">
        <PageHeader
          label="Spending · May"
          value={<Money value={total} mono={false} />}
          sublabel={`across ${cats.length} categories`}
        />
      </div>

      <div className="px-5 pb-[120px]">
        <div className="bg-card border-border flex flex-col items-center rounded-xl border p-5">
          <div className="relative flex items-center justify-center">
            <Donut slices={slices} size={168} stroke={26} />
            <div className="absolute text-center">
              <div className="font-serif text-2xl leading-none">
                <Money value={total} mono={false} />
              </div>
              <div className="text-muted-foreground mt-1 text-[10px] tracking-wider uppercase">Spent</div>
            </div>
          </div>
        </div>

        <div className="mt-4">
          {cats.map((c) => {
            const pct = total ? Math.round((c.spent / total) * 100) : 0;
            return (
              <div
                key={c.id}
                className="border-border flex items-center gap-3 border-t py-3 first:border-t-0"
              >
                <span
                  className="size-2.5 shrink-0 rounded-full"
                  style={{ background: `oklch(0.65 0.13 ${c.hue})` }}
                />
                <div className="flex-1 truncate text-sm">{c.name}</div>
                <div className="text-muted-foreground w-9 text-right font-mono text-xs">{pct}%</div>
                <Money value={c.spent} className="w-20 text-right text-sm" />
              </div>
            );
          })}
        </div>

        <button
          type="button"
          onClick={() => toast.success('Export started', { description: 'May report · CSV' })}
          className="bg-secondary text-secondary-foreground mt-4 flex h-11 w-full items-center justify-center gap-2 rounded-xl text-sm font-medium"
        >
          Export CSV
        </button>
      </div>
    </MobilePage>
  );
}
