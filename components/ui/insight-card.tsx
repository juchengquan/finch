// frontend/components/ui/insight-card.tsx — extracted from
// components/InsightCard.tsx (43 lines; PR 4). A card used in the
// Insights page: a tone-coloured circular icon, a serif title, and a
// muted body. The icon key + tone come from the `Insight` type in
// lib/insights; titles and bodies are i18n messages.
'use client';

import { useTranslations } from 'next-intl';
import { ArrowD, ArrowU, Calendar, Check, Doc, Fork, Sparkle, Tag } from '@/components/icons';
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

const ICON: Record<string, typeof ArrowD> = {
  'arrow-d': ArrowD,
  'arrow-u': ArrowU,
  doc: Doc,
  fork: Fork,
  sparkle: Sparkle,
  calendar: Calendar,
  tag: Tag,
  check: Check,
};

export function InsightCard({ insight }: InsightCardProps) {
  const t = useTranslations('insightCards');
  const Icon = ICON[insight.icon] ?? Doc;
  return (
    <div className="bg-card border-border mb-2.5 flex gap-3 rounded-xl border p-4">
      <div className={cn('flex size-8 shrink-0 items-center justify-center rounded-full', TONE[insight.tone])}>
        <Icon size={16} />
      </div>
      <div className="flex-1">
        <div className="mb-1 font-serif text-lg -tracking-[0.2px]">{t(insight.title.key, insight.title.params)}</div>
        <div className="text-secondary-foreground text-xs leading-relaxed">{t(insight.body.key, insight.body.params)}</div>
      </div>
    </div>
  );
}
