'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Money, BarChart, AreaChart, CalendarHeatmap, Sankey } from '@/components/primitives';
import { ScreenHeader, MobilePage, PageHeader } from '@/components/MobileComponents';
import { SearchButton } from '@/components/command-palette';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { MOCK } from '@/lib/data';
import { InsightCard } from '@/components/InsightCard';
import { AprVsMay } from '@/components/AprVsMay';
import { WeeklyDigestCard } from '@/components/weekly-digest-card';
import { useLedger } from '@/components/ledger-provider';
import { useMoney } from '@/components/use-money';
import { useBackup } from '@/components/sqlite-backup-provider';
import { useFinanceStore } from '@/lib/store';
import { generateInsights } from '@/lib/insights';
import { categorySpend, currentMonth, prevMonth, monthlySpending, monthlyCashflow, topCategoryDeltas, dailySpending, netWorthByMonth, monthForecast, incomeCategoryFlow, weeklyDigest } from '@/lib/select';
import { cn } from '@/lib/utils';

import type { MonthForecast } from '@/lib/select';

const MONTH_LABELS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const fullMonth = (ym: string) => (ym ? MONTH_LABELS[Number(ym.slice(5)) - 1] : '');
const formatMonth = (ym: string) => (ym ? `${MONTH_LABELS[Number(ym.slice(5)) - 1]} ${ym.slice(0, 4)}` : '');

