'use client';

import { useEffect, useState } from 'react';
import { toast } from 'sonner';
import { Icon } from '@/components/primitives';
import { MOCK, CURRENCIES, convertAmount, fmtNative } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { useLedger } from '@/components/ledger-provider';
import { useMoney } from '@/components/use-money';
import { useDb } from '@/components/db-provider';
import { listAccounts } from '@/lib/db/queries/accounts';
import { listCategories } from '@/lib/db/queries/categories';
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
  const { activeId } = useLedger();
  const { base } = useMoney();
  const { exec, version } = useDb();

  const [amount, setAmount] = useState('');
  const [merchant, setMerchant] = useState('');
  const [category, setCategory] = useState('food');
  const [account, setAccount] = useState('cc');
  const [currency, setCurrency] = useState(base);
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
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

  // Category/account options come from the live DB, scoped to the active ledger.
  const [cats, setCats] = useState<Option[]>([]);
  const [accts, setAccts] = useState<Option[]>([]);
  useEffect(() => {
    if (!exec) return;
    let cancelled = false;
    Promise.all([listCategories(exec, activeId), listAccounts(exec, activeId)])
      .then(([c, a]) => {
        if (cancelled) return;
        const catOpts = c.map((x) => ({ id: x.id, name: x.name }));
        const acctOpts = a.map((x) => ({ id: x.id, name: x.name }));
        setCats(catOpts);
        setAccts(acctOpts);
        // Keep the current selection if still valid, else default to the first.
        setCategory((prev) => (catOpts.some((o) => o.id === prev) ? prev : catOpts[0]?.id ?? prev));
        setAccount((prev) => (acctOpts.some((o) => o.id === prev) ? prev : acctOpts[0]?.id ?? prev));
      })
      .catch((err) => console.error('Could not load add-expense options from DB', err));
    return () => {
      cancelled = true;
    };
  }, [exec, version, activeId]);

  type Mock = { id: string; name: string; ledger?: string };
  const categoryOptions = cats.length ? cats : mockOptions(MOCK.categories as Mock[], activeId);
  const accountOptions = accts.length ? accts : mockOptions(MOCK.accounts as Mock[], activeId);

  const save = () => {
    const value = parseFloat(amount);
    if (!value || Number.isNaN(value)) {
      toast.error('Enter an amount');
      return;
    }
    const native = -Math.abs(value);
    // Store the ledger-base amount (drives balances) alongside the original currency.
    const baseAmount =
      currency === base ? native : Math.round(convertAmount(native, currency, base) * 100) / 100;
    const id = addTransaction({
      merchant: merchant.trim() || 'Untitled',
      category,
      amount: baseAmount,
      currency,
      nativeAmount: native,
      account,
      date,
      time: new Date().toTimeString().slice(0, 5),
      note: note.trim(),
      pending: false,
      ledgerId: activeId,
    });
    toast.success('Expense added', {
      description: `${merchant.trim() || 'Untitled'} · ${fmtNative(Math.abs(value), currency)}`,
    });
    onSaved?.(id);
  };

  return (
    <div className={cn('flex flex-col gap-3.5 px-5 pt-4 pb-8', className)}>
      <div className="pt-5 text-center">
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
