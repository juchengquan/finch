'use client';

import { useTranslations } from 'next-intl';
import { catById } from '@/lib/data';
import { Icon } from './primitives';
import { cn } from '@/lib/utils';
import { useMoney } from '@/components/use-money';
import type { WeeklyDigest } from '@/lib/select';

const MONTH_SHORT = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** "Aug 4 – 10" when both ends share a month; "Jul 28 – Aug 3" when they straddle. */
function weekLabel(start: string, end: string): string {
  const [, sm, sd] = start.split('-').map(Number);
  const [, em, ed] = end.split('-').map(Number);
  if (sm === em) return `${MONTH_SHORT[sm - 1]} ${sd} – ${ed}`;
  return `${MONTH_SHORT[sm - 1]} ${sd} – ${MONTH_SHORT[em - 1]} ${ed}`;
}

/** Sunday-night recap card: last week's spend with prev-week / typical comparisons,
 *  top categories, and the biggest single hit. Renders nothing when there's no
 *  digest to show (handed a null by the parent). */
export function WeeklyDigestCard({ digest }: { digest: WeeklyDigest | null }) {
  const { fmt, short } = useMoney();
  const t = useTranslations('weeklyDigest');
  if (!digest) return null;

  const { spent, income, net, vsPrevPct, vsAvgPct, avgSpent, topCategories, biggestExpense, txCount } = digest;
  const pctChip = (pct: number, label: string) => {
    const up = pct > 0;
    return (
      <span
        className={cn(
          'rounded-md px-1.5 py-0.5 font-mono text-[11px] font-medium',
          up ? 'bg-destructive/10 text-destructive' : 'bg-success/10 text-success',
        )}
      >
        {up ? '↑' : '↓'} {Math.abs(Math.round(pct * 100))}% {label}
      </span>
    );
  };

  return (
    <div className="bg-card border-border mb-4 rounded-xl border p-3.5">
      <div className="mb-2 flex items-baseline justify-between">
        <div className="flex items-center gap-1.5 text-sm font-semibold">
          <Icon name="calendar" size={14} />
          {t('title')}
        </div>
        <span className="text-muted-foreground font-mono text-[11px]">{weekLabel(digest.weekStart, digest.weekEnd)}</span>
      </div>

      <div className="mb-3 flex items-baseline gap-3">
        <span className="font-serif text-3xl -tracking-[0.5px]">{fmt(spent)}</span>
        <span className="text-muted-foreground text-xs">{t('spent')}</span>
        {vsPrevPct != null && pctChip(vsPrevPct, t('vsLastWeek'))}
      </div>

      <div className="text-muted-foreground mb-3 flex flex-wrap items-center gap-x-3 gap-y-1 text-[11px]">
        <span>{t('txnsCount', { count: txCount })}</span>
        {income > 0 && <span className="text-success">{t('incomeChip', { amount: short(income) })}</span>}
        <span className={cn(net >= 0 ? 'text-success' : 'text-warning')}>
          {net >= 0 ? t('netPositive', { amount: short(Math.abs(net)) }) : t('netNegative', { amount: short(Math.abs(net)) })}
        </span>
        {vsAvgPct != null && <span>{t('vsTypical', { amount: short(avgSpent) })}</span>}
      </div>

      {topCategories.length > 0 && (
        <div className="border-border border-t pt-3">
          <div className="text-muted-foreground mb-2 font-mono text-[10px] uppercase tracking-wide">{t('topCategories')}</div>
          <div className="space-y-1.5">
            {topCategories.map((c) => {
              const cat = catById(c.categoryId);
              const color = cat.color ?? 'var(--muted-foreground)';
              return (
                <div key={c.categoryId} className="flex items-baseline gap-2">
                  <span className="size-1.5 shrink-0 rounded-full" style={{ background: color }} />
                  <span className="flex-1 truncate text-xs">{cat.name}</span>
                  <span className="font-mono text-xs tabular-nums">{short(c.amount)}</span>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {biggestExpense && (
        <div className="border-border mt-3 flex items-baseline gap-1.5 border-t pt-3 text-[11px]">
          <span className="text-muted-foreground font-mono uppercase tracking-wide">{t('biggestHit')}</span>
          <span className="flex-1 truncate">{biggestExpense.merchant}</span>
          <span className="text-destructive font-mono tabular-nums">{short(biggestExpense.amount)}</span>
        </div>
      )}
    </div>
  );
}
