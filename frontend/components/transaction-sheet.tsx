'use client';

import { createContext, useCallback, useContext, useMemo, useState } from 'react';
import { Sheet, SheetContent, SheetTitle, SheetDescription } from '@/components/ui/sheet';
import { TransactionDetail, TransactionActionsMenu } from '@/components/transaction-detail';
import { useIsDesktop } from '@/components/use-is-desktop';
import { cn } from '@/lib/utils';

interface TransactionSheetValue {
  /** Open the detail slider for the given transaction id. */
  openTransaction: (id: string) => void;
  close: () => void;
}

const TransactionSheetContext = createContext<TransactionSheetValue | null>(null);

/**
 * Use anywhere a transaction row is clickable. Calling `openTransaction(id)`
 * opens a single app-wide detail panel: a bottom sheet on mobile, a right-side
 * slider on desktop.
 */
export function useTransactionSheet(): TransactionSheetValue {
  const ctx = useContext(TransactionSheetContext);
  if (!ctx) throw new Error('useTransactionSheet must be used within TransactionSheetProvider');
  return ctx;
}

export function TransactionSheetProvider({ children }: { children: React.ReactNode }) {
  // `open` drives the Sheet; `txId` is kept through the close animation so the
  // content doesn't blank out mid-transition.
  const [open, setOpen] = useState(false);
  const [txId, setTxId] = useState<string | null>(null);
  const isDesktop = useIsDesktop();

  const openTransaction = useCallback((id: string) => {
    setTxId(id);
    setOpen(true);
  }, []);
  const close = useCallback(() => setOpen(false), []);

  const value = useMemo(() => ({ openTransaction, close }), [openTransaction, close]);

  return (
    <TransactionSheetContext.Provider value={value}>
      {children}
      <Sheet open={open} onOpenChange={setOpen}>
        <SheetContent
          side={isDesktop ? 'right' : 'bottom'}
          className={cn(
            'gap-0 p-0',
            isDesktop ? 'w-full sm:max-w-md' : 'max-h-[85vh] rounded-t-2xl',
          )}
        >
          <SheetTitle className="sr-only">Transaction details</SheetTitle>
          <SheetDescription className="sr-only">
            View and edit the selected transaction.
          </SheetDescription>
          {txId && (
            <>
              <div className="flex items-center justify-between p-4 pr-12">
                <TransactionActionsMenu txId={txId} onDeleted={close} />
              </div>
              <div className="min-h-0 flex-1 overflow-y-auto px-5 pb-8">
                <TransactionDetail txId={txId} />
              </div>
            </>
          )}
        </SheetContent>
      </Sheet>
    </TransactionSheetContext.Provider>
  );
}
