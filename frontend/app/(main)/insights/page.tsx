'use client';

import { useState } from 'react';
import { BarChart, AreaChart } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { MOCK, INSIGHTS, APR_VS_MAY } from '@/lib/data';
import { InsightCard } from '@/components/InsightCard';
import { AprVsMay } from '@/components/AprVsMay';
import { cn } from '@/lib/utils';

const METRICS = [
  { id: 'spending', label: 'Spending' },
  { id: 'income', label: 'Income' },
  { id: 'cashflow', label: 'Cashflow' },
] as const;
type Metric = (typeof METRICS)[number]['id'];

const RANGES = [
  { id: 3, label: '3M' },
  { id: 6, label: '6M' },
  { id: 12, label: '1Y' },
] as const;

export default function InsightsPage() {
  const [metric, setMetric] = useState<Metric>('spending');
  const [range, setRange] = useState<number>(12);

  const monthly = MOCK.monthly.slice(-range);
  const cashflow = MOCK.cashflow.slice(-range);

  return (
    <MobilePage
      header={<ScreenHeader title="Insights" trailing={<IconButton icon="search" />} />}
    >
      <div className="px-5 pb-[22px]">
        <PageHeader
          label="You're spending less"
          value={<span className="font-serif text-[60px] leading-none -tracking-[2px]">↓ 8.4%</span>}
          sublabel={
            <span className="text-secondary-foreground font-serif text-base italic">
              than April. Mostly less <span className="text-primary">Shopping</span>.
            </span>
          }
        />
      </div>

      <div className="px-5 pb-[120px]">
        <div className="bg-card border-border mb-4 rounded-xl border p-3.5">
          <div className="mb-3 flex items-center justify-between gap-2">
            <div className="bg-secondary flex gap-1 rounded-full p-1">
              {METRICS.map((m) => (
                <button
                  key={m.id}
                  type="button"
                  onClick={() => setMetric(m.id)}
                  className={cn(
                    'h-7 rounded-full px-3 text-xs font-medium transition-colors',
                    metric === m.id ? 'bg-background text-foreground shadow-sm' : 'text-muted-foreground',
                  )}
                >
                  {m.label}
                </button>
              ))}
            </div>
            <div className="flex gap-1">
              {RANGES.map((r) => (
                <button
                  key={r.id}
                  type="button"
                  onClick={() => setRange(r.id)}
                  className={cn(
                    'rounded-full px-2 py-1 font-mono text-[10px] tracking-wide transition-colors',
                    range === r.id ? 'bg-foreground text-background' : 'text-muted-foreground',
                  )}
                >
                  {r.label}
                </button>
              ))}
            </div>
          </div>

          {metric === 'spending' && (
            <BarChart
              values={monthly.map((m) => m.v)}
              labels={monthly.map((m) => m.m[0])}
              width={310}
              height={120}
              color="var(--muted-foreground)"
              highlight="var(--primary)"
              muted="var(--secondary)"
            />
          )}
          {metric === 'income' && (
            <BarChart
              values={cashflow.map((c) => c.inc)}
              labels={cashflow.map((c) => c.m[0])}
              width={310}
              height={120}
              color="var(--muted-foreground)"
              highlight="var(--success)"
              muted="var(--secondary)"
            />
          )}
          {metric === 'cashflow' && (
            <>
              <AreaChart
                series={[
                  { values: cashflow.map((c) => c.inc), color: 'var(--success)' },
                  { values: cashflow.map((c) => c.exp), color: 'var(--destructive)' },
                ]}
                labels={cashflow.map((c) => c.m)}
                width={310}
                height={120}
              />
              <div className="text-muted-foreground mt-2 flex gap-4 text-[11px]">
                <span className="flex items-center gap-1.5">
                  <span className="bg-success size-2 rounded-full" />
                  Income
                </span>
                <span className="flex items-center gap-1.5">
                  <span className="bg-destructive size-2 rounded-full" />
                  Expense
                </span>
              </div>
            </>
          )}
        </div>

        {INSIGHTS.map((ins) => (
          <InsightCard key={ins.title} insight={ins} />
        ))}

        <div className="mt-[22px]">
          <div className="mb-2.5 flex items-baseline justify-between">
            <div className="font-serif text-lg italic">Apr vs May</div>
            <span className="text-muted-foreground text-[11px]">Top changes</span>
          </div>
          <AprVsMay data={APR_VS_MAY} />
        </div>
      </div>
    </MobilePage>
  );
}
