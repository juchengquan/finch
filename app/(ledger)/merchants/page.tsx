'use client';

import { Icon } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
import { LEDGER } from '@/lib/data';
import { cn } from '@/lib/utils';

export default function MerchantsPage() {
  return (
    <MobilePage
      header={
        <ScreenHeader
          title="Merchants"
          trailing={<IconButton icon="plus"/>}
        />
      }
    >
      <div className="px-5 pb-[120px]">
        <div className="px-1 pb-[18px]">
          <SchemaChip label="counterparties"/>
          <div className="mt-2 flex items-baseline gap-3.5">
            <div>
              <div className="font-serif text-[40px] leading-none tracking-[-1.4px]">{LEDGER.counterparties.length}</div>
              <div className="mt-1 font-mono text-[9px] tracking-[1px] text-muted-foreground">STANDARDISED</div>
            </div>
            <div className="h-8 w-px bg-border"/>
            <div>
              <div className="font-serif text-[40px] leading-none tracking-[-1.4px] text-warning">
                {LEDGER.counterparties.filter(c => !c.verified).length}
              </div>
              <div className="mt-1 font-mono text-[9px] tracking-[1px] text-muted-foreground">UNVERIFIED</div>
            </div>
          </div>
        </div>

        <div className="mb-3.5 flex h-[38px] items-center gap-2.5 rounded-[19px] bg-secondary px-3.5 text-[13px] text-muted-foreground">
          <Icon name="search" size={14}/>Search merchants & aliases…
        </div>

        <div className="flex flex-col">
          {LEDGER.counterparties.map((c, i) => (
            <div key={c.id} className={cn('flex items-start gap-3 py-3.5', i && 'border-t border-border')}>
              <div className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-lg font-mono text-[10px] font-semibold text-white" style={{ background: `oklch(0.65 0.2 ${c.hue})` }}>
                {c.name.slice(0, 2).toUpperCase()}
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-baseline justify-between gap-2">
                  <div className="flex items-center gap-2">
                    <div className="text-sm font-medium">{c.name}</div>
                    {!c.verified && (
                      <span className="rounded border border-warning/40 px-1.5 py-0.5 font-mono text-[9px] tracking-[0.6px] text-warning">UNVERIFIED</span>
                    )}
                  </div>
                  <div className="font-mono text-[11px] text-muted-foreground">{c.txCount}×</div>
                </div>
                <div className="mt-1 text-[11px] text-muted-foreground">
                  {c.category} <span className="mx-[5px]">·</span>
                  <span className="font-mono text-[10px] text-secondary-foreground">aliases:</span>
                </div>
                <div className="mt-1.5 flex flex-wrap gap-1">
                  {c.aliases.map((a) => (
                    <span key={a} className="rounded bg-secondary px-[7px] py-0.5 font-mono text-[10px] tracking-[0.2px] text-secondary-foreground">{a}</span>
                  ))}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </MobilePage>
  );
}
