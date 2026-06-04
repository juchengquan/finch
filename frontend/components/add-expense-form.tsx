'use client';

import { useMemo, useState } from 'react';
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
import { suggestCategory } from '@/lib/select';
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
  const createTransfer = useFinanceStore((s) => s.createTransfer);
  const storeCats = useFinanceStore((s) => s.categories);
  const storeAccts = useFinanceStore((s) => s.accounts);
  const storeTxns = useFinanceStore((s) => s.transactions);
  const storeCps = useFinanceStore((s) => s.counterparties);
  const { activeId } = useLedger();
  const { base } = useMoney();

  const [type, setType] = useState<'expense' | 'income' | 'transfer'>('expense');
  const [amount, setAmount] = useState('');
  const [merchant, setMerchant] = useState('');
  const [category, setCategory] = useState('food');
  const [account, setAccount] = useState('cc');
  // Transfer-only: source/destination accounts and the received amount (used
  // only when the two accounts hold different currencies).
  const [fromAccount, setFromAccount] = useState('');
  const [toAccount, setToAccount] = useState('');
  const [received, setReceived] = useState('');
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 16));
  const [note, setNote] = useState('');

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
  // Default the transfer from/to to the first two accounts.
  if (accountOptions.length && !accountOptions.some((o) => o.id === fromAccount)) setFromAccount(accountOptions[0].id);
  if (accountOptions.length > 1 && !accountOptions.some((o) => o.id === toAccount)) setToAccount(accountOptions[1].id);

  // Local-heuristic category suggestion: if the typed merchant resolves to a
  // counterparty (or matches a past free-text description), surface the most-
  // common category from past confirmed expenses for that merchant. Quiet
  // when there's no signal. Only suggests for expenses (income/transfer have
  // their own conventions).
  const merchantTerm = merchant.trim().toLowerCase();
  const counterpartyId = useMemo(() => {
    if (!merchantTerm) return null;
    const hit = storeCps.find(
      (c) => c.ledgerId === activeId && c.name.trim().toLowerCase() === merchantTerm,
    );
    return hit ? hit.id : null;
  }, [storeCps, activeId, merchantTerm]);
  const suggestion = useMemo(() => {
    if (type !== 'expense') return null;
    return suggestCategory(storeTxns, activeId, merchant, counterpartyId);
  }, [storeTxns, activeId, merchant, counterpartyId, type]);
  const suggestedName = suggestion ? categoryOptions.find((c) => c.id === suggestion.categoryId)?.name : null;
  const alreadyApplied = suggestion ? suggestion.categoryId === category : false;

  const curOf = (id: string) => storeAccts.find((a) => a.id === id)?.currency ?? base;
  // The entry currency follows the selected account (an account holds one
  // currency); foreign spend is modelled via a dedicated fx account, not a
  // foreign entry here. Falls back to the ledger base pre-hydration. For a
  // transfer the top amount is denominated in the source account.
  const accountCurrency = type === 'transfer' ? curOf(fromAccount) : curOf(account);
  const currencySym = CURRENCIES[accountCurrency as keyof typeof CURRENCIES]?.sym ?? '$';
  const toCurrency = curOf(toAccount);
  const transferIsCrossCurrency = type === 'transfer' && !!accountCurrency && !!toCurrency && accountCurrency !== toCurrency;

  const saveTransfer = () => {
    const value = parseFloat(amount);
    if (!value || value <= 0) return void toast.error('Enter an amount');
    if (!fromAccount || !toAccount) return void toast.error('Pick both accounts');
    if (fromAccount === toAccount) return void toast.error('Pick two different accounts');
    // Cross-currency: the received amount is required so the actual bank
    // conversion is recorded rather than guessed from the mid-rate.
    let recv: number | undefined;
    if (transferIsCrossCurrency) {
      recv = parseFloat(received);
      if (!recv || recv <= 0) return void toast.error(`Enter the amount received in ${toCurrency}`);
    }
    createTransfer({
      fromAccountId: fromAccount,
      toAccountId: toAccount,
      fromAmount: value,
      toAmount: recv,
      date: date.slice(0, 10),
      time: date.slice(11, 16) || undefined,
      note: note.trim() || undefined,
    });
    const fromName = accountOptions.find((a) => a.id === fromAccount)?.name ?? 'account';
    const toName = accountOptions.find((a) => a.id === toAccount)?.name ?? 'account';
    toast.success('Transfer created', { description: `${fromName} → ${toName} · ${fmtNative(value, accountCurrency)}` });
    onSaved?.('');
  };

  const save = () => {
    if (type === 'transfer') return saveTransfer();
    const value = parseFloat(amount);
    if (!value || Number.isNaN(value)) {
      toast.error('Enter an amount');
      return;
    }
    const signed = type === 'income' ? Math.abs(value) : -Math.abs(value);
    // The entry is in the account's currency. Provide an optimistic ledger-base
    // figure for immediate display; the server re-derives + locks it on sync.
    const baseAmount =
      accountCurrency === base ? signed : Math.round(convertAmount(signed, accountCurrency, base) * 100) / 100;
    const id = addTransaction({
      merchant: merchant.trim() || (type === 'income' ? 'Income' : 'Untitled'),
      category,
      amount: baseAmount,
      currency: accountCurrency,
      nativeAmount: signed,
      account,
      date,
      time: new Date().toTimeString().slice(0, 5),
      note: note.trim(),
      pending: false,
      ledgerId: activeId,
    });
    toast.success(type === 'income' ? 'Income added' : 'Expense added', {
      description: `${merchant.trim() || (type === 'income' ? 'Income' : 'Untitled')} · ${fmtNative(Math.abs(value), accountCurrency)}`,
    });
    onSaved?.(id);
  };

  return (
    <div className={cn('flex flex-col gap-3.5 px-5 pt-4 pb-8', className)}>
      <div className="flex justify-center pt-5">
        <div role="tablist" aria-label="Transaction type" className="bg-secondary inline-flex rounded-full p-0.5 text-xs">
          {(['expense', 'income', 'transfer'] as const).map((t) => (
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
        <div className="text-muted-foreground mb-3.5 font-mono text-[10px] tracking-[1.5px]">
          {type === 'transfer' ? 'SENT' : 'AMOUNT'}
        </div>
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
        {type === 'transfer' ? (
          <>
            <Field icon="wallet" label="From">
              <Select value={fromAccount} onValueChange={setFromAccount}>
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
            <Field icon="arrow-r" label="To">
              <Select value={toAccount} onValueChange={setToAccount}>
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
            {transferIsCrossCurrency && (
              <>
                <Field icon="coins" label={`Recv ${toCurrency}`}>
                  <input
                    value={received}
                    onChange={(e) => setReceived(e.target.value.replace(/[^0-9.]/g, ''))}
                    inputMode="decimal"
                    aria-label="Received amount"
                    placeholder={`amount in ${toCurrency}`}
                    className="placeholder:text-muted-foreground w-full bg-transparent text-right text-[15px] outline-none"
                  />
                </Field>
                {(() => {
                  const sent = parseFloat(amount);
                  const got = parseFloat(received);
                  if (!sent || !got) return null;
                  return (
                    <div className="text-muted-foreground px-5 py-2 text-right text-[11px]">
                      Effective rate: {(got / sent).toFixed(6)} {toCurrency} per {accountCurrency}
                    </div>
                  );
                })()}
              </>
            )}
          </>
        ) : (
          <>
            <Field icon="coins" label="Currency">
              <span className="text-muted-foreground text-[15px]" title="Follows the selected account">{accountCurrency}</span>
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
            {type === 'expense' && suggestion && suggestedName && !alreadyApplied && (
              <div className="flex justify-end px-5 py-1.5">
                <button
                  type="button"
                  onClick={() => setCategory(suggestion.categoryId)}
                  className="bg-secondary text-secondary-foreground hover:bg-secondary/80 inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11px] transition-colors"
                  aria-label={`Use suggested category ${suggestedName}`}
                >
                  <Icon name="sync" size={10} />
                  <span>Suggested: <span className="font-medium">{suggestedName}</span></span>
                  <span className="text-muted-foreground">· {suggestion.count}×</span>
                </button>
              </div>
            )}
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
          </>
        )}
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
        {type === 'transfer' ? 'Save transfer' : type === 'income' ? 'Save income' : 'Save expense'}
      </button>
    </div>
  );
}
