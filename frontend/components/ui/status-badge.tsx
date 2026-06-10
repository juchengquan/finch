// frontend/components/ui/status-badge.tsx — extracted from
// components/StatusBadge.tsx (30 lines; PR 4). Pending vs done
// indicator for transactions and scheduled occurrences.
// `pending` (unconfirmed) reads amber; `done` (confirmed, the
// default) is muted. `upcoming` is for a scheduled occurrence that
// hasn't been generated yet.
'use client';

import { useTranslations } from 'next-intl';
import { cn } from '@/lib/utils';

export function StatusBadge({
  status = 'done',
  className,
}: {
  status?: 'pending' | 'done' | 'upcoming';
  className?: string;
}) {
  const t = useTranslations('badges');
  return (
    <span
      className={cn(
        'rounded px-1.5 py-0.5 font-mono text-[9px] tracking-[0.6px] uppercase',
        status === 'pending'
          ? 'bg-warning/10 text-warning'
          : 'bg-secondary text-secondary-foreground',
        className,
      )}
    >
      {t(status)}
    </span>
  );
}