const VIEWS = [
  { id: 'trends', label: 'Trends' },
  { id: 'breakdown', label: 'Breakdown' },
] as const;
type View = (typeof VIEWS)[number]['id'];

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
  const [view, setView] = useState<View>('trends');
  const [metric, setMetric] = useState<Metric>('spending');
  const [range, setRange] = useState<number>(12);
  const { activeId } = useLedger();
  const { fmt, toBase } = useMoney();
  const { downloadCsv } = useBackup();
  const transactions = useFinanceStore((s) => s.transactions);
  const accounts = useFinanceStore((s) => s.accounts);
  const budgets = useFinanceStore((s) => s.budgets);
  const scheduled = useFinanceStore((s) => s.scheduled);

  // --- Breakdown view (formerly the Reports page): a month picker + the
  // per-category spend list for the chosen month. The picker is restricted to
  // months that actually have data in the active ledger. ---
  const breakdownMonths = useMemo(() => {
    const set = new Set<string>();
    for (const t of transactions) {
      if ((t.ledgerId ?? 'personal') === activeId) set.add(t.date.slice(0, 7));
    }
    return Array.from(set).sort().reverse();
  }, [transactions, activeId]);
  const [pickedMonth, setPickedMonth] = useState<string>(() => currentMonth(transactions, activeId));
  // The pick is the source of truth; if it falls out of range (ledger switch,
  // data prune) fall back to the latest month with data — at render, no effect.
  const breakdownMonth = breakdownMonths.includes(pickedMonth) ? pickedMonth : (breakdownMonths[0] ?? '');
  const breakdownSpentById = categorySpend(transactions, activeId, breakdownMonth);
  const breakdownCats = (MOCK.categories as { id: string; name: string; color?: string; ledger?: string }[])
    .filter((c) => (c.ledger ?? 'personal') === activeId)
    .map((c) => ({ id: c.id, name: c.name, color: c.color ?? '#9ca3af', spent: breakdownSpentById[c.id] ?? 0 }))
    .sort((a, b) => b.spent - a.spent);
  const breakdownTotal = breakdownCats.reduce((s, c) => s + c.spent, 0);

  const exportCsv = () => {
    void downloadCsv()
      .then(() => toast.success('Transactions exported', { description: 'CSV downloaded' }))
      .catch((err) => toast.error('Export failed', { description: String((err as Error).message ?? err) }));
  };

  // Category reference (name + static seed budget) for the deltas comparison; the
  // page derives monthly/cashflow series straight from the projected transactions.
  const ledgerCategories = (MOCK.categories as { id: string; name: string; budget: number; color?: string; ledger?: string }[])
    .filter((c) => (c.ledger ?? 'personal') === activeId)
    .map((c) => ({ id: c.id, name: c.name, budget: c.budget, color: c.color ?? '#9ca3af' }));
  const month = currentMonth(transactions, activeId);
  const lastDate = transactions.reduce(
    (d, t) => ((t.ledgerId ?? 'personal') === activeId && t.date > d ? t.date : d),
    '',
  );
  const monthly = monthlySpending(transactions, activeId, month, range);
  const cashflow = monthlyCashflow(transactions, activeId, month, range);
  const networth = netWorthByMonth(transactions, accounts, activeId, month, range, toBase);
  const heatmap = dailySpending(transactions, activeId, lastDate, 12 * 7); // 12 weeks
  const categoryDeltas = topCategoryDeltas(transactions, activeId, month, ledgerCategories, 5);
  const insights = generateInsights({
    transactions,
    categories: ledgerCategories,
    // "Goals" insights now run off income budgets (Goals were merged into Budgets).
    goals: budgets
      .filter((b) => b.ledgerId === activeId && b.type === 'income')
      .map((b) => ({ id: b.id, name: b.name, target: b.amount, saved: b.saved })),
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

  // Sunday-night recap card: most recently completed Mon-Sun. `lastDate`
  // approximates "today" without a wall-clock dependency (mirrors monthForecast).
  const digest = lastDate ? weeklyDigest(transactions, activeId, lastDate) : null;

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
        {/* Trends / Breakdown view toggle (Insights + the former Reports page). */}
        <div role="tablist" aria-label="Insights view" className="bg-secondary mb-4 flex gap-1 rounded-full p-1">
          {VIEWS.map((v) => (
            <button
              key={v.id}
              type="button"
              role="tab"
              aria-selected={view === v.id}
              onClick={() => setView(v.id)}
              className={cn(
                'h-8 flex-1 rounded-full text-xs font-medium transition-colors',
                view === v.id ? 'bg-background text-foreground shadow-sm' : 'text-muted-foreground',
              )}
            >
              {v.label}
            </button>
          ))}
        </div>

        {view === 'breakdown' ? (
          <div>
            <div className="mb-2 flex items-center justify-between">
              <div className="text-muted-foreground text-[10px] tracking-wider uppercase">Month</div>
              {breakdownMonths.length > 0 ? (
                <Select value={breakdownMonth} onValueChange={setPickedMonth}>
                  <SelectTrigger className="border-border bg-card h-7 w-auto min-w-[110px] gap-1.5 rounded-full px-3 text-xs font-medium">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {breakdownMonths.map((m) => (
                      <SelectItem key={m} value={m}>{formatMonth(m)}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              ) : (
                <span className="text-muted-foreground text-xs">—</span>
              )}
            </div>
            <div className="mb-4">
              <PageHeader
                label="Spent"
                value={<Money value={breakdownTotal} mono={false} />}
                sublabel={`${breakdownCats.length} categories`}
              />
            </div>
            {breakdownTotal === 0 ? (
              <div className="text-muted-foreground border-border rounded-xl border border-dashed py-10 text-center text-sm">
                No spending in {formatMonth(breakdownMonth) || 'this ledger'}.
              </div>
            ) : (
              <div>
                {breakdownCats.filter((c) => c.spent > 0).map((c) => {
                  const pct = breakdownTotal ? Math.round((c.spent / breakdownTotal) * 100) : 0;
                  return (
                    <div key={c.id} className="border-border flex items-center gap-3 border-t py-3 first:border-t-0">
                      <span className="size-2.5 shrink-0 rounded-full" style={{ background: c.color }} />
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
              onClick={exportCsv}
              className="bg-secondary text-secondary-foreground mt-4 flex h-11 w-full items-center justify-center gap-2 rounded-xl text-sm font-medium"
            >
              Export transactions CSV
            </button>
          </div>
        ) : (
        <>
        <WeeklyDigestCard digest={digest} />
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
                    color: c.color,
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
                  <span className="size-2 rounded-full" style={{ background: c.color }} />
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
        </>
        )}
      </div>
    </MobilePage>
  );
}
