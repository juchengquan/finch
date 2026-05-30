'use client';

import { useState } from 'react';
import { BarChart, AreaChart, CalendarHeatmap, Sankey } from '@/components/primitives';
import { ScreenHeader, MobilePage, PageHeader } from '@/components/MobileComponents';
import { SearchButton } from '@/components/command-palette';
import { MOCK } from '@/lib/data';
import { InsightCard } from '@/components/InsightCard';
import { AprVsMay } from '@/components/AprVsMay';
import { useLedger } from '@/components/ledger-provider';
import { useMoney } from '@/components/use-money';
import { useFinanceStore } from '@/lib/store';
import { generateInsights } from '@/lib/insights';
import { categorySpend, currentMonth, prevMonth, monthlySpending, monthlyCashflow, topCategoryDeltas, dailySpending, netWorthByMonth, monthForecast, incomeCategoryFlow } from '@/lib/select';
import { cn } from '@/lib/utils';

import type { MonthForecast } from '@/lib/select';

const MONTH_LABELS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const fullMonth = (ym: string) => (ym ? MONTH_LABELS[Number(ym.slice(5)) - 1] : '');

// Stacked horizontal bar that visualises the four forecast components
// (mtd / unscheduled / scheduled) at their proportional widths.
function ForecastBar({ forecast }: { forecast: MonthForecast }) {
  const total = forecast.projected;
  if (total <= 0) return null;
  const segs = [
    { v: forecast.mtdSpent, color: 'var(--primary)' },
    { v: forecast.unscheduledRest, color: 'var(--muted-foreground)' },
    { v: forecast.scheduledRest, color: 'var(--warning)' },
  ];
  return (
    <div className="bg-secondary flex h-2.5 w-full overflow-hidden rounded-full">
      {segs.map((s, i) =>
        s.v > 0 ? <span key={i} style={{ width: `${(s.v / total) * 100}%`, background: s.color }} /> : null,
      )}
    </div>
  );
}

