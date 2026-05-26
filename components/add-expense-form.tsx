'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Icon } from '@/components/primitives';
import { MOCK } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { useLedger } from '@/components/ledger-provider';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { cn } from '@/lib/utils';

function Field({ icon, label, children }: { icon: string; label: string; children: React.ReactNode }) {
  return (
    <div className="border-border flex items-center gap-3.5 border-b px-5 py-3.5">
      <div className="bg-secondary text-secondary-foreground flex size-8 shrink-0 items-center justify-center rounded-2xl">
        <Icon name={icon} size={15} />
      </div>
      <div className="text-muted-foreground w-20 shrink-0 text-[11px] tracking-[0.4px] uppercase">
        {label}
      </div>
      <div className="flex flex-1 justify-end">{children}</div>
    </div>
  );
}

/**
 * The add-expense form, shared by the /add route (full page) and the
 * right-side add slider. `onSaved` fires after a successful add — the route
 * navigates to Activity, the slider closes itself.
 */
export function AddExpenseForm({
  onSaved,
  className,
}: {
  onSaved?: (id: string) => void;
  className?: string;
}) {
  const addTransaction = useFinanceStore((s) => s.addTransaction);
  const { activeId } = useLedger();

  const [amount, setAmount] = useState('');
  const [merchant, setMerchant] = useState('');
  const [category, setCategory] = useState('food');
  const [account, setAccount] = useState('cc');
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [note, setNote] = useState('');

  const save = () => {
    const value = parseFloat(amount);
    if (!value || Number.isNaN(value)) {
      toast.error('Enter an amount');
      return;
    }
    const id = addTransaction({
      merchant: merchant.trim() || 'Untitled',
      category,
      amount: -Math.abs(value),
      account,
      date,
      time: new Date().toTimeString().slice(0, 5),
      note: note.trim(),
      pending: false,
      ledgerId: activeId,
    });
    toast.success('Expense added', { description: `${merchant.trim() || 'Untitled'} · $${Math.abs(value).toFixed(2)}` });
    onSaved?.(id);
  };

  return (
    <div className={cn('flex flex-col gap-3.5 px-5 pt-4 pb-8', className)}>
      <div className="pt-5 text-center">
        <div className="text-muted-foreground mb-3.5 font-mono text-[10px] tracking-[1.5px]">AMOUNT</div>
        <div className="flex items-baseline justify-center gap-1">
          <span className="text-muted-foreground font-serif text-[40px]">$</span>
          <input
            value={amount}
            onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ''))}
            inputMode="decimal"
            aria-label="Amount" placeholder="0"
            autoFocus
            className="placeholder:text-muted-foreground w-[5ch] bg-transparent text-center font-serif text-[72px] leading-none font-normal -tracking-[3px] outline-none"
          />
        </div>
      </div>

      <div>
        <Field icon="tag" label="Merchant">
          <input
            value={merchant}
            onChange={(e) => setMerchant(e.target.value)}
            aria-label="Merchant" placeholder="e.g. Blue Bottle"
            className="placeholder:text-muted-foreground w-full bg-transparent text-right text-[15px] outline-none"
          />
        </Field>
        <Field icon="fork" label="Category">
          <Select value={category} onValueChange={setCategory}>
            <SelectTrigger size="sm" className="border-0 shadow-none">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {MOCK.categories.map((c) => (
                <SelectItem key={c.id} value={c.id}>
                  {c.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </Field>
        <Field icon="wallet" label="Account">
          <Select value={account} onValueChange={setAccount}>
            <SelectTrigger size="sm" className="border-0 shadow-none">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {MOCK.accounts.map((a) => (
                <SelectItem key={a.id} value={a.id}>
                  {a.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </Field>
        <Field icon="calendar" label="Date">
          <input
            type="date" aria-label="Date"
            value={date}
            onChange={(e) => setDate(e.target.value)}
            className="bg-transparent text-right text-[15px] outline-none"
          />
        </Field>
        <Field icon="edit" label="Note">
          <input
            value={note}
            onChange={(e) => setNote(e.target.value)}
            aria-label="Note" placeholder="Optional"
            className="placeholder:text-muted-foreground w-full bg-transparent text-right text-[15px] outline-none"
          />
        </Field>
      </div>

      <button
        type="button"
        onClick={save}
        className="bg-foreground text-background mt-2 flex h-[54px] cursor-pointer items-center justify-center rounded-[27px] text-base font-medium -tracking-[0.2px]"
      >
        Save expense
      </button>
    </div>
  );
}
