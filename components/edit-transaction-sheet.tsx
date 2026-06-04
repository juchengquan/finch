'use client';

// The edit-transaction sheet. Mirrors `add-expense-sheet.tsx` — a single
// app-wide context, a right-side slider on desktop / bottom sheet on mobile.
// The body is `EditTransactionForm`, pre-populated from the row's current
// values; on submit it calls `useFinanceStore.updateTransaction` with a patch
// of only the changed fields, and the server-authoritative state flows back
// through the existing optimistic-update + re-projection pattern.

import { createContext, useCallback, useContext, useMemo, useState } from 'react';
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from '@/components/ui/sheet';
import { EditTransactionForm } from '@/components/edit-transaction-form';
import { useIsDesktop } from '@/components/use-is-desktop';
import { cn } from '@/lib/utils';

interface EditTransactionValue {
  /** Open the edit slider for the given transaction id. */
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
  // `open` drives the Sheet; `txId` is kept through the close animation so the
  // content doesn't blank out mid-transition (and so the next open with a
  // different id remounts the form with fresh state).
  const [open, setOpen] = useState(false);
  const [txId, setTxId] = useState<string | null>(null);
  const isDesktop = useIsDesktop();

  const openEditTransaction = useCallback((id: string) => {
    setTxId(id);
    setOpen(true);
  }, []);
  const close = useCallback(() => setOpen(false), []);

  const value = useMemo(() => ({ openEditTransaction, close }), [openEditTransaction, close]);

  return (
    <EditTransactionContext.Provider value={value}>
      {children}
      <Sheet open={open} onOpenChange={setOpen}>
        <SheetContent
          side={isDesktop ? 'right' : 'bottom'}
          className={cn('gap-0 p-0', isDesktop ? 'w-full sm:max-w-md' : 'h-[92dvh] rounded-t-2xl')}
        >
          <SheetHeader className="border-border border-b px-5 py-4">
            <SheetTitle className="font-serif text-xl italic">Edit</SheetTitle>
            <SheetDescription className="sr-only">
              Edit the selected transaction.
            </SheetDescription>
          </SheetHeader>
          <div className="min-h-0 flex-1 overflow-y-auto">
            {/* Only mount while open so each open starts from the row's current
             * values. The `key={txId}` forces a full remount when the user
             * opens a different row without closing the sheet first, which
             * re-initializes the form's state. */}
            {open && txId && (
              <EditTransactionForm key={txId} txId={txId} onSaved={close} />
            )}
          </div>
        </SheetContent>
      </Sheet>
    </EditTransactionContext.Provider>
  );
}
