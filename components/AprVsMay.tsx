'use client';

import { useMoney } from '@/components/use-money';
import { cn } from '@/lib/utils';

interface AprVsMayProps {
  data: {
    name: string;
    a: number;
    b: number;
    d: number;
  }[];
}

export function AprVsMay({ data }: AprVsMayProps) {
  const { short } = useMoney();

  return (
    <div>
      {data.map((c) => (
        <div key={c.name} className="border-border flex items-center border-t py-3">
          <div className="flex-1 text-sm">{c.name}</div>
          <div className="text-muted-foreground mr-3.5 font-mono text-[11px]">
            {short(c.a)} → {short(c.b)}
          </div>
          <div className={cn('font-mono text-xs font-semibold', c.d < 0 ? 'text-success' : 'text-destructive')}>
            {c.d > 0 ? '+' : ''}
            {c.d}%
          </div>
        </div>
      ))}
    </div>
  );
}
