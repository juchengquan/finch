'use client';

// The edit-transaction dialog. A single app-wide context opening a centered
// popout card (Dialog), matching the other entity dialogs (budgets, exchange
// rates, …). The body is `EditTransactionForm`, pre-populated from the row's
// current values; on submit it calls `useFinanceStore.updateTransaction` with
// a patch of only the changed fields, and the server-authoritative state flows
// back through the existing optimistic-update + re-projection pattern.

import { createContext, useCallback, useContext, useMemo, useState } from 'react';
import { useTranslations } from 'next-intl';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { EditTransactionForm } from '@/components/edit-transaction-form';

interface EditTransactionValue {
  /** Open the edit card for the given transaction id. */
  openEditTransaction: (id: string) => void;
  close: () => void;
}

const EditTransactionContext = createContext<EditTransactionValue | null>(null);

export function useEditTransaction(): EditTransactionValue {
  const ctx = useContext(EditTransactionContext);
  if (!ctx) throw new Error('useEditTransaction must be used within EditTransactionSheetProvider');
  return ctx;
}

export function EditTransactionSheetProvider({ children }: { children: React.ReactNode }) {
  // `open` drives the Dialog; `txId` is kept through the close animation so the
  // content doesn't blank out mid-transition (and so the next open with a
  // different id remounts the form with fresh state).
  const [open, setOpen] = useState(false);
  const [txId, setTxId] = useState<string | null>(null);
  const t = useTranslations('editTxnSheet');

  const openEditTransaction = useCallback((id: string) => {
    setTxId(id);
    setOpen(true);
  }, []);
  const close = useCallback(() => setOpen(false), []);

  const value = useMemo(() => ({ openEditTransaction, close }), [openEditTransaction, close]);

  return (
    <EditTransactionContext.Provider value={value}>
      {children}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="flex max-h-[88vh] flex-col gap-0 overflow-hidden p-0 sm:max-w-md">
          <DialogHeader className="border-border border-b px-5 py-4">
            <DialogTitle className="font-serif text-xl italic">{t('title')}</DialogTitle>
            <DialogDescription className="sr-only">{t('description')}</DialogDescription>
          </DialogHeader>
          <div className="min-h-0 flex-1 overflow-y-auto">
            {/* Only mount while open so each open starts from the row's current
             * values. The `key={txId}` forces a full remount when the user
             * opens a different row without closing the dialog first, which
             * re-initializes the form's state. */}
            {open && txId && (
              <EditTransactionForm key={txId} txId={txId} onSaved={close} />
            )}
          </div>
        </DialogContent>
      </Dialog>
    </EditTransactionContext.Provider>
  );
}
