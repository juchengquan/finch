'use client';

import { useMemo, useState } from 'react';
import { Money } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { MOCK } from '@/lib/data';
import { useLedger } from '@/components/ledger-provider';
import { useFinanceStore } from '@/lib/store';
import { categorySpend, currentMonth } from '@/lib/select';
import { toast } from 'sonner';

const MONTH_LABELS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const formatMonth = (ym: string) => {
  if (!ym) return '';
  const [y, m] = ym.split('-').map(Number);
  return `${MONTH_LABELS[m - 1]} ${y}`;
};

export default function ReportsPage() {
  const { activeId } = useLedger();
  const allTxns = useFinanceStore((s) => s.transactions);

  // YYYY-MM keys for months with at least one transaction in the active ledger,
  // newest first. The picker is restricted to months that actually have data.
  const months = useMemo(() => {
    const set = new Set<string>();
    for (const t of allTxns) {
      if (((t as { ledgerId?: string }).ledgerId ?? 'personal') === activeId) {
        set.add(t.date.slice(0, 7));
      }
    }
    return Array.from(set).sort().reverse();
  }, [allTxns, activeId]);

  const [pickedMonth, setPickedMonth] = useState<string>(() => currentMonth(allTxns, activeId));
  // The user's pick is the source of truth; if it falls out of the available
  // months (e.g. after a ledger switch or data prune), fall back to the latest
  // month that still has data — computed at render time, not in an effect.
  const month = months.includes(pickedMonth) ? pickedMonth : (months[0] ?? '');
  const spentById = categorySpend(allTxns, activeId, month);

  const cats = MOCK.categories
    .filter((c) => ((c as { ledger?: string }).ledger ?? 'personal') === activeId)
    .map((c) => ({ ...c, spent: spentById[c.id] ?? 0 }))
    .sort((a, b) => b.spent - a.spent);
  const total = cats.reduce((s, c) => s + c.spent, 0);

  const exportNow = () =>
    toast.success('Export started', { description: `${formatMonth(month)} report · CSV` });

  return (
    <MobilePage
      header={<ScreenHeader title="Reports" trailing={<IconButton icon="doc" aria-label="Export" onClick={exportNow} />} />}
    >
      <div className="px-5 pb-[22px]">
        <div className="mb-2 flex items-center justify-between">
          <div className="text-muted-foreground text-[10px] tracking-wider uppercase">Month</div>
          {months.length > 0 ? (
            <Select value={month} onValueChange={setPickedMonth}>
              <SelectTrigger className="border-border bg-card h-7 w-auto min-w-[110px] gap-1.5 rounded-full px-3 text-xs font-medium">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {months.map((m) => (
                  <SelectItem key={m} value={m}>{formatMonth(m)}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          ) : (
            <span className="text-muted-foreground text-xs">—</span>
          )}
        </div>
        <PageHeader
          label="Spent"
          value={<Money value={total} mono={false} />}
          sublabel={`${cats.length} categories`}
        />
      </div>

      <div className="px-5 pb-[120px]">
        {total === 0 ? (
          <div className="text-muted-foreground rounded-xl border border-dashed border-border py-10 text-center text-sm">
            No spending in {formatMonth(month) || 'this ledger'}.
          </div>
        ) : (
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
                    style={{ background: c.color ?? '#9ca3af' }}
                  />
                  <div className="flex-1 truncate text-sm">{c.name}</div>
                  <div className="text-muted-foreground w-9 text-right font-mono text-xs">{pct}%</div>
                  <Money value={c.spent} className="w-20 text-right text-sm" />
                </div>
              );
            })}
          </div>
        )}

        <button
          type="button"
          onClick={exportNow}
          className="bg-secondary text-secondary-foreground mt-4 flex h-11 w-full items-center justify-center gap-2 rounded-xl text-sm font-medium"
        >
          Export CSV
        </button>
      </div>
    </MobilePage>
  );
}
