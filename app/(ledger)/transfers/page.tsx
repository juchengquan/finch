'use client';

import Link from 'next/link';
import { Icon } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
import { LEDGER, fmtNative } from '@/lib/data';
import { cn } from '@/lib/utils';

export default function TransfersPage() {
  return (
    <MobilePage
      header={
        <ScreenHeader
          title="Transfers"
          trailing={<IconButton icon="dots" aria-label="More actions" />}
        />
      }
    >
      <div className="px-5 pb-[120px]">
        <div className="px-1 pb-5">
          <SchemaChip label="transfer_groups"/>
          <div className="mt-1.5 font-serif text-[44px] leading-none tracking-[-1.6px]">
            {LEDGER.transferGroups.length} <span className="italic text-muted-foreground">transfers</span>
          </div>
          <div className="mt-1.5 text-[13px] text-secondary-foreground">
            Cross-account moves. Tap one to see the locked rate and both legs.
          </div>
        </div>

        {LEDGER.transferGroups.map((tg, i) => (
          <Link
            key={tg.id}
            href={`/transfers/${tg.id}`}
            className={cn('mb-2.5 flex items-center gap-3 rounded-[14px] border border-border bg-card p-4', i && '')}
          >
            <div className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-[16px] bg-secondary text-secondary-foreground">
              <Icon name="split" size={16} stroke={2}/>
            </div>
            <div className="min-w-0 flex-1">
              <div className="flex items-baseline justify-between gap-2">
                <div className="truncate text-sm font-medium">{tg.fromAccount} → {tg.toAccount}</div>
                <div className="font-sans text-[15px] font-medium tabular-nums">
                  {fmtNative(tg.amountBase, tg.fromCurrency)}
                </div>
              </div>
              <div className="mt-0.5 text-[11px] text-muted-foreground">
                {tg.date.slice(5).replace('-', '/')} · {tg.fromCurrency}→{tg.toCurrency}
              </div>
            </div>
          </Link>
        ))}
      </div>
    </MobilePage>
  );
}
