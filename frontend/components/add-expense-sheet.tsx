'use client';

import { createContext, useCallback, useContext, useMemo, useState } from 'react';
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

  const openAddExpense = useCallback(() => setOpen(true), []);
  const close = useCallback(() => setOpen(false), []);

  const value = useMemo(() => ({ openAddExpense, close }), [openAddExpense, close]);

  return (
    <AddExpenseContext.Provider value={value}>
      {children}
      {/* Centered dialog, matching the other create flows (tag/merchant/
          category). The form is tall, so the body scrolls within a viewport
          cap rather than growing the box. */}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="flex max-h-[90dvh] flex-col gap-0 overflow-hidden p-0 sm:max-w-md">
          <DialogHeader className="border-border border-b px-5 py-4">
            <DialogTitle className="font-serif text-xl italic">Add</DialogTitle>
            <DialogDescription className="sr-only">Record an expense, income, or transfer.</DialogDescription>
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
