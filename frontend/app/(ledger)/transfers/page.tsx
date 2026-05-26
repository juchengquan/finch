'use client';

import { Icon } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
import { LEDGER } from '@/lib/data';
import { cn } from '@/lib/utils';

export default function TransfersPage() {
  const tg = LEDGER.transferGroups[1];

  return (
    <MobilePage
      header={
        <ScreenHeader
          title="Transfers"
          trailing={<IconButton icon="dots"/>}
        />
      }
    >
      <div className="px-5 pb-[120px]">
        <div className="px-1 pb-[22px] text-center">
          <SchemaChip label="transfer_groups"/>
          <div className="mt-3.5 font-serif text-[22px] italic text-muted-foreground">You transferred</div>
          <div className="mt-1 font-serif text-[52px] tracking-[-1.8px]">
            S$80,000<span className="text-[28px] tracking-[-0.5px] text-muted-foreground">.00</span>
          </div>
          <div className="mt-0.5 font-serif text-[18px] italic text-secondary-foreground">
            → ¥422,728 received
          </div>
          <div className="mt-3.5 inline-flex items-center gap-2 rounded-[14px] bg-secondary px-3 py-1.5 font-mono text-[10px] tracking-[0.6px] text-secondary-foreground">
            <Icon name="check" size={12} className="text-success" stroke={2}/>
            RATE LOCKED @ 5.2841 · MON MAY 18
          </div>
        </div>

        <div className="mb-3 rounded-[14px] border border-border bg-card">
          <div className="flex items-center gap-3 border-b border-dashed border-border p-4">
            <div className="flex h-8 w-8 items-center justify-center rounded-[16px] bg-destructive/10 text-destructive">
              <Icon name="arrow-u" size={16} stroke={2}/>
            </div>
            <div className="flex-1">
              <div className="font-mono text-[9px] tracking-[1px] text-muted-foreground">FROM · PERSONAL LEDGER</div>
              <div className="mt-0.5 text-sm font-medium">{tg.fromAccount}</div>
            </div>
            <div className="font-sans text-base font-medium tabular-nums text-destructive">−S$80,000.00</div>
          </div>
          <div className="flex items-center gap-3 p-4">
            <div className="flex h-8 w-8 items-center justify-center rounded-[16px] bg-success/10 text-success">
              <Icon name="arrow-d" size={16} stroke={2}/>
            </div>
            <div className="flex-1">
              <div className="font-mono text-[9px] tracking-[1px] text-muted-foreground">TO · SIDE STUDIO LEDGER</div>
              <div className="mt-0.5 text-sm font-medium">{tg.toAccount}</div>
            </div>
            <div className="font-sans text-base font-medium tabular-nums text-success">+¥422,728</div>
          </div>
        </div>

        <div className="rounded-[14px] border border-border bg-card px-4 py-1">
          {[
            ['transfer_group_id', tg.id],
            ['amount_base',       'S$80,000.00 (locked)'],
            ['exchange_rate',     '5.2841 SGD→CNY'],
            ['from_currency',    'SGD'],
            ['to_currency',       'CNY'],
            ['notes',             tg.notes],
          ].map((r, i) => (
            <div key={r[0]} className={cn('flex items-center justify-between py-3 text-[13px]', i && 'border-t border-border')}>
              <span className="font-mono text-[11px] tracking-[0.4px] text-muted-foreground">{r[0]}</span>
              <span className="text-right">{r[1]}</span>
            </div>
          ))}
        </div>

        <div className="mt-3.5 px-1 text-[11px] leading-relaxed text-muted-foreground">
          The exchange rate is locked at import time. Both transactions share <span className="font-mono text-secondary-foreground">amount_base</span> so reports across ledgers stay consistent.
        </div>
      </div>
    </MobilePage>
  );
}
