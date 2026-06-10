'use client';

import { createContext, useCallback, useContext, useMemo, useState } from 'react';
import { useTranslations } from 'next-intl';
import { Dialog, DialogContent, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { TransactionDetail } from '@/components/transaction-detail';

interface TransactionDialogValue {
  /** Open the detail card for the given transaction id. */
  openTransaction: (id: string) => void;
  close: () => void;
}

const TransactionDialogContext = createContext<TransactionDialogValue | null>(null);

/**
 * Use anywhere a transaction row is clickable. Calling `openTransaction(id)`
 * opens a single app-wide detail panel as a centered popout card (Dialog),
 * matching the other entity dialogs (budgets, exchange rates, …).
 */
export function useTransactionDialog(): TransactionDialogValue {
  const ctx = useContext(TransactionDialogContext);
  if (!ctx) throw new Error('useTransactionDialog must be used within TransactionDialogProvider');
  return ctx;
}

export function TransactionDialogProvider({ children }: { children: React.ReactNode }) {
  // `open` drives the Dialog; `txId` is kept through the close animation so the
  // content doesn't blank out mid-transition.
  const [open, setOpen] = useState(false);
  const [txId, setTxId] = useState<string | null>(null);
  const t = useTranslations('txnSheet');

  const openTransaction = useCallback((id: string) => {
    setTxId(id);
    setOpen(true);
  }, []);
  const close = useCallback(() => setOpen(false), []);

  const value = useMemo(() => ({ openTransaction, close }), [openTransaction, close]);

  return (
    <TransactionDialogContext.Provider value={value}>
      {children}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-h-[85vh] gap-0 overflow-y-auto p-0 sm:max-w-md">
          <DialogTitle className="sr-only">{t('title')}</DialogTitle>
          <DialogDescription className="sr-only">{t('description')}</DialogDescription>
          {txId && (
            <div className="px-5 pt-8 pb-8">
              <TransactionDetail txId={txId} onDeleted={close} />
            </div>
          )}
        </DialogContent>
      </Dialog>
    </TransactionDialogContext.Provider>
  );
}
