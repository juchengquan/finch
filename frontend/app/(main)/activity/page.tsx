'use client';

import { useState } from 'react';
import { Money, MerchantGlyph, Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton } from '@/components/MobileComponents';
import { MOCK, catById, acctById } from '@/lib/data';
import { cn } from '@/lib/utils';

const FILTERS = [
  { id: 'all', label: 'All' },
  { id: 'out', label: 'Out' },
  { id: 'in', label: 'In' },
] as const;

type Filter = (typeof FILTERS)[number]['id'];

function dayLabel(date: string) {
  return new Date(`${date}T00:00`).toLocaleDateString('en-US', {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
  });
}

export default function ActivityPage() {
  const [filter, setFilter] = useState<Filter>('all');
  const [query, setQuery] = useState('');

  const txns = MOCK.transactions.filter((t) => {
    if (filter === 'in' && t.amount <= 0) return false;
    if (filter === 'out' && t.amount >= 0) return false;
    if (query && !t.merchant.toLowerCase().includes(query.toLowerCase())) return false;
    return true;
  });

  const groups: { date: string; items: typeof txns }[] = [];
  for (const t of txns) {
    const last = groups[groups.length - 1];
    if (last && last.date === t.date) last.items.push(t);
    else groups.push({ date: t.date, items: [t] });
  }

  return (
    <MobilePage
      header={<ScreenHeader title="Activity" trailing={<IconButton icon="search" aria-label="Search" />} />}
    >
      <div className="px-5 pb-[120px]">
        <div className="bg-secondary mb-3 flex h-9 items-center gap-2 rounded-full px-3.5">
          <Icon name="search" size={14} className="text-muted-foreground" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search transactions"
            className="placeholder:text-muted-foreground w-full bg-transparent text-[13px] outline-none"
          />
        </div>

        <div className="bg-secondary mb-4 flex gap-1 rounded-full p-1">
          {FILTERS.map((f) => (
            <button
              key={f.id}
              type="button"
              onClick={() => setFilter(f.id)}
              className={cn(
                'h-7 flex-1 rounded-full text-xs font-medium transition-colors',
                filter === f.id ? 'bg-background text-foreground shadow-sm' : 'text-muted-foreground',
              )}
            >
              {f.label}
            </button>
          ))}
        </div>

        {groups.length === 0 && (
          <div className="text-muted-foreground py-10 text-center text-sm">No transactions</div>
        )}

        {groups.map((group) => (
          <div key={group.date} className="mb-4">
            <div className="text-muted-foreground mb-1 px-1 font-mono text-[10px] tracking-wider uppercase">
              {dayLabel(group.date)}
            </div>
            <div className="bg-card border-border overflow-hidden rounded-xl border">
              {group.items.map((t, i) => {
                const cat = catById(t.category);
                const inc = t.amount > 0;
                return (
                  <div
                    key={t.id}
                    className={cn('flex items-center gap-3 p-3.5', i && 'border-border border-t')}
                  >
                    <MerchantGlyph name={t.merchant} hue={cat.hue} size={36} />
                    <div className="min-w-0 flex-1">
                      <div className="truncate text-sm font-medium">{t.merchant}</div>
                      <div className="text-muted-foreground mt-0.5 truncate text-[11px]">
                        {cat.name} · {acctById(t.account).name}
                        {t.pending && <span className="text-warning"> · pending</span>}
                      </div>
                    </div>
                    <Money
                      value={t.amount}
                      signed={inc}
                      className={cn('text-sm font-medium', inc ? 'text-success' : 'text-foreground')}
                    />
                  </div>
                );
              })}
            </div>
          </div>
        ))}
      </div>
    </MobilePage>
  );
}
