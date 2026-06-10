'use client';

import { toast } from 'sonner';
import { useTranslations } from 'next-intl';
import { Check, Filter } from '@/components/icons';
import { MobilePage } from '@/components/mobile-page';
import { SchemaChip } from '@/components/ui/schema-chip';
import { ScreenHeader } from '@/components/ui/screen-header';
import { IconButton } from '@/components/ui/icon-button';
import { PendingRow } from '@/components/pending-row';
import { useLedger } from '@/components/ledger-provider';
import { useFinanceStore } from '@/lib/store';

export default function PendingPage() {
  const { activeId } = useLedger();
  const allTxns = useFinanceStore((s) => s.transactions);
  const confirmAllPending = useFinanceStore((s) => s.confirmAllPending);
  const t = useTranslations('pending');

  const pending = allTxns.filter((tx) => tx.pending && (tx.ledgerId ?? 'personal') === activeId);

  return (
    <MobilePage
      header={
        <ScreenHeader
          title={t('title')}
          trailing={<IconButton icon={Filter} aria-label={t('filterAria')} />}
        />
      }
    >
      <div className="px-5 pb-[120px]">
        <div className="px-1 pb-5">
          <SchemaChip label="status = pending" />
          <div className="mt-1.5 font-serif text-[44px] leading-none tracking-[-1.6px]">
            {pending.length} <span className="text-muted-foreground italic">{t('items')}</span>
          </div>
          <div className="text-secondary-foreground mt-1.5 text-[13px]">
            {t('intro')}
          </div>
        </div>

        {pending.length === 0 ? (
          <div className="text-muted-foreground py-16 text-center text-sm">
            {t('empty')}
          </div>
        ) : (
          <>
            <div className="mb-3.5 flex gap-2">
              <button
                type="button"
                onClick={() => {
                  confirmAllPending();
                  toast.success(t('confirmedAllToast'));
                }}
                className="bg-foreground text-background flex h-[38px] flex-1 items-center justify-center gap-1.5 rounded-[19px] text-xs font-medium"
              >
                <Check size={14} />
                {t('confirmAll')}
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
