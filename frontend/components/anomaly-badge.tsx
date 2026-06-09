'use client';

import { useTranslations } from 'next-intl';
import { Bell } from '@/components/icons';

/** Marks a transaction whose magnitude is unusually far from the merchant's
 *  historical mean. Surfaced inline next to the merchant name so users notice
 *  "wait, $89 at Bali Beach is 4× my usual tab" — catches both fraud and
 *  honest mistakes. Threshold + min-sample-count live in the anomalyScore
 *  selector; this is purely cosmetic. */
export function AnomalyBadge({ zScore, mean }: { zScore: number; mean: number }) {
  const t = useTranslations('badges');
  const x = Math.round((zScore + Number.EPSILON) * 10) / 10;
  return (
    <span
      className="bg-warning/10 text-warning inline-flex shrink-0 items-center gap-0.5 rounded px-1.5 py-0.5 text-[10px] font-medium leading-none"
      title={t('unusualTitle', { multiplier: x.toFixed(1), mean: mean.toFixed(2) })}
    >
      <Bell size={9} />
      {t('unusual')}
    </span>
  );
}
