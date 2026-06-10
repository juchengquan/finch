'use client';

import { useTranslations } from 'next-intl';
import { Check } from '@/components/icons';
import { fmtNative } from '@/lib/data';
import { cn } from '@/lib/utils';
import type { AccountRow } from '@/lib/db/domain/accounts/types';

const STALE_AFTER_DAYS = 35;

function daysBetween(isoDate: string, today: Date): number {
  // isoDate is YYYY-MM-DD; treat both ends as UTC midnight so DST doesn't slosh.
  const [y, m, d] = isoDate.slice(0, 10).split('-').map(Number);
  const a = Date.UTC(y, m - 1, d);
  const b = Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate());
  return Math.max(0, Math.floor((b - a) / 86400000));
}

/** Status line for the reconcile-to-statement checkpoint. Three states:
 *  - **Never reconciled** — muted "Never reconciled" hint.
 *  - **Recently reconciled** (≤ 35 days) — success-tinted "✓ Reconciled to $X · 5 days ago".
 *  - **Stale** (> 35 days) — warning-tinted same line with "47 days ago".
 *
 *  The 35-day threshold matches RECONCILE_PLAN §7 ("a single 35-day default,
 *  revisit if it's noisy"). The "edited since" amber state from the plan is
 *  not yet wired — it needs a transaction-level updated_at proxy we don't
 *  surface in the projected store yet; tracked as a follow-up. */
export function ReconcileStatus({
  account,
  today = new Date(),
}: {
  account: AccountRow;
  today?: Date;
}) {
  const t = useTranslations('reconcileStatus');
  if (!account.lastReconciledAt) {
    return (
      <span className="text-muted-foreground inline-flex items-center gap-1.5 font-mono text-[11px]">
        <Check size={11} />
        {t('never')}
      </span>
    );
  }
  const days = daysBetween(account.lastReconciledAt, today);
  const stale = days > STALE_AFTER_DAYS;
  const balance = account.lastReconciledBalance ?? 0;
  const ago = days === 0 ? t('today') : days === 1 ? t('yesterday') : t('daysAgo', { count: days });
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 font-mono text-[11px]',
        stale ? 'text-warning' : 'text-success',
      )}
      title={t('title', { date: account.lastReconciledAt })}
    >
      <Check size={11} />
      {t('reconciledTo', { balance: fmtNative(balance, account.currency), when: ago })}
    </span>
  );
}
