'use client';

import { useMemo } from 'react';
import { useTranslations } from 'next-intl';
import { useFinanceStore } from '@/lib/store';
import { useLedger } from '@/components/ledger-provider';
import { useMoney } from '@/components/use-money';
import { netWorthExplained, currentMonth } from '@/lib/select';

const MONTHS = 6;
const PAD = 8;
const W = 320;
const H = 160;
const COL_GAP = 6;

type Bucket = { key: 'income' | 'expense' | 'adjustment' | 'fx'; value: number; color: string };

/** DE §10.7 net-worth-explained panel. Decomposes the last 6 months of
 *  net-worth movement into four signed buckets (income, expense, adjustment,
 *  FX residual) using the {@link netWorthExplained} selector. Renders as a
 *  bespoke inline-SVG stacked-bar chart (one column per month, positive
 *  segments above the zero axis, negative below) in the chart-1..4 palette,
 *  following the codebase precedent for one-off charts (Sankey, CalendarHeatmap).
 *
 *  Hides automatically when the active ledger has no movement in the window. */
export function NetWorthExplainedCard() {
  const t = useTranslations('insights.netWorthExplained');
  const txns = useFinanceStore((s) => s.transactions);
  const accounts = useFinanceStore((s) => s.accounts);
  const { activeId } = useLedger();
  const { fmt, toBase } = useMoney();

  const series = useMemo(
    () => netWorthExplained(txns, accounts, activeId, currentMonth(txns, activeId), MONTHS, toBase),
    [txns, accounts, activeId, toBase],
  );

  if (
    series.length === 0 ||
    series.every((s) => s.income === 0 && s.expense === 0 && s.adjustment === 0 && s.fx === 0)
  ) {
    return null;
  }

  // Build each month's 4 buckets, signed by their net-worth effect:
  //   income     contributes positively
  //   expense    contributes negatively (selector stores positive magnitude → flip)
  //   adjustment is signed as-is (either direction)
  //   fx         is signed as-is (residual, only non-zero on cross-currency flows)
  const columns: Bucket[][] = series.map((s) => [
    { key: 'income', value: s.income, color: 'var(--color-chart-2)' },
    { key: 'expense', value: -s.expense, color: 'var(--color-chart-1)' },
    { key: 'adjustment', value: s.adjustment, color: 'var(--color-chart-3)' },
    { key: 'fx', value: s.fx, color: 'var(--color-chart-4)' },
  ]);

  // Domain for the y axis: max sum-of-positives vs |sum-of-negatives| across all months.
  // Floor at 1 so a window with only tiny rounding-residue FX rows doesn't divide by zero.
  const maxAbs = Math.max(
    1,
    ...columns.map((col) => col.filter((b) => b.value > 0).reduce((s, b) => s + b.value, 0)),
    ...columns.map((col) => Math.abs(col.filter((b) => b.value < 0).reduce((s, b) => s + b.value, 0))),
  );
  const innerW = W - PAD * 2;
  const innerH = H - PAD * 2;
  const colW = (innerW - COL_GAP * (series.length - 1)) / series.length;
  const zeroY = PAD + innerH / 2;
  const scale = innerH / 2 / maxAbs;

  return (
    <div className="bg-card border-border mb-4 rounded-xl border p-3.5">
      <div className="mb-2 flex items-baseline justify-between">
        <div className="text-sm font-semibold">{t('title')}</div>
      </div>
      <p className="text-muted-foreground mb-3 text-xs">{t('subtitle')}</p>
      <svg viewBox={`0 0 ${W} ${H}`} width="100%" height={H} role="img" aria-label={t('chartAria')}>
        <line x1={PAD} y1={zeroY} x2={W - PAD} y2={zeroY} stroke="var(--border)" strokeWidth={1} />
        {columns.map((col, ci) => {
          const x = PAD + ci * (colW + COL_GAP);
          let yPos = zeroY;
          let yNeg = zeroY;
          return (
            <g key={series[ci].m}>
              {col.map((b) => {
                if (b.value === 0) return null;
                const h = Math.abs(b.value) * scale;
                if (b.value > 0) {
                  const y = yPos - h;
                  yPos = y;
                  return <rect key={b.key} x={x} y={y} width={colW} height={h} fill={b.color} opacity={0.85} />;
                }
                const y = yNeg;
                yNeg = y + h;
                return <rect key={b.key} x={x} y={y} width={colW} height={h} fill={b.color} opacity={0.85} />;
              })}
              <text
                x={x + colW / 2}
                y={H - 2}
                textAnchor="middle"
                className="fill-muted-foreground"
                fontSize={10}
              >
                {series[ci].m.slice(5)}
              </text>
            </g>
          );
        })}
      </svg>
      <ul className="text-muted-foreground mt-3 flex flex-wrap gap-x-4 gap-y-1 text-xs">
        {(['income', 'expense', 'adjustment', 'fx'] as const).map((key, i) => (
          <li key={key} className="flex items-center gap-1.5">
            <span
              className="inline-block size-3 rounded-sm"
              style={{ background: `var(--color-chart-${[2, 1, 3, 4][i]})` }}
            />
            {t(key)}
          </li>
        ))}
      </ul>
      <p className="text-muted-foreground mt-2 text-xs">
        {t('netLatest', { value: fmt(series[series.length - 1].net) })}
      </p>
    </div>
  );
}
