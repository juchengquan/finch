'use client';

import { createContext, useCallback, useContext, useMemo, useState } from 'react';
import { useTranslations } from 'next-intl';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { AddExpenseForm } from '@/components/add-expense-form';

interface AddExpenseValue {
  /** Open the add-expense dialog. */
  openAddExpense: () => void;
  close: () => void;
}

const AddExpenseContext = createContext<AddExpenseValue | null>(null);

export function useAddExpense(): AddExpenseValue {
  const ctx = useContext(AddExpenseContext);
  if (!ctx) throw new Error('useAddExpense must be used within AddExpenseSheetProvider');
  return ctx;
}

export function AddExpenseSheetProvider({ children }: { children: React.ReactNode }) {
  const [open, setOpen] = useState(false);
  const tAdd = useTranslations('add');

  const openAddExpense = useCallback(() => setOpen(true), []);
  const close = useCallback(() => setOpen(false), []);

  const value = useMemo(() => ({ openAddExpense, close }), [openAddExpense, close]);

  return (
    <AddExpenseContext.Provider value={value}>
      {children}
      {/* Centered dialog, matching the other create flows (tag/merchant/
          category). Fixed height (with a small-screen cap) so the box doesn't
          resize as the form's content changes; the body scrolls inside. */}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="flex h-[720px] max-h-[90dvh] flex-col gap-0 overflow-hidden p-0 sm:max-w-md">
          <DialogHeader className="border-border border-b px-5 py-4">
            <DialogTitle className="font-serif text-xl italic">{tAdd('sheetTitle')}</DialogTitle>
            <DialogDescription className="sr-only">{tAdd('sheetDescription')}</DialogDescription>
          </DialogHeader>
          <div className="min-h-0 flex-1 overflow-y-auto">
            {/* Only mount while open so the form starts blank on each open. */}
            {open && <AddExpenseForm onSaved={close} />}
          </div>
        </DialogContent>
      </Dialog>
    </AddExpenseContext.Provider>
  );
}
