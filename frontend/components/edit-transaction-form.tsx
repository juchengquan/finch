'use client';

// The body of the edit-transaction sheet. Pre-populated from the row's current
// values; on save, calls `updateTransaction(id, patch)` with a patch covering
// only the fields the user can change from this form. The server is the
// source of truth — the store's optimistic-update + re-projection pattern
// (lib/store.ts:357 + lib/db/mutations.ts:398) handles the round-trip.

import { useState } from 'react';
import { toast } from 'sonner';
import { useTranslations } from 'next-intl';
import { Banknote, Calendar, Chev, Check, Clock, Coins, Fork, Tag, Wallet } from '@/components/icons';
import { CURRENCIES } from '@/lib/data';
import { categoryPath } from '@/lib/db/domain/categories/queries';
import { useFinanceStore, type Tx } from '@/lib/store';
import { useMerchantPicker } from '@/components/merchant-picker-dialog';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { cn } from '@/lib/utils';

// Field.icon is a string short-name; resolve to the typed lucide component
// so the form rows can be declared inline. Extend as new field types appear.
const FIELD_ICON: Record<string, typeof Wallet> = {
  banknote: Banknote,
  coins: Coins,
  tag: Tag,
  fork: Fork,
  wallet: Wallet,
  calendar: Calendar,
  clock: Clock,
  check: Check,
};

type Option = { id: string; name: string };

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

