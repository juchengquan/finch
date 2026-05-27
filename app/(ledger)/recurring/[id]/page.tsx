'use client';

import { useParams } from 'next/navigation';
import { useState } from 'react';
import Link from 'next/link';
import { toast } from 'sonner';
import { Icon, StackedBar } from '@/components/primitives';
import { ScreenHeader, MobilePage, SchemaChip } from '@/components/MobileComponents';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { fmtNative } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { mutate } from '@/lib/api-client';
import { cn } from '@/lib/utils';

const SPLIT_COLOR = (i: number) =>
  i === 0 ? 'var(--primary)' : i === 1 ? 'var(--warning)' : 'var(--success)';

export default function RecurringDetailPage() {
  const params = useParams();
  const id = params.id as string;
  const recurring = useFinanceStore((s) => s.recurring);
  const updateRecurringSplit = useFinanceStore((s) => s.updateRecurringSplit);
  const t = recurring.find((r) => r.id === id) ?? recurring[0];

  const amount = t.amount ?? 0;
  const splits = t.splits ?? [];
  const totalPct = splits.reduce((sum, s) => sum + (s.pct || 0), 0);

  const [posting, setPosting] = useState(false);
  const post = async () => {
    setPosting(true);
    try {
      const state = await mutate('postRecurring', { templateId: t.id });
      useFinanceStore.setState(state);
      toast.success(`Posted “${t.name}”`, { description: 'Added to transactions.' });
    } catch (err) {
      toast.error((err as Error).message || 'Could not post');
    } finally {
      setPosting(false);
    }
  };

  return (
    <MobilePage header={<ScreenHeader title="Recurring" back backHref="/recurring" />}>
      <div className="px-5 pb-[120px]">
        <div className="mb-5 flex items-center gap-2 text-xs text-muted-foreground md:hidden">
          <Link href="/recurring" className="text-muted-foreground">
            Recurring
          </Link>
          <Icon name="chev" size={11} />
          <span className="font-mono text-foreground">{t.id}</span>
        </div>

        <div className="px-1 pb-[22px]">
          <div className="mt-1 font-serif text-[36px] leading-[1.1] tracking-[-0.8px]">
            <span className="italic text-muted-foreground">{t.name}</span><br/>
            <span className="text-[44px]">{t.varies ? 'Varies' : fmtNative(amount, 'SGD')}</span>
          </div>
          <div className="mt-2 text-xs text-muted-foreground">
            {t.frequency} · day {t.dayOfMonth} — next on <b className="text-secondary-foreground">{t.nextRun}</b> · last {t.lastRun}
          </div>
          <Button className="mt-4" onClick={post} disabled={posting || !!t.varies}>
            <Icon name="plus" size={14} />
            {posting ? 'Posting…' : t.varies ? 'Variable — add manually' : 'Post now'}
          </Button>
        </div>

        {splits.length > 0 && (
          <>
            <div className="mb-2 flex items-baseline justify-between px-1">
              <div className="font-serif text-[20px] italic tracking-[-0.2px]">Splits</div>
              <SchemaChip label="recurring_splits"/>
            </div>
            <div className="px-1 pb-2.5 text-xs text-muted-foreground">
              Salary is split across accounts. Total must equal 100%.
            </div>

            <div className="mb-2.5 rounded-[14px] border border-border bg-card p-3.5">
              <StackedBar
                slices={splits.map((s, i) => ({ value: s.pct || 0, color: SPLIT_COLOR(i) }))}
                width={310} height={12} radius={6}/>
              <div className="mt-2.5 flex justify-between font-mono text-[10px] text-muted-foreground">
                <span>0%</span><span>50%</span><span>100%</span>
              </div>
            </div>

            {splits.map((s, i) => {
              const splitAmount = amount * (s.pct || 0) / 100;
              return (
                <div key={i} className="mb-2 rounded-[14px] border border-border bg-card p-3.5">
                  <div className="flex items-center gap-3">
                    <div className="h-9 w-2 rounded" style={{ background: SPLIT_COLOR(i) }}/>
                    <div className="min-w-0 flex-1">
                      <div className="flex items-baseline justify-between gap-2">
                        <div className="text-sm font-medium">{s.account}</div>
                        <div className="font-sans text-sm font-medium tabular-nums">{fmtNative(splitAmount, 'SGD')}</div>
                      </div>
                      <div className="mt-1.5 flex items-center justify-between gap-2">
                        <div className="text-[11px] text-muted-foreground">{s.label}</div>
                        <div className="flex items-center gap-1.5">
                          <Input
                            type="number"
                            value={s.pct}
                            min={0}
                            max={100}
                            aria-label={`${s.account} percent`}
                            onChange={(e) => updateRecurringSplit(t.id, i, Number(e.target.value))}
                            className="h-8 w-16 text-right font-mono text-[13px]"
                          />
                          <span className="font-mono text-[11px] text-muted-foreground">%</span>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              );
            })}

            <div className="mt-2 flex items-center justify-between px-1 text-xs">
              <span className="text-muted-foreground">Total</span>
              <span className={cn('font-mono font-medium tabular-nums', totalPct === 100 ? 'text-success' : 'text-destructive')}>
                {totalPct}%
              </span>
            </div>
          </>
        )}
      </div>
    </MobilePage>
  );
}
