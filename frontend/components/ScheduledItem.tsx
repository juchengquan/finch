'use client';

import { Money } from './primitives';
import { cn } from '@/lib/utils';

interface ScheduledItemProps {
  item: {
    day: number;
    month: string;
    label: string;
    amount: number;
    type: string;
    color: string;
  };
}

export function ScheduledItem({ item }: ScheduledItemProps) {
  return (
    <div className="bg-card border-border flex items-center gap-3.5 rounded-xl border p-3.5">
      <div className="w-11 shrink-0 text-center">
        <div className="text-muted-foreground font-mono text-[9px] tracking-wide uppercase">
          {item.month}
        </div>
        <div className="mt-0.5 font-serif text-[22px] leading-none -tracking-[0.4px]">{item.day}</div>
      </div>
      <div className="min-w-0 flex-1">
        <div className="text-sm font-medium">{item.label}</div>
        <div className="text-muted-foreground mt-0.5 flex items-center gap-1.5 text-[11px]">
          <span className="size-1.5 rounded-full" style={{ background: item.color }} />
          {item.type}
        </div>
      </div>
      <Money
        value={item.amount}
        className={cn('text-sm font-medium', item.amount > 0 ? 'text-success' : 'text-foreground')}
      />
    </div>
  );
}
