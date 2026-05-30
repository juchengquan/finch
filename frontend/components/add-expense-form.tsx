'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Icon } from '@/components/primitives';
import { MOCK, CURRENCIES, convertAmount, fmtNative } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { useLedger } from '@/components/ledger-provider';
import { useMoney } from '@/components/use-money';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { cn } from '@/lib/utils';

type Option = { id: string; name: string };

// Scoped fallback used until the query DB is ready (MOCK isn't ledger-scoped).
function mockOptions(list: { id: string; name: string; ledger?: string }[], ledgerId: string): Option[] {
  return list
    .filter((x) => (x.ledger ?? 'personal') === ledgerId)
    .map((x) => ({ id: x.id, name: x.name }));
}

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
  const storeCats = useFinanceStore((s) => s.categories);
  const storeAccts = useFinanceStore((s) => s.accounts);
  const { activeId } = useLedger();
  const { base } = useMoney();

  const [type, setType] = useState<'expense' | 'income'>('expense');
  const [amount, setAmount] = useState('');
  const [merchant, setMerchant] = useState('');
  const [category, setCategory] = useState('food');
  const [account, setAccount] = useState('cc');
  const [currency, setCurrency] = useState(base);
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 16));
  const [note, setNote] = useState('');

  // Default the entry currency to the active ledger's base, and follow a ledger
  // switch — adjusting state during render (the React-recommended alternative to
  // a setState-in-effect) so the picker resets when `base` changes.
  const [prevBase, setPrevBase] = useState(base);
  if (prevBase !== base) {
    setPrevBase(base);
    setCurrency(base);
  }

  const currencyOptions = Object.keys(CURRENCIES);
  const currencySym = CURRENCIES[currency as keyof typeof CURRENCIES]?.sym ?? '$';

  // Category/account options come from the projected store, scoped to the active
  // ledger; fall back to MOCK until the store is hydrated.
  const cats: Option[] = storeCats.filter((c) => c.ledgerId === activeId).map((x) => ({ id: x.id, name: x.name }));
  const accts: Option[] = storeAccts.filter((a) => a.ledgerId === activeId).map((x) => ({ id: x.id, name: x.name }));

  type Mock = { id: string; name: string; ledger?: string };
  const categoryOptions = cats.length ? cats : mockOptions(MOCK.categories as Mock[], activeId);
  const accountOptions = accts.length ? accts : mockOptions(MOCK.accounts as Mock[], activeId);

  // Keep the current selection valid as options load / the ledger switches.
  if (categoryOptions.length && !categoryOptions.some((o) => o.id === category)) setCategory(categoryOptions[0].id);
  if (accountOptions.length && !accountOptions.some((o) => o.id === account)) setAccount(accountOptions[0].id);

  const save = () => {
    const value = parseFloat(amount);
    if (!value || Number.isNaN(value)) {
      toast.error('Enter an amount');
      return;
    }
    const signed = type === 'income' ? Math.abs(value) : -Math.abs(value);
    // Store the ledger-base amount (drives balances) alongside the original currency.
    const baseAmount =
      currency === base ? signed : Math.round(convertAmount(signed, currency, base) * 100) / 100;
    const id = addTransaction({
      merchant: merchant.trim() || (type === 'income' ? 'Income' : 'Untitled'),
      category,
      amount: baseAmount,
      currency,
      nativeAmount: signed,
      account,
      date,
      time: new Date().toTimeString().slice(0, 5),
      note: note.trim(),
      pending: false,
      ledgerId: activeId,
    });
    toast.success(type === 'income' ? 'Income added' : 'Expense added', {
      description: `${merchant.trim() || (type === 'income' ? 'Income' : 'Untitled')} · ${fmtNative(Math.abs(value), currency)}`,
    });
    onSaved?.(id);
  };

  return (
    <div className={cn('flex flex-col gap-3.5 px-5 pt-4 pb-8', className)}>
      <div className="flex justify-center pt-5">
        <div role="tablist" aria-label="Transaction type" className="bg-secondary inline-flex rounded-full p-0.5 text-xs">
          {(['expense', 'income'] as const).map((t) => (
            <button
              key={t}
              type="button"
              role="tab"
              aria-selected={type === t}
              onClick={() => setType(t)}
              className={cn('rounded-full px-4 py-1.5 capitalize transition-colors', type === t ? 'bg-background text-foreground shadow-sm' : 'text-muted-foreground')}
            >
              {t}
            </button>
          ))}
        </div>
      </div>
      <div className="text-center">
        <div className="text-muted-foreground mb-3.5 font-mono text-[10px] tracking-[1.5px]">AMOUNT</div>
        <div className="flex items-baseline justify-center gap-1">
          <span className="text-muted-foreground font-serif text-[40px]">{currencySym}</span>
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
        <Field icon="coins" label="Currency">
          <Select value={currency} onValueChange={setCurrency}>
            <SelectTrigger size="sm" className="border-0 shadow-none">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {currencyOptions.map((c) => (
                <SelectItem key={c} value={c}>
                  {c}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </Field>
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
              {categoryOptions.map((c) => (
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
              {accountOptions.map((a) => (
                <SelectItem key={a.id} value={a.id}>
                  {a.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </Field>
        <Field icon="calendar" label="Date">
          <input
            type="datetime-local" aria-label="Date"
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
        {type === 'income' ? 'Save income' : 'Save expense'}
      </button>
    </div>
  );
}
