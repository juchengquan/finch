'use client';

import Link from 'next/link';
import { Icon } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
import { fmtNative } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';

export default function RecurringPage() {
  const recurring = useFinanceStore((s) => s.recurring);

  return (
    <MobilePage
      header={
        <ScreenHeader
          title="Recurring"
          trailing={<IconButton icon="dots"/>}
        />
      }
    >
      <div className="px-5 pb-[120px]">
        <div className="px-1 pb-5">
          <SchemaChip label="recurring_templates"/>
          <div className="mt-1.5 font-serif text-[44px] leading-none tracking-[-1.6px]">
            {recurring.length} <span className="italic text-muted-foreground">templates</span>
          </div>
          <div className="mt-1.5 text-[13px] text-secondary-foreground">
            Scheduled income & bills. Tap one to edit its splits.
          </div>
        </div>

        {recurring.map((t) => (
          <Link
            key={t.id}
            href={`/recurring/${t.id}`}
            className="mb-2.5 flex items-center gap-3 rounded-[14px] border border-border bg-card p-4"
          >
            <div className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-[16px] bg-secondary text-secondary-foreground">
              <Icon name="sync" size={16} stroke={2}/>
            </div>
            <div className="min-w-0 flex-1">
              <div className="flex items-baseline justify-between gap-2">
                <div className="truncate text-sm font-medium">{t.name}</div>
                <div className="font-sans text-[15px] font-medium tabular-nums">
                  {t.varies ? 'Varies' : fmtNative(t.amount ?? 0, 'SGD')}
                </div>
              </div>
              <div className="mt-0.5 flex items-center gap-1.5 text-[11px] text-muted-foreground">
                {t.frequency} · day {t.dayOfMonth} · next {t.nextRun}
                {t.autoPost ? (
                  <span className="rounded bg-secondary px-1.5 py-0.5 font-mono text-[9px] tracking-[0.6px] text-secondary-foreground">AUTO</span>
                ) : null}
              </div>
            </div>
          </Link>
        ))}
      </div>
    </MobilePage>
  );
}
