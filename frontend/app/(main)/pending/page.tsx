'use client';

import { toast } from 'sonner';
import { Icon } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
import { acctById, catById } from '@/lib/data';
import { useLedger } from '@/components/ledger-provider';
import { useMoney } from '@/components/use-money';
import { useFinanceStore } from '@/lib/store';
import { cn } from '@/lib/utils';

export default function PendingPage() {
  const { activeId } = useLedger();
  const { fmt } = useMoney();
  const allTxns = useFinanceStore((s) => s.transactions);
  const confirmPending = useFinanceStore((s) => s.confirmPending);
  const cancelPending = useFinanceStore((s) => s.cancelPending);
  const confirmAllPending = useFinanceStore((s) => s.confirmAllPending);

  const pending = allTxns.filter((t) => t.pending && (t.ledgerId ?? 'personal') === activeId);

  return (
    <MobilePage
      header={
        <ScreenHeader
          title="Pending"
          trailing={<IconButton icon="filter" aria-label="Filter" />}
        />
      }
    >
      <div className="px-5 pb-[120px]">
        <div className="px-1 pb-5">
          <SchemaChip label="status = pending" />
          <div className="mt-1.5 font-serif text-[44px] leading-none tracking-[-1.6px]">
            {pending.length} <span className="text-muted-foreground italic">items</span>
          </div>
          <div className="text-secondary-foreground mt-1.5 text-[13px]">
            Confirm them to flow into your reports and balances. Or cancel to void.
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
                onClick={() => {
                  confirmAllPending();
                  toast.success('All items confirmed');
                }}
                className="bg-foreground text-background flex h-[38px] flex-1 items-center justify-center gap-1.5 rounded-[19px] text-xs font-medium"
              >
                <Icon name="check" size={14} />
                Confirm all
              </button>
            </div>

            {pending.map((p, i) => {
              const inc = p.amount > 0;
              const cat = catById(p.category);
              const isFx = p.currency && p.currency !== 'SGD' && p.currency !== 'USD';
              return (
                <div key={p.id} className="border-border bg-card mb-2.5 rounded-[14px] border p-4">
                  <div className="flex items-start gap-3">
                    <div
                      className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-lg font-mono text-[11px] font-semibold text-white"
                      style={{ background: `oklch(0.65 0.2 ${(i * 60) % 360})` }}
                    >
                      {p.merchant.slice(0, 2).toUpperCase()}
                    </div>
                    <div className="flex-1">
                      <div className="flex items-baseline justify-between gap-2">
                        <div className="text-sm font-medium">{p.merchant}</div>
                        <div className={cn('font-sans text-[15px] font-medium tabular-nums', inc ? 'text-success' : 'text-foreground')}>
                          {fmt(Math.abs(p.amount))}
                        </div>
                      </div>
                      <div className="text-muted-foreground mt-0.5 flex items-center gap-1.5 text-[11px]">
                        {acctById(p.account).name} · {p.date.replace(/-/g, '/')}{p.time ? ' ' + p.time.slice(0, 5) : ''} · {cat.name}
                        {isFx && <span className="text-warning font-mono text-[10px]">· FX</span>}
                      </div>
                      {p.note && (
                        <div className="bg-secondary text-secondary-foreground mt-2.5 flex items-center gap-2 rounded-lg px-2.5 py-2 text-xs">
                          <Icon name="sparkle" size={13} className="text-primary" style={{ flexShrink: 0 }} />
                          {p.note}
                        </div>
                      )}
                    </div>
                  </div>
                  <div className="mt-3 flex gap-1.5">
                    <button
                      type="button"
                      onClick={() => {
                        confirmPending(p.id);
                        toast.success(`Confirmed ${p.merchant}`);
                      }}
                      className="bg-foreground text-background flex h-8 flex-1 items-center justify-center gap-1.5 rounded-[16px] text-xs font-medium"
                    >
                      <Icon name="check" size={12} stroke={2} />
                      Confirm
                    </button>
                    <button
                      type="button"
                      aria-label="Cancel"
                      onClick={() => {
                        cancelPending(p.id);
                        toast(`Voided ${p.merchant}`);
                      }}
                      className="border-border text-muted-foreground flex h-8 w-8 items-center justify-center rounded-[16px] border"
                    >
                      <Icon name="x" size={12} />
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
