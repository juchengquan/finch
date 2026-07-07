'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { useTranslations } from 'next-intl';
import {
  ArrowR,
  Banknote,
  Bell,
  Calendar,
  Chev,
  Coins,
  Fork,
  Sync,
  Tag,
  Wallet,
} from '@/components/icons';
import { MOCK, CURRENCIES, convertAmount } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { useLedger } from '@/components/ledger-provider';
import { useMoney } from '@/components/use-money';
import { useMerchantPicker } from '@/components/merchant-picker-dialog';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { suggestCategory, recentExpenses, findDuplicate } from '@/lib/select';
import { categoryPath } from '@/lib/db/domain/categories/queries';
import { cn } from '@/lib/utils';

type Option = { id: string; name: string };

// Field.icon is a string short-name; resolve to the typed lucide component
// so the form rows can be declared inline. Extend as new field types appear.
const FIELD_ICON: Record<string, typeof Wallet> = {
  banknote: Banknote,
  wallet: Wallet,
  'arrow-r': ArrowR,
  coins: Coins,
  tag: Tag,
  fork: Fork,
  calendar: Calendar,
};

// Scoped fallback used until the query DB is ready (MOCK isn't ledger-scoped).
function mockOptions(list: { id: string; name: string; ledger?: string }[], ledgerId: string): Option[] {
  return list
    .filter((x) => (x.ledger ?? 'personal') === ledgerId)
    .map((x) => ({ id: x.id, name: x.name }));
}

/** Current date+time as a local `datetime-local` value (YYYY-MM-DDTHH:mm).
 *  `toISOString()` alone would be UTC and show a wall-clock several hours off. */
function localDateTimeNow(): string {
  const d = new Date();
  d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
  return d.toISOString().slice(0, 16);
}

function Field({ icon, label, children }: { icon: string; label: string; children: React.ReactNode }) {
  const Glyph = FIELD_ICON[icon] ?? Wallet;
  return (
    <div className="border-border flex items-center gap-3.5 border-b px-5 py-3.5">
      <div className="bg-secondary text-secondary-foreground flex size-8 shrink-0 items-center justify-center rounded-2xl">
        <Glyph size={15} />
      </div>
      <div className="text-muted-foreground w-20 shrink-0 text-[11px] tracking-[0.4px] uppercase">
        {label}
      </div>
      <div className="flex flex-1 justify-end">{children}</div>
    </div>
  );
}

/**
 * The add-expense form, rendered inside the add dialog (see
 * add-expense-sheet.tsx). `onSaved` fires after a successful add — the
 * dialog closes itself.
 */
