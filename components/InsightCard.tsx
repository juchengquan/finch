'use client';

import { useTranslations } from 'next-intl';
import { Icon } from './primitives';
import { cn } from '@/lib/utils';
import type { Insight } from '@/lib/insights';

interface InsightCardProps {
  insight: Insight;
}

const TONE: Record<string, string> = {
  pos: 'bg-success/10 text-success',
  warn: 'bg-warning/10 text-warning',
  neut: 'bg-primary/10 text-primary',
};

export function InsightCard({ insight }: InsightCardProps) {
  const t = useTranslations('insightCards');
  return (
    <div className="bg-card border-border mb-2.5 flex gap-3 rounded-xl border p-4">
      <div className={cn('flex size-8 shrink-0 items-center justify-center rounded-full', TONE[insight.tone])}>
        <Icon name={insight.icon} size={16} />
      </div>
      <div className="flex-1">
        <div className="mb-1 font-serif text-lg -tracking-[0.2px]">{t(insight.title.key, insight.title.params)}</div>
        <div className="text-secondary-foreground text-xs leading-relaxed">{t(insight.body.key, insight.body.params)}</div>
      </div>
    </div>
  );
}
