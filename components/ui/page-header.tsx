// frontend/components/ui/page-header.tsx — extracted from
// MobileComponents.tsx (was 26 lines; PR 4). Page chrome: a small
// label, a large serif value, an optional sublabel, and an optional
// trend chip. Border-top variant separates the header from the
// content above it. The trend prop's `icon` is a string key resolved
// through ICON_FOR; no caller currently passes a trend, so the
// resolution is kept for the next time trend is wired up.
'use client';

import { Plus } from '@/components/icons';
import { cn } from '@/lib/utils';
import type { LucideIcon } from 'lucide-react';

const ICON_FOR: Record<string, LucideIcon> = {
  plus: Plus,
};

interface PageHeaderProps {
  label: string;
  value: React.ReactNode;
  sublabel?: React.ReactNode;
  trend?: { text: string; icon: string; color: 'pos' | 'neg' | 'warn' };
  borderTop?: boolean;
}

const TREND_CLASS: Record<string, string> = {
  pos: 'bg-success/10 text-success',
  neg: 'bg-destructive/10 text-destructive',
  warn: 'bg-warning/10 text-warning',
};

export function PageHeader({ label, value, sublabel, trend, borderTop = false }: PageHeaderProps) {
  // trend.icon is a string from PageHeader callers; today no caller passes
  // a trend, so the chip below is dead. Keep the resolution here for the
  // next time trend is wired up.
  const TrendIcon = trend ? ICON_FOR[trend.icon] ?? Plus : null;
  return (
    <div className={cn('px-5 pb-[22px]', borderTop && 'border-border border-t pt-[18px]')}>
      <div className="text-muted-foreground text-[10px] tracking-wider uppercase">{label}</div>
      <div className="text-foreground mt-1.5 font-serif text-5xl leading-none font-normal -tracking-[2px]">
        {value}
      </div>
      {sublabel && <div className="text-muted-foreground mt-1 text-xs">{sublabel}</div>}
      {trend && (
        <div
          className={cn(
            'mt-2 inline-flex items-center gap-1.5 rounded-[10px] px-2.5 py-1 text-[11px] font-medium',
            TREND_CLASS[trend.color],
          )}
        >
          {TrendIcon && <TrendIcon size={12} />}
          {trend.text}
        </div>
      )}
    </div>
  );
}