export function AddExpenseForm({
  onSaved,
  className,
}: {
  onSaved?: (id: string) => void;
  className?: string;
}) {
  const t = useTranslations('add');
  const addTransaction = useFinanceStore((s) => s.addTransaction);
  const createTransfer = useFinanceStore((s) => s.createTransfer);
  const createCounterparty = useFinanceStore((s) => s.createCounterparty);
  const storeCats = useFinanceStore((s) => s.categories);
  const storeAccts = useFinanceStore((s) => s.accounts);
  const storeTxns = useFinanceStore((s) => s.transactions);
  const storeCps = useFinanceStore((s) => s.counterparties);
  const { activeId } = useLedger();
  const { base, native } = useMoney();
  const { openMerchantPicker } = useMerchantPicker();

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
  const [date, setDate] = useState(localDateTimeNow);
  const [note, setNote] = useState('');

  // Category/account options come from the projected store, scoped to the active
  // ledger; fall back to MOCK until the store is hydrated. Category labels
  // render as `Parent › Child › Leaf` so depth-3 picks are unambiguous
  // (CATEGORIES_LEVEL3_PLAN §5.1); siblings cluster via the path sort.
  const ledgerCats = storeCats.filter((c) => c.ledgerId === activeId);
  const ledgerCatById = new Map(ledgerCats.map((c) => [c.id, c]));
  const cats: Option[] = ledgerCats
    .map((c) => ({ id: c.id, name: categoryPath(c, ledgerCatById) }))
    .sort((a, b) => a.name.localeCompare(b.name));
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

  // Recent confirmed expenses (deduplicated by merchant+amount+account+category)
  // — surfaced as one-tap chips so daily-habit purchases (coffee, lunch,
  // parking) fill the form in a single tap. Capped at 5 to keep the row
  // compact; sorted most-recent-first by the selector.
  const recents = useMemo(
    () => (type === 'expense' ? recentExpenses(storeTxns, activeId, 5) : []),
    [storeTxns, activeId, type],
  );

  const applyRecent = (r: ReturnType<typeof recentExpenses>[number]) => {
    setAmount(String(r.amount));
    setMerchant(r.merchant);
    if (r.categoryId) setCategory(r.categoryId);
    setAccount(r.accountId);
  };

  // Soft duplicate detector (#6): warn — never block — when the current draft
  // matches an existing expense/income (same account + merchant + amount within
  // ±3 days). Transfers have their own two-sided shape, so skip them here.
  const duplicate = useMemo(() => {
    if (type === 'transfer') return null;
    const value = parseFloat(amount);
    if (!merchant.trim() || !value || Number.isNaN(value)) return null;
    return findDuplicate(storeTxns, activeId, {
      merchant,
      amount: value,
      accountId: account,
      date,
    });
  }, [type, amount, merchant, account, date, storeTxns, activeId]);

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
    if (!value || value <= 0) return void toast.error(t('errors.amount'));
    if (!fromAccount || !toAccount) return void toast.error(t('errors.accounts'));
    if (fromAccount === toAccount) return void toast.error(t('errors.sameAccount'));
    // Cross-currency: the received amount is required so the actual bank
    // conversion is recorded rather than guessed from the mid-rate.
    let recv: number | undefined;
    if (transferIsCrossCurrency) {
      recv = parseFloat(received);
      if (!recv || recv <= 0) return void toast.error(t('errors.recvAmount', { currency: toCurrency }));
    }
    // A cleared date field falls back to "now" (local).
    const when = date || localDateTimeNow();
    createTransfer({
      fromAccountId: fromAccount,
      toAccountId: toAccount,
      fromAmount: value,
      toAmount: recv,
      date: when.slice(0, 10),
      time: when.slice(11, 16) || undefined,
      note: note.trim() || undefined,
    });
    const fromName = accountOptions.find((a) => a.id === fromAccount)?.name ?? t('fallback.account');
    const toName = accountOptions.find((a) => a.id === toAccount)?.name ?? t('fallback.account');
    toast.success(t('toasts.transferCreated'), {
      description: t('toasts.transferDescription', {
        from: fromName,
        to: toName,
        amount: native(value, accountCurrency),
      }),
    });
    onSaved?.('');
  };

  const save = () => {
    if (type === 'transfer') return saveTransfer();
    const value = parseFloat(amount);
    if (!value || Number.isNaN(value)) {
      toast.error(t('errors.amount'));
      return;
    }
    const signed = type === 'income' ? Math.abs(value) : -Math.abs(value);
    // The entry is in the account's currency. Provide an optimistic ledger-base
    // figure for immediate display; the server re-derives + locks it on sync.
    const baseAmount =
      accountCurrency === base ? signed : Math.round(convertAmount(signed, accountCurrency, base) * 100) / 100;
    // Split the datetime-local value into the stored date + time columns,
    // honouring what the user picked; a cleared field falls back to "now".
    const when = date || localDateTimeNow();
    const fallbackName = type === 'income' ? t('fallback.income') : t('fallback.untitled');
    const id = addTransaction({
      merchant: merchant.trim() || fallbackName,
      category,
      amount: baseAmount,
      currency: accountCurrency,
      nativeAmount: signed,
      account,
      date: when.slice(0, 10),
      time: when.slice(11, 16) || undefined,
      note: note.trim(),
      pending: false,
      ledgerId: activeId,
    });
    toast.success(type === 'income' ? t('toasts.incomeAdded') : t('toasts.expenseAdded'), {
      description: t('toasts.txnDescription', {
        merchant: merchant.trim() || fallbackName,
        amount: native(Math.abs(value), accountCurrency),
      }),
    });
    onSaved?.(id);
  };

  return (
    <div className={cn('flex flex-col gap-3.5 px-5 pt-4 pb-8', className)}>
      <div className="flex justify-center pt-5">
        <div role="tablist" aria-label={t('typeAria')} className="bg-secondary inline-flex rounded-full p-0.5 text-xs">
          {(['expense', 'income', 'transfer'] as const).map((tv) => (
            <button
              key={tv}
              type="button"
              role="tab"
              aria-selected={type === tv}
              onClick={() => setType(tv)}
              className={cn('rounded-full px-4 py-1.5 transition-colors', type === tv ? 'bg-background text-foreground shadow-sm' : 'text-muted-foreground')}
            >
              {t(`types.${tv}`)}
            </button>
          ))}
        </div>
      </div>

      {recents.length > 0 && (
        <div className="-mx-5 px-5">
          <div className="text-muted-foreground mb-1.5 font-mono text-[10px] tracking-[1.5px]">{t('recent')}</div>
          <div className="flex gap-1.5 overflow-x-auto pb-1">
            {recents.map((r, i) => (
              <button
                key={`${r.merchant}-${r.amount}-${i}`}
                type="button"
                onClick={() => applyRecent(r)}
                aria-label={t('repeatAria', { merchant: r.merchant, amount: native(r.amount, r.currency) })}
                className="bg-secondary text-secondary-foreground hover:bg-secondary/80 flex shrink-0 items-center gap-1.5 rounded-full px-3 py-1.5 text-[12px] transition-colors"
              >
                <span className="truncate max-w-[14ch]">{r.merchant}</span>
                <span className="text-muted-foreground tabular-nums">{native(r.amount, r.currency)}</span>
              </button>
            ))}
          </div>
        </div>
      )}
      <div>
        <Field icon="banknote" label={type === 'transfer' ? t('fields.sent') : t('fields.amount')}>
          <div className="flex items-baseline gap-1">
            <span className="text-muted-foreground text-[15px]">{currencySym}</span>
            <input
              value={amount}
              onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ''))}
              inputMode="decimal"
              aria-label={t('fields.amountAria')} placeholder="0"
              autoFocus
              className="placeholder:text-muted-foreground w-24 bg-transparent text-right text-[15px] outline-none"
            />
          </div>
        </Field>
        {type === 'transfer' ? (
          <>
            <Field icon="wallet" label={t('fields.from')}>
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
            <Field icon="arrow-r" label={t('fields.to')}>
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
                <Field icon="coins" label={t('fields.recv', { currency: toCurrency })}>
                  <input
                    value={received}
                    onChange={(e) => setReceived(e.target.value.replace(/[^0-9.]/g, ''))}
                    inputMode="decimal"
                    aria-label={t('fields.recvAria')}
                    placeholder={t('fields.recvPlaceholder', { currency: toCurrency })}
                    className="placeholder:text-muted-foreground w-full bg-transparent text-right text-[15px] outline-none"
                  />
                </Field>
                {(() => {
                  const sent = parseFloat(amount);
                  const got = parseFloat(received);
                  if (!sent || !got) return null;
                  return (
                    <div className="text-muted-foreground px-5 py-2 text-right text-[11px]">
                      {t('fields.effectiveRate', { rate: (got / sent).toFixed(6), to: toCurrency, from: accountCurrency })}
                    </div>
                  );
                })()}
              </>
            )}
          </>
        ) : (
          <>
            <Field icon="coins" label={t('fields.currency')}>
              <span className="text-muted-foreground text-[15px]" title={t('fields.currencyHint')}>{accountCurrency}</span>
            </Field>
            <Field icon="tag" label={t('fields.merchant')}>
              <button
                type="button"
                onClick={() =>
                  openMerchantPicker(merchant, (res) => {
                    if (!res) return;
                    // "Create new" returns only a name — create the counterparty
                    // row here so the save-time name resolution has something to
                    // link (the pending flow's server mutation does this itself).
                    if (res.kind === 'new') createCounterparty({ name: res.name, ledgerId: activeId });
                    setMerchant(res.name);
                  })
                }
                className="flex w-full items-center justify-end gap-1.5 text-right text-[15px] outline-none"
                aria-label={t('fields.merchantAria')}
              >
                <span className={cn('truncate', merchant ? 'text-foreground' : 'text-muted-foreground')}>
                  {merchant || t('fields.merchantPlaceholder')}
                </span>
                <Chev size={12} className="text-muted-foreground shrink-0" />
              </button>
            </Field>
            <Field icon="fork" label={t('fields.category')}>
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
                  aria-label={t('suggestion.aria', { name: suggestedName })}
                >
                  <Sync size={10} />
                  <span>{t('suggestion.prefix')} <span className="font-medium">{suggestedName}</span></span>
                  <span className="text-muted-foreground">· {suggestion.count}×</span>
                </button>
              </div>
            )}
            <Field icon="wallet" label={t('fields.account')}>
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
        <Field icon="calendar" label={t('fields.date')}>
          <input
            type="datetime-local" aria-label={t('fields.dateAria')}
            value={date}
            onChange={(e) => setDate(e.target.value)}
            className="bg-transparent text-right text-[15px] outline-none"
          />
        </Field>
        <Field icon="edit" label={t('fields.note')}>
          <input
            value={note}
            onChange={(e) => setNote(e.target.value)}
            aria-label={t('fields.noteAria')} placeholder={t('fields.notePlaceholder')}
            className="placeholder:text-muted-foreground w-full bg-transparent text-right text-[15px] outline-none"
          />
        </Field>
      </div>

      {duplicate && (
        <div
          role="status"
          className="border-warning/40 bg-warning/10 text-warning-foreground flex items-start gap-2.5 rounded-xl border px-3.5 py-2.5 text-[12px]"
        >
          <Bell size={14} className="text-warning mt-0.5 shrink-0" />
          <span>
            {t('duplicateWarning', { merchant: duplicate.merchant, date: duplicate.date.slice(0, 10) })}
          </span>
        </div>
      )}

      <button
        type="button"
        onClick={save}
        className="bg-foreground text-background mt-2 flex h-[54px] cursor-pointer items-center justify-center rounded-[27px] text-base font-medium -tracking-[0.2px]"
      >
        {type === 'transfer' ? t('saveButton.transfer') : type === 'income' ? t('saveButton.income') : t('saveButton.expense')}
      </button>
    </div>
  );
}
