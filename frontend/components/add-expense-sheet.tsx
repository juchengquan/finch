'use client';

import { createContext, useCallback, useContext, useMemo, useState } from 'react';
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from '@/components/ui/sheet';
import { AddExpenseForm } from '@/components/add-expense-form';
import { useIsDesktop } from '@/components/use-is-desktop';
import { cn } from '@/lib/utils';

interface AddExpenseValue {
  /** Open the add-expense slider. */
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
  const isDesktop = useIsDesktop();

  const openAddExpense = useCallback(() => setOpen(true), []);
  const close = useCallback(() => setOpen(false), []);

  const value = useMemo(() => ({ openAddExpense, close }), [openAddExpense, close]);

  return (
    <AddExpenseContext.Provider value={value}>
      {children}
      <Sheet open={open} onOpenChange={setOpen}>
        {/* Right slider on desktop, bottom sheet on mobile. */}
        <SheetContent
          side={isDesktop ? 'right' : 'bottom'}
          className={cn('gap-0 p-0', isDesktop ? 'w-full sm:max-w-md' : 'h-[92dvh] rounded-t-2xl')}
        >
          <SheetHeader className="border-border border-b px-5 py-4">
            <SheetTitle className="font-serif text-xl italic">Add expense</SheetTitle>
            <SheetDescription className="sr-only">Record a new expense.</SheetDescription>
          </SheetHeader>
          <div className="min-h-0 flex-1 overflow-y-auto">
            {/* Only mount while open so the form starts blank on each open. */}
            {open && <AddExpenseForm onSaved={close} />}
          </div>
        </SheetContent>
      </Sheet>
    </AddExpenseContext.Provider>
  );
}
