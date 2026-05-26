'use client';

import { Icon } from './primitives';
import { cn } from '@/lib/utils';

interface InsightCardProps {
  insight: {
    tone: 'pos' | 'warn' | 'neut';
    icon: string;
    title: string;
    body: string;
  };
}

const TONE: Record<string, string> = {
  pos: 'bg-success/10 text-success',
  warn: 'bg-warning/10 text-warning',
  neut: 'bg-primary/10 text-primary',
};

export function InsightCard({ insight }: InsightCardProps) {
  return (
    <div className="bg-card border-border mb-2.5 flex gap-3 rounded-xl border p-4">
      <div className={cn('flex size-8 shrink-0 items-center justify-center rounded-full', TONE[insight.tone])}>
        <Icon name={insight.icon} size={16} />
      </div>
      <div className="flex-1">
        <div className="mb-1 font-serif text-lg -tracking-[0.2px]">{insight.title}</div>
        <div className="text-secondary-foreground text-xs leading-relaxed">{insight.body}</div>
      </div>
    </div>
  );
}
