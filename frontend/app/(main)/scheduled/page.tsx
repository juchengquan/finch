'use client';

import { useState } from 'react';
import { Money, Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { SCHEDULED_ITEMS } from '@/lib/data';
import { ScheduledItem } from '@/components/ScheduledItem';

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const WEEKDAYS = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
const MONTH_NAMES = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

export default function ScheduledPage() {
  const [view, setView] = useState({ y: 2026, m: 5 }); // June 2026

  const totalOutgoing = SCHEDULED_ITEMS.filter((i) => i.amount < 0).reduce((s, i) => s + i.amount, 0);
  const totalIncoming = SCHEDULED_ITEMS.filter((i) => i.amount > 0).reduce((s, i) => s + i.amount, 0);
  const netTotal = totalIncoming + totalOutgoing;

  const firstDow = new Date(view.y, view.m, 1).getDay();
  const daysInMonth = new Date(view.y, view.m + 1, 0).getDate();

  const dotsByDay = new Map<number, string[]>();
  for (const it of SCHEDULED_ITEMS) {
    if (MONTHS.indexOf(it.month) !== view.m) continue;
    const arr = dotsByDay.get(it.day) ?? [];
    arr.push(it.color);
    dotsByDay.set(it.day, arr);
  }

  const shift = (delta: number) =>
    setView((v) => {
      const d = new Date(v.y, v.m + delta, 1);
      return { y: d.getFullYear(), m: d.getMonth() };
    });

  return (
    <MobilePage
      header={<ScreenHeader title="Scheduled" trailing={<IconButton icon="search" />} />}
    >
      <div className="px-5 pb-[22px]">
        <PageHeader
          label="Next 30 days"
          value={<Money value={netTotal} mono={false} className="font-serif" />}
          sublabel={
            <span className="text-success">
              +<Money value={totalIncoming} /> incoming
            </span>
          }
        />
      </div>

      <div className="md:grid md:grid-cols-[1.6fr_1fr] md:items-start md:gap-6 md:px-8">
      <div className="px-5 pb-5 md:px-0">
        <div className="bg-card border-border rounded-xl border p-4 md:p-5">
          <div className="mb-3 flex items-center justify-between">
            <button
              type="button"
              aria-label="Previous month"
              onClick={() => shift(-1)}
              className="text-muted-foreground hover:text-foreground"
            >
              <Icon name="chev-l" size={16} />
            </button>
            <div className="font-serif text-base italic">
              {MONTH_NAMES[view.m]} {view.y}
            </div>
            <button
              type="button"
              aria-label="Next month"
              onClick={() => shift(1)}
              className="text-muted-foreground hover:text-foreground"
            >
              <Icon name="chev" size={16} />
            </button>
          </div>
          <div className="text-muted-foreground mb-1 grid grid-cols-7 text-center font-mono text-[10px]">
            {WEEKDAYS.map((d, i) => (
              <div key={i}>{d}</div>
            ))}
          </div>
          <div className="grid grid-cols-7 gap-y-1">
            {Array.from({ length: firstDow }).map((_, i) => (
              <div key={`b${i}`} />
            ))}
            {Array.from({ length: daysInMonth }).map((_, i) => {
              const day = i + 1;
              const dots = dotsByDay.get(day);
              return (
                <div key={day} className="flex flex-col items-center gap-1 py-1 md:py-2.5">
                  <span className="text-[13px] tabular-nums">{day}</span>
                  <span className="flex h-1.5 gap-0.5">
                    {dots?.slice(0, 3).map((c, j) => (
                      <span key={j} className="size-1.5 rounded-full" style={{ background: c }} />
                    ))}
                  </span>
                </div>
              );
            })}
          </div>
        </div>
      </div>

      <div className="flex flex-col gap-2.5 px-5 pb-[120px] md:px-0 md:pb-12">
        <div className="text-muted-foreground px-1 font-mono text-[10px] tracking-wider uppercase">
          Upcoming
        </div>
        {SCHEDULED_ITEMS.map((item, i) => (
          <ScheduledItem key={i} item={item} />
        ))}
      </div>
      </div>
    </MobilePage>
  );
}
