'use client';

import { Icon } from './primitives';
import { fmtMoneyShort } from '@/lib/data';
import { useCurrency } from '@/components/currency-provider';
import { cn } from '@/lib/utils';

interface CategoryRowProps {
  category: {
    id: string;
    name: string;
    icon: string;
    hue: number;
    spent: number;
    budget: number;
  };
}

export function CategoryRow({ category }: CategoryRowProps) {
  const { currency } = useCurrency();
  const cpct = (category.spent / category.budget) * 100;
  const over = cpct > 100;
  const remaining = category.budget - category.spent;

  return (
    <div className="bg-card border-border mb-2 flex cursor-pointer items-center gap-3.5 rounded-xl border p-3.5">
      <div
        className="text-foreground flex size-[38px] shrink-0 items-center justify-center rounded-full"
        style={{ background: `oklch(0.92 0.04 ${category.hue})` }}
      >
        <Icon name={category.icon} size={18} />
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-baseline justify-between">
          <div className="text-sm font-medium">{category.name}</div>
          <div className={cn('font-mono text-[11px]', over ? 'text-destructive' : 'text-foreground')}>
            {fmtMoneyShort(category.spent, currency)} / {fmtMoneyShort(category.budget, currency)}
          </div>
        </div>
        <div className="bg-secondary relative mt-1.5 h-[3px] overflow-hidden rounded-sm">
          <div
            className={cn('h-full', over ? 'bg-destructive' : 'bg-primary')}
            style={{ width: `${Math.min(cpct, 100)}%` }}
          />
        </div>
        <div className={cn('mt-1 text-[11px]', over ? 'text-destructive' : 'text-muted-foreground')}>
          {over
            ? `${fmtMoneyShort(-remaining, currency)} over`
            : `${fmtMoneyShort(remaining, currency)} left`}
        </div>
      </div>
    </div>
  );
}
