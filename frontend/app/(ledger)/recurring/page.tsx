'use client';

import { Icon, StackedBar } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
import { LEDGER } from '@/lib/data';

export default function RecurringPage() {
  const t = LEDGER.recurringTemplates[0];

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
        <div className="px-1 pb-[22px]">
          <SchemaChip label="recurring_templates"/>
          <div className="mt-2.5 font-serif text-[36px] leading-[1.1] tracking-[-0.8px]">
            <span className="italic text-muted-foreground">Every 25th, you receive</span><br/>
            <span className="text-[44px]">S$5,800.00</span>
          </div>
          <div className="mt-2 text-xs text-muted-foreground">
            from <b className="text-secondary-foreground">Acme</b> — next on May 25 · awaits your confirmation
          </div>
        </div>

        <div className="mb-2 flex items-baseline justify-between px-1">
          <div className="font-serif text-[20px] italic tracking-[-0.2px]">Splits</div>
          <SchemaChip label="recurring_splits"/>
        </div>
        <div className="px-1 pb-2.5 text-xs text-muted-foreground">
          Salary is split across accounts. Total must equal 100%.
        </div>

        <div className="mb-2.5 rounded-[14px] border border-border bg-card p-3.5">
          <StackedBar
            slices={(t.splits || []).map((s, i) => ({ value: s.pct || 0, color: i === 0 ? 'var(--primary)' : i === 1 ? 'var(--warning)' : 'var(--success)' }))}
            width={310} height={12} radius={6}/>
          <div className="mt-2.5 flex justify-between font-mono text-[10px] text-muted-foreground">
            <span>0%</span><span>50%</span><span>100%</span>
          </div>
        </div>

        {(t.splits || []).map((s, i) => {
          const dot = i === 0 ? 'var(--primary)' : i === 1 ? 'var(--warning)' : 'var(--success)';
          const amount = 5800 * s.pct / 100;
          return (
            <div key={i} className="mb-2 rounded-[14px] border border-border bg-card p-3.5">
              <div className="flex items-center gap-3">
                <div className="h-9 w-2 rounded" style={{ background: dot }}/>
                <div className="min-w-0 flex-1">
                  <div className="flex items-baseline justify-between">
                    <div className="text-sm font-medium">{s.account}</div>
                    <div className="font-sans text-sm font-medium">S${amount.toLocaleString(undefined, { maximumFractionDigits: 0 })}</div>
                  </div>
                  <div className="mt-0.5 text-[11px] text-muted-foreground">{s.label} · <span className="font-mono text-[10px]">amount_pct = {s.pct}</span></div>
                </div>
              </div>
            </div>
          );
        })}

        <div className="mt-1 flex h-11 items-center justify-center gap-2 rounded-xl border border-dashed border-border text-xs text-muted-foreground">
          <Icon name="plus" size={14}/>Add split rule
        </div>

        <div className="px-0 pb-2 pt-6">
          <div className="flex h-[50px] items-center justify-center rounded-[25px] bg-foreground text-[15px] font-medium text-background">
            Save template
          </div>
        </div>
      </div>
    </MobilePage>
  );
}