export function EditTransactionForm({
  txId,
  onSaved,
}: {
  txId: string;
  onSaved?: () => void;
}) {
  const allTxns = useFinanceStore((s) => s.transactions);
  const storeAccts = useFinanceStore((s) => s.accounts);
  const storeCats = useFinanceStore((s) => s.categories);
  const updateTransaction = useFinanceStore((s) => s.updateTransaction);
  const createCounterparty = useFinanceStore((s) => s.createCounterparty);
  const { openMerchantPicker } = useMerchantPicker();
  const t = useTranslations('editTxnForm');

  const tx = allTxns.find((tx2) => tx2.id === txId);

  // The provider mounts this form with `key={txId}` (see edit-transaction-sheet
  // — "Only mount while open so each open starts from the row's current values")
  // and also re-mounts on txId change. So `useState` initializers below run
  // against the new row's values, and an early `tx === undefined` simply
  // means the row was deleted between the click and the form render.
  const ledgerId = tx?.ledgerId ?? 'personal';
  const initialNative = tx ? (tx.nativeAmount ?? tx.amount) : 0;
  // Labels render as `Parent › Child › Leaf` so depth-3 picks read
  // unambiguously (CATEGORIES_LEVEL3_PLAN §5.1).
  const ledgerCats = storeCats.filter((c) => c.ledgerId === ledgerId);
  const ledgerCatById = new Map(ledgerCats.map((c) => [c.id, c]));
  const cats: Option[] = ledgerCats
    .map((c) => ({ id: c.id, name: categoryPath(c, ledgerCatById) }))
    .sort((a, b) => a.name.localeCompare(b.name));
  const accts: Option[] = storeAccts
    .filter((a) => a.ledgerId === ledgerId)
    .map((x) => ({ id: x.id, name: x.name }));

  const [merchant, setMerchant] = useState(tx?.merchant ?? '');
  const [account, setAccount] = useState(tx?.account ?? '');
  const [category, setCategory] = useState<string | null>(tx?.category ?? null);
  const [date, setDate] = useState(tx?.date ?? '');
  const [time, setTime] = useState(tx?.time ?? '');
  // The form edits the magnitude; the sign is reapplied on submit so the user
  // never has to re-type a minus sign for an existing expense.
  const [amount, setAmount] = useState(() => Math.abs(initialNative).toFixed(2));
  const [status, setStatus] = useState<'pending' | 'confirmed'>(tx?.pending ? 'pending' : 'confirmed');
  const [note, setNote] = useState(tx?.note ?? '');

  if (!tx) {
    return (
      <div className="text-muted-foreground py-20 text-center text-sm">{t('notFound')}</div>
    );
  }

  // Currency follows the selected account. An account's currency is fixed at
  // creation (see AccountPatch in lib/store.ts), so the form shows the new
  // account's currency the moment the user picks it.
  const acct = storeAccts.find((a) => a.id === account);
  const accountCurrency = acct?.currency ?? tx.currency ?? 'SGD';
  const currencySym = CURRENCIES[accountCurrency as keyof typeof CURRENCIES]?.sym ?? '$';

  const save = () => {
    const value = parseFloat(amount);
    if (!Number.isFinite(value) || value <= 0) {
      toast.error(t('errors.amount'));
      return;
    }
    if (!account) {
      toast.error(t('errors.account'));
      return;
    }
    if (!date) {
      toast.error(t('errors.date'));
      return;
    }
    // Re-apply the original sign. Refunds and incomes stay positive;
    // expenses stay negative. The user's figure is a magnitude.
    const signed = initialNative < 0 ? -value : value;

    // Only include fields that actually changed. The server's `updateTransaction`
    // is a no-op when no patch keys are set; on the client we still send the
    // full set because the store action takes `Partial<Tx>` and the server
    // runs the recompute path (re-projection is cheap). The reconciliation is
    // idempotent.
    const patch: Partial<Tx> = {
      merchant: merchant.trim() || tx.merchant,
      account,
      category,
      date,
      time: time || undefined,
      // Optimistic base + native values; the server re-derives amount_base
      // and exchange_rate against the new currency at the (possibly edited)
      // date, then re-projects. The client-side `amount` is also overwritten
      // by the projection when it returns.
      amount: signed,
      nativeAmount: signed,
      currency: accountCurrency,
      pending: status === 'pending',
      note: note.trim() || undefined,
    };
    updateTransaction(tx.id, patch);
    toast.success(t('updatedToast'));
    onSaved?.();
  };

  return (
    <div className="flex flex-col gap-3.5 px-5 pt-4 pb-8">
      <div>
        <Field icon="banknote" label={t('amount')}>
          <div className="flex items-baseline gap-1">
            <span className="text-muted-foreground text-[15px]">{currencySym}</span>
            <input
              value={amount}
              onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ''))}
              inputMode="decimal"
              aria-label={t('amountAria')} placeholder="0"
              autoFocus
              className="placeholder:text-muted-foreground w-24 bg-transparent text-right text-[15px] outline-none"
            />
          </div>
        </Field>
        <Field icon="coins" label={t('currency')}>
          <span className="text-muted-foreground text-[15px]" title={t('currencyHint')}>
            {accountCurrency}
          </span>
        </Field>
        <Field icon="tag" label={t('merchant')}>
          <button
            type="button"
            onClick={() =>
              openMerchantPicker(merchant, (res) => {
                if (!res) return;
                // "Create new" returns only a name — create the counterparty
                // row here so the save-time name resolution has something to
                // link (the pending flow's server mutation does this itself).
                if (res.kind === 'new') createCounterparty({ name: res.name, ledgerId });
                setMerchant(res.name);
              })
            }
            className="flex w-full items-center justify-end gap-1.5 text-right text-[15px] outline-none"
            aria-label={t('merchantAria')}
          >
            <span className={cn('truncate', merchant ? 'text-foreground' : 'text-muted-foreground')}>
              {merchant || t('merchantPlaceholder')}
            </span>
            <Chev size={12} className="text-muted-foreground shrink-0" />
          </button>
        </Field>
        <Field icon="fork" label={t('category')}>
          <Select
            value={category ?? 'uncategorized'}
            onValueChange={(v) => setCategory(v === 'uncategorized' ? null : v)}
          >
            <SelectTrigger size="sm" className="border-0 shadow-none">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {cats.map((c) => (
                <SelectItem key={c.id} value={c.id}>
                  {c.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </Field>
        <Field icon="wallet" label={t('account')}>
          <Select value={account} onValueChange={setAccount}>
            <SelectTrigger size="sm" className="border-0 shadow-none">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {accts.map((a) => (
                <SelectItem key={a.id} value={a.id}>
                  {a.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </Field>
        <Field icon="calendar" label={t('date')}>
          <input
            type="date" aria-label={t('dateAria')}
            value={date}
            onChange={(e) => setDate(e.target.value)}
            className="bg-transparent text-right text-[15px] outline-none"
          />
        </Field>
        <Field icon="clock" label={t('time')}>
          <input
            type="time" aria-label={t('timeAria')}
            value={time}
            onChange={(e) => setTime(e.target.value)}
            className="bg-transparent text-right text-[15px] outline-none"
          />
        </Field>
        <Field icon="check" label={t('status')}>
          <div role="tablist" aria-label={t('statusAria')} className="bg-secondary inline-flex rounded-full p-0.5 text-xs">
            {(['confirmed', 'pending'] as const).map((s) => (
              <button
                key={s}
                type="button"
                role="tab"
                aria-selected={status === s}
                onClick={() => setStatus(s)}
                className={cn(
                  'rounded-full px-3 py-1 transition-colors',
                  status === s ? 'bg-background text-foreground shadow-sm' : 'text-muted-foreground',
                )}
              >
                {s === 'confirmed' ? t('statusPosted') : t('statusPending')}
              </button>
            ))}
          </div>
        </Field>
        <Field icon="edit" label={t('note')}>
          <input
            value={note}
            onChange={(e) => setNote(e.target.value)}
            aria-label={t('noteAria')} placeholder={t('notePlaceholder')}
            className="placeholder:text-muted-foreground w-full bg-transparent text-right text-[15px] outline-none"
          />
        </Field>
      </div>

      <button
        type="button"
        onClick={save}
        className="bg-foreground text-background mt-2 flex h-[54px] cursor-pointer items-center justify-center rounded-[27px] text-base font-medium -tracking-[0.2px]"
      >
        {t('save')}
      </button>
    </div>
  );
}
