'use client';

import { useState } from 'react';
import { useTranslations } from 'next-intl';
import { Sparkle } from '@/components/icons';
import { useMoney } from '@/components/use-money';
import { cn } from '@/lib/utils';
import type { WhatIfBaseline } from '@/lib/select';

interface CategoryRef {
  id: string;
  name: string;
  color: string;
}

/** Interactive hypotheticals over the trailing-months baseline: drag a
 *  category's slider to a % cut and see the monthly/annual savings plus the
 *  effect on the average monthly net. Pure client math — nothing persists.
 *  Renders nothing when the ledger has no baseline to reason from. */
export function WhatIfCard({
  baseline,
  categories,
}: {
  baseline: WhatIfBaseline | null;
  categories: CategoryRef[];
}) {
  const { fmt, short } = useMoney();
  const t = useTranslations('insights.whatIf');
  const [cuts, setCuts] = useState<Record<string, number>>({});
  if (!baseline) return null;

  const catById = new Map(categories.map((c) => [c.id, c]));
  const rows = baseline.categories.map((c) => ({
    ...c,
    name: catById.get(c.categoryId)?.name ?? c.categoryId,
    color: catById.get(c.categoryId)?.color ?? 'var(--muted-foreground)',
    pct: cuts[c.categoryId] ?? 0,
  }));
  if (rows.length === 0) return null;

  const monthlySave = rows.reduce((s, r) => s + (r.avgMonthly * r.pct) / 100, 0);
  const hasCuts = monthlySave > 0;
  const netBefore = baseline.avgIncome - baseline.avgSpend;
  const netAfter = netBefore + monthlySave;

  return (
    <div className="bg-card border-border mb-4 rounded-xl border p-3.5">
      <div className="mb-1 flex items-baseline justify-between">
        <div className="flex items-center gap-1.5 text-sm font-semibold">
          <Sparkle size={14} />
          {t('title')}
        </div>
        {hasCuts && (
          <button
            type="button"
            onClick={() => setCuts({})}
            className="text-muted-foreground text-[11px] underline-offset-2 hover:underline"
          >
            {t('reset')}
          </button>
        )}
      </div>
      <p className="text-muted-foreground mb-3 text-[11px]">
        {t('subtitle', { count: baseline.months.length })}
      </p>

      <div className="space-y-2.5">
        {rows.map((r) => {
          const save = (r.avgMonthly * r.pct) / 100;
          return (
            <div key={r.categoryId}>
              <div className="mb-1 flex items-baseline gap-2 text-xs">
                <span className="size-1.5 shrink-0 rounded-full" style={{ background: r.color }} />
                <span className="flex-1 truncate">{r.name}</span>
                <span className="text-muted-foreground font-mono text-[11px] tabular-nums">
                  {t('avgPerMonth', { amount: short(r.avgMonthly) })}
                </span>
              </div>
              <div className="flex items-center gap-2.5">
                <input
                  type="range"
                  min={0}
                  max={100}
                  step={5}
                  value={r.pct}
                  aria-label={t('sliderAria', { category: r.name })}
                  onChange={(e) => setCuts((c) => ({ ...c, [r.categoryId]: Number(e.target.value) }))}
                  className="h-1.5 flex-1 cursor-pointer appearance-none rounded-full bg-secondary accent-[var(--primary)]"
                  style={{ accentColor: 'var(--primary)' }}
                />
                <span
                  className={cn(
                    'w-24 text-right font-mono text-[11px] tabular-nums',
                    r.pct > 0 ? 'text-success' : 'text-muted-foreground',
                  )}
                >
                  {r.pct > 0 ? t('rowSaves', { pct: r.pct, amount: short(save) }) : t('rowIdle')}
                </span>
              </div>
            </div>
          );
        })}
      </div>

      <div className="border-border mt-3 border-t pt-3">
        {hasCuts ? (
          <>
            <div className="flex items-baseline gap-3">
              <span className="font-serif text-2xl -tracking-[0.5px]">{fmt(monthlySave * 12)}</span>
              <span className="text-muted-foreground text-xs">{t('perYear')}</span>
              <span className="bg-success/10 text-success rounded-md px-1.5 py-0.5 font-mono text-[11px] font-medium">
                {t('perMonthChip', { amount: short(monthlySave) })}
              </span>
            </div>
            {baseline.avgIncome > 0 && (
              <p className="text-muted-foreground mt-1.5 text-[11px]">
                {t('netChange', { before: fmt(netBefore), after: fmt(netAfter) })}
              </p>
            )}
          </>
        ) : (
          <p className="text-muted-foreground text-[11px]">{t('prompt')}</p>
        )}
      </div>
    </div>
  );
}
