'use client';

import { toast } from 'sonner';
import { Icon } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
import { fmtNative } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { cn } from '@/lib/utils';

export default function PendingPage() {
  const pending = useFinanceStore((s) => s.pending);
  const confirmPending = useFinanceStore((s) => s.confirmPending);
  const cancelPending = useFinanceStore((s) => s.cancelPending);
  const confirmAllPending = useFinanceStore((s) => s.confirmAllPending);

  return (
    <MobilePage
      header={
        <ScreenHeader
          title="Pending"
          trailing={<IconButton icon="filter"/>}
        />
      }
    >
      <div className="px-5 pb-[120px]">
        <div className="px-1 pb-5">
          <SchemaChip label="status = pending"/>
          <div className="mt-1.5 font-serif text-[44px] leading-none tracking-[-1.6px]">
            {pending.length} <span className="italic text-muted-foreground">items</span>
          </div>
          <div className="mt-1.5 text-[13px] text-secondary-foreground">
            Confirm them to flow into your reports. Or cancel to ignore.
          </div>
        </div>

        {pending.length === 0 ? (
          <div className="text-muted-foreground py-16 text-center text-sm">
            All caught up — nothing pending.
          </div>
        ) : (
        <>
        <div className="mb-3.5 flex gap-2">
          <button
            type="button"
            onClick={() => { confirmAllPending(); toast.success('All items confirmed'); }}
            className="flex h-[38px] flex-1 items-center justify-center gap-1.5 rounded-[19px] bg-foreground text-xs font-medium text-background"
          >
            <Icon name="check" size={14}/>Confirm all
          </button>
        </div>

        {pending.map((p, i) => {
          const inc = p.amount > 0;
          const isFx = p.currency !== 'SGD';
          return (
            <div key={p.id} className="mb-2.5 rounded-[14px] border border-border bg-card p-4">
              <div className="flex items-start gap-3">
                <div className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-lg font-mono text-[11px] font-semibold text-white" style={{ background: `oklch(0.65 0.2 ${(i * 60) % 360})` }}>
                  {p.merchant.slice(0, 2).toUpperCase()}
                </div>
                <div className="flex-1">
                  <div className="flex items-baseline justify-between gap-2">
                    <div className="text-sm font-medium">{p.merchant}</div>
                    <div className={cn('font-sans text-[15px] font-medium tabular-nums', inc ? 'text-success' : 'text-foreground')}>
                      {fmtNative(p.amount, p.currency, { signed: true })}
                    </div>
                  </div>
                  <div className="mt-0.5 flex items-center gap-1.5 text-[11px] text-muted-foreground">
                    {p.account} · {p.date.slice(5).replace('-', '/')}
                    {isFx && <span className="font-mono text-[10px] text-warning">· FX</span>}
                  </div>
                  <div className="mt-2.5 flex items-center gap-2 rounded-lg bg-secondary px-2.5 py-2 text-xs text-secondary-foreground">
                    <Icon name="sparkle" size={13} className="text-primary" style={{ flexShrink: 0 }}/>{p.reason}
                  </div>
                </div>
              </div>
              <div className="mt-3 flex gap-1.5">
                <button
                  type="button"
                  onClick={() => { confirmPending(p.id); toast.success(`Confirmed ${p.merchant}`); }}
                  className="flex h-8 flex-1 items-center justify-center gap-1.5 rounded-[16px] bg-foreground text-xs font-medium text-background"
                >
                  <Icon name="check" size={12} stroke={2}/>Confirm
                </button>
                <button
                  type="button"
                  onClick={() => toast('Edit — coming soon')}
                  className="flex h-8 items-center gap-1.5 rounded-[16px] border border-border px-3.5 text-xs text-foreground"
                >
                  Edit
                </button>
                <button
                  type="button"
                  aria-label="Cancel"
                  onClick={() => { cancelPending(p.id); toast(`Dismissed ${p.merchant}`); }}
                  className="flex h-8 w-8 items-center justify-center rounded-[16px] border border-border text-muted-foreground"
                >
                  <Icon name="x" size={12}/>
                </button>
              </div>
            </div>
          );
        })}
        </>
        )}
      </div>
    </MobilePage>
  );
}
