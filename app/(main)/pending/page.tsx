'use client';

import { toast } from 'sonner';
import { Icon } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
import { PendingRow } from '@/components/pending-row';
import { useLedger } from '@/components/ledger-provider';
import { useFinanceStore } from '@/lib/store';

export default function PendingPage() {
  const { activeId } = useLedger();
  const allTxns = useFinanceStore((s) => s.transactions);
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

            {pending.map((p) => (
              <PendingRow key={p.id} tx={p} />
            ))}
          </>
        )}
      </div>
    </MobilePage>
  );
}