const METRICS = [
  { id: 'spending', label: 'Spending' },
  { id: 'income', label: 'Income' },
  { id: 'cashflow', label: 'Cashflow' },
  { id: 'networth', label: 'Net worth' },
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
  const { activeId } = useLedger();
  const { fmt } = useMoney();
  const transactions = useFinanceStore((s) => s.transactions);
  const accounts = useFinanceStore((s) => s.accounts);
  const goals = useFinanceStore((s) => s.goals);
  const scheduled = useFinanceStore((s) => s.scheduled);
  const budgetByCategory = useFinanceStore((s) => s.budgetByCategory);

  // Live category mapping from the seed (still serves the budget lookup); the
  // page now derives monthly/cashflow series and the category-deltas comparison
  // straight from the projected transactions.
  const ledgerCategories = (MOCK.categories as { id: string; name: string; budget: number; hue?: number; ledger?: string }[])
    .filter((c) => (c.ledger ?? 'personal') === activeId)
    .map((c) => ({ id: c.id, name: c.name, budget: budgetByCategory[c.id] ?? c.budget, hue: c.hue ?? 200 }));
  const month = currentMonth(transactions, activeId);
  const lastDate = transactions.reduce(
    (d, t) => ((t.ledgerId ?? 'personal') === activeId && t.date > d ? t.date : d),
    '',
  );
  const monthly = monthlySpending(transactions, activeId, month, range);
  const cashflow = monthlyCashflow(transactions, activeId, month, range);
  const networth = netWorthByMonth(transactions, accounts, activeId, month, range);
  const heatmap = dailySpending(transactions, activeId, lastDate, 12 * 7); // 12 weeks
  const categoryDeltas = topCategoryDeltas(transactions, activeId, month, ledgerCategories, 5);
  const insights = generateInsights({
    transactions,
    categories: ledgerCategories,
    goals: goals.filter((g) => g.ledgerId === activeId),
    accounts,
    ledgerId: activeId,
    month,
    fmt: (n) => fmt(n),
  });

  // Month-over-month spending for the header (falls back to curated copy if there's
  // no prior-month data yet).
  const curSpend = Object.values(categorySpend(transactions, activeId, month)).reduce((s, v) => s + v, 0);
  const prevSpend = month
    ? Object.values(categorySpend(transactions, activeId, prevMonth(month))).reduce((s, v) => s + v, 0)
    : 0;
  const momPct = prevSpend > 0 ? Math.round(((curSpend - prevSpend) / prevSpend) * 100) : null;

  // Spending forecast: project the rest of the current month from run-rate +
  // upcoming scheduled items. `lastDate` is the most-recent transaction
  // for the ledger, which approximates "today" without a wall-clock dependency.
  const forecast = month ? monthForecast(transactions, scheduled, activeId, month, lastDate) : null;
  const forecastVsPrev =
    forecast && prevSpend > 0 ? Math.round(((forecast.projected - prevSpend) / prevSpend) * 100) : null;

  // Income → categories flow for the Sankey card.
  const flow = month ? incomeCategoryFlow(transactions, ledgerCategories, activeId, month, 6) : null;

  return (
    <MobilePage
      header={<ScreenHeader title="Insights" trailing={<SearchButton />} />}
    >
      <div className="px-5 pb-[22px]">
        <PageHeader
          label={momPct == null ? "Your spending" : momPct <= 0 ? "You're spending less" : "You're spending more"}
          value={
            <span className="font-serif text-[60px] leading-none -tracking-[2px]">
              {momPct == null ? fmt(curSpend) : `${momPct <= 0 ? '↓' : '↑'} ${Math.abs(momPct)}%`}
            </span>
          }
          sublabel={
            <span className="text-secondary-foreground font-serif text-base italic">
              {momPct == null ? 'this month' : 'than last month'}
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
              width={600}
              height={150}
              className="h-40 w-full"
              color="var(--muted-foreground)"
              highlight="var(--primary)"
              muted="var(--secondary)"
            />
          )}
          {metric === 'income' && (
            <BarChart
              values={cashflow.map((c) => c.inc)}
              labels={cashflow.map((c) => c.m[0])}
              width={600}
              height={150}
              className="h-40 w-full"
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
                width={600}
                height={150}
                className="h-40 w-full"
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
          {metric === 'networth' && (
            <>
              <AreaChart
                series={[{ values: networth.map((n) => n.v), color: 'var(--primary)' }]}
                labels={networth.map((n) => n.m)}
                width={600}
                height={150}
                className="h-40 w-full"
              />
              <div className="text-muted-foreground mt-2 flex items-baseline justify-between text-[11px]">
                <span>
                  {networth[0] && `${networth[0].m}: ${fmt(networth[0].v)}`}
                </span>
                <span>
                  {networth[networth.length - 1] &&
                    `${networth[networth.length - 1].m}: ${fmt(networth[networth.length - 1].v)}`}
                </span>
              </div>
            </>
          )}
        </div>

        {forecast && forecast.daysRemaining > 0 && (
          <div className="bg-card border-border mb-4 rounded-xl border p-3.5">
            <div className="mb-2 flex items-baseline justify-between">
              <div className="text-sm font-semibold">Spending forecast</div>
              <span className="text-muted-foreground text-[11px]">
                day {forecast.daysElapsed} of {forecast.daysInMonth}
              </span>
            </div>
            <div className="mb-3 flex items-baseline gap-3">
              <span className="font-serif text-3xl -tracking-[0.5px]">{fmt(forecast.projected)}</span>
              <span className="text-muted-foreground text-xs">projected</span>
              {forecastVsPrev != null && (
                <span
                  className={cn(
                    'rounded-md px-1.5 py-0.5 text-[11px] font-medium',
                    forecastVsPrev > 0 ? 'bg-destructive/10 text-destructive' : 'bg-success/10 text-success',
                  )}
                >
                  {forecastVsPrev > 0 ? '↑' : '↓'} {Math.abs(forecastVsPrev)}% vs {fullMonth(prevMonth(month))}
                </span>
              )}
            </div>
            <ForecastBar forecast={forecast} />
            <div className="mt-3 grid grid-cols-2 gap-x-4 gap-y-1.5 text-[11px]">
              <span className="flex items-center gap-1.5 text-muted-foreground">
                <span className="bg-primary size-2 rounded-full" />
                Spent so far · {fmt(forecast.mtdSpent)}
              </span>
              <span className="flex items-center gap-1.5 text-muted-foreground">
                <span className="bg-muted-foreground size-2 rounded-full" />
                Run-rate rest · {fmt(forecast.unscheduledRest)}
              </span>
              {forecast.scheduledRest > 0 && (
                <span className="flex items-center gap-1.5 text-muted-foreground">
                  <span className="bg-warning size-2 rounded-full" />
                  Scheduled · {fmt(forecast.scheduledRest)}
                </span>
              )}
            </div>
          </div>
        )}

        {flow && flow.income > 0 && flow.categories.length > 0 && (
          <div className="bg-card border-border mb-4 rounded-xl border p-3.5">
            <div className="mb-2 flex items-baseline justify-between">
              <div className="text-sm font-semibold">Where {fullMonth(month)} income went</div>
              <span className="text-muted-foreground text-[11px]">{fmt(flow.income)} in</span>
            </div>
            <div className="overflow-hidden">
              <Sankey
                left={[{ name: 'Income', value: flow.income, color: 'var(--success)' }]}
                right={[
                  ...flow.categories.map((c) => ({
                    name: c.name,
                    value: c.spent,
                    color: `oklch(0.65 0.13 ${c.hue})`,
                  })),
                  ...(flow.saved > 0
                    ? [{ name: 'Saved', value: flow.saved, color: 'var(--primary)' }]
                    : []),
                ]}
                width={520}
                height={180}
                className="h-44 w-full"
              />
            </div>
            <div className="text-muted-foreground mt-3 flex flex-wrap gap-x-3 gap-y-1.5 text-[11px]">
              {flow.categories.map((c) => (
                <span key={c.id} className="flex items-center gap-1.5">
                  <span className="size-2 rounded-full" style={{ background: `oklch(0.65 0.13 ${c.hue})` }} />
                  {c.name} · {fmt(c.spent)}
                </span>
              ))}
              {flow.saved > 0 && (
                <span className="flex items-center gap-1.5">
                  <span className="bg-primary size-2 rounded-full" />
                  Saved · {fmt(flow.saved)}
                </span>
              )}
            </div>
          </div>
        )}

        {heatmap.some((d) => d.value > 0) && (
          <div className="bg-card border-border mb-4 rounded-xl border p-3.5">
            <div className="mb-2 flex items-baseline justify-between">
              <div className="text-sm font-semibold">Daily spending</div>
              <span className="text-muted-foreground text-[11px]">last 12 weeks</span>
            </div>
            <div className="overflow-x-auto">
              <CalendarHeatmap values={heatmap} />
            </div>
          </div>
        )}

        {insights.length > 0 ? (
          <div className="md:grid md:grid-cols-3 md:gap-3">
            {insights.map((ins) => (
              <InsightCard key={ins.title} insight={ins} />
            ))}
          </div>
        ) : (
          <div className="text-muted-foreground rounded-xl border border-dashed border-border py-8 text-center text-sm">
            Add a few transactions to see insights.
          </div>
        )}

        {categoryDeltas.length > 0 && (
          <div className="mt-[22px]">
            <div className="mb-2.5 flex items-baseline justify-between">
              <div className="font-serif text-lg italic">{fullMonth(prevMonth(month))} vs {fullMonth(month)}</div>
              <span className="text-muted-foreground text-[11px]">Top changes</span>
            </div>
            <AprVsMay data={categoryDeltas} />
          </div>
        )}
      </div>
    </MobilePage>
  );
}
