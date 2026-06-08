'use client';

import { useMemo } from 'react';
import { useTranslations } from 'next-intl';
import { useFinanceStore } from '@/lib/store';
import { useLedger } from '@/components/ledger-provider';
import { useMoney } from '@/components/use-money';
import { netWorthByAccountType } from '@/lib/select';
import { ACCOUNT_TYPE_VALUES, type AccountType } from '@/lib/account-types';

const PAD = 8;
const W = 320;
const H = 160;
const COL_GAP = 6;

// Single colour for the per-type columns (mirrors the legend swatch). Pinned
// to chart-3 to keep the palette tight alongside the other Insights charts.
const BUCKET_COLOR = 'var(--color-chart-3)';

const TYPE_LABEL_KEYS: Record<AccountType, string> = {
  cash: 'cash',
  savings: 'savings',
  investment: 'investment',
  credit_card: 'creditCard',
  fx: 'fx',
  virtual: 'virtual',
};

/** Per-account-type net-worth breakdown. Decomposes the active ledger's net
 *  worth across the 6 canonical account types using the
 *  {@link netWorthByAccountType} selector. Renders as a bespoke inline-SVG
 *  bar chart (one column per type, positive bar above the zero axis /
 *  negative below) so a single component is self-explanatory. Auto-hides
 *  when every bucket is zero (no positions to chart). */
export function NetWorthByTypeCard() {
  const t = useTranslations('insights.netWorthByType');
  const accounts = useFinanceStore((s) => s.accounts);
  const { activeId } = useLedger();
  const { fmt, toBase } = useMoney();

  const buckets = useMemo(
    () => netWorthByAccountType(accounts, activeId, toBase),
    [accounts, activeId, toBase],
  );

  if (buckets.every((b) => b.balance === 0)) {
    return null;
  }

  const maxAbs = Math.max(1, ...buckets.map((b) => Math.abs(b.balance)));
  const innerW = W - PAD * 2;
  const innerH = H - PAD * 2;
  const colW = (innerW - COL_GAP * (buckets.length - 1)) / buckets.length;
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
        {buckets.map((b, i) => {
          const x = PAD + i * (colW + COL_GAP);
          const h = Math.abs(b.balance) * scale;
          if (b.balance >= 0) {
            const y = zeroY - h;
            return <rect key={b.type} x={x} y={y} width={colW} height={h} fill={BUCKET_COLOR} opacity={0.85} />;
          }
          return <rect key={b.type} x={x} y={zeroY} width={colW} height={h} fill={BUCKET_COLOR} opacity={0.85} />;
        })}
      </svg>
      <ul className="text-muted-foreground mt-3 flex flex-wrap gap-x-4 gap-y-1 text-xs">
        {ACCOUNT_TYPE_VALUES.map((type) => (
          <li key={type} className="flex items-center gap-1.5">
            <span
              className="inline-block size-3 rounded-sm"
              style={{ background: BUCKET_COLOR }}
            />
            {t(TYPE_LABEL_KEYS[type])}
          </li>
        ))}
      </ul>
      <p className="text-muted-foreground mt-2 text-xs">
        {t('totalNote', { value: fmt(buckets.reduce((s, b) => s + b.balance, 0)) })}
      </p>
    </div>
  );
}
