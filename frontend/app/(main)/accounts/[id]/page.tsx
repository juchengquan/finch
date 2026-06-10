'use client';

import { useParams, useRouter } from 'next/navigation';
import { useState } from 'react';
import Link from 'next/link';
import { toast } from 'sonner';
import { useTranslations } from 'next-intl';
import { CatBar } from '@/components/ui/cat-bar';
import { Money, Sparkline } from '@/components/primitives';
import { Check, Chev, Doc, Edit, Filter, Plus, Sync, Trash, Wallet, X } from '@/components/icons';
import { RefundBadge } from '@/components/ui/refund-badge';
import { AnomalyBadge } from '@/components/anomaly-badge';
import { merchantStats, anomalyScore } from '@/lib/select';
import { MobilePage } from '@/components/mobile-page';
import { ScreenHeader } from '@/components/ui/screen-header';
import { StatusBadge } from '@/components/ui/status-badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { useLedger } from '@/components/ledger-provider';
import { useMoney } from '@/components/use-money';
import { useTransactionDialog } from '@/components/transaction-dialog';
import { MOCK, catById, convertAmount, fmtNative } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { ACCOUNT_TYPE_OPTIONS, accountTypeLabel, toDbType } from '@/lib/account-types';
import { selectTransactions, accountBalance, balanceSeries, unrealizedFx, holdingsValueForAccount } from '@/lib/select';
import { reconcileState } from '@/lib/reconcile';
import { AccountHoldings } from '@/components/account-holdings';
import { AccountForecast } from '@/components/account-forecast';
import { ReconcileStatus } from '@/components/reconcile-status';
import { cn } from '@/lib/utils';

export default function AccountDetailPage() {
  const { active } = useLedger();
  const { display, fmtFrom, toBase, fmt, base } = useMoney();
  const params = useParams();
  const router = useRouter();
  const t = useTranslations('accounts.detail');
  const tNav = useTranslations('nav');
  const tCommon = useTranslations('common');
  const accountId = params.id as string;
  // Try real (DB-backed) accounts first; the mock list is a pre-hydration
  // fallback for structural fields (color, ledger). When neither matches the
  // route id, we render a Not-Found state below — silently swapping in
  // MOCK.accounts[0] would have shown the first mock account on every bad
  // link, which the audit flagged as a real UX bug.
  const mock = MOCK.accounts.find((a) => a.id === accountId);
  const allTxns = useFinanceStore((s) => s.transactions);
  const accounts = useFinanceStore((s) => s.accounts);
  const holdings = useFinanceStore((s) => s.holdings);
  const updateAccount = useFinanceStore((s) => s.updateAccount);
  const archiveAccount = useFinanceStore((s) => s.archiveAccount);
  const adjustAccountBalance = useFinanceStore((s) => s.adjustAccountBalance);
  const confirmPending = useFinanceStore((s) => s.confirmPending);
  const cancelPending = useFinanceStore((s) => s.cancelPending);

  // The projected DB row is the source of truth; the mock is a pre-hydration
  // fallback for structural fields (color, ledger).
  const row = accounts.find((a) => a.id === accountId);
  // No real account AND no mock — the route id doesn't resolve. The store may
  // still be hydrating on first paint though (no `accounts` yet, no `mock` for
  // unseeded ids), so only commit to the Not-Found state once the projection
  // has at least loaded; until then we render a quiet placeholder.
  const notFound = !row && !mock;
  const ledgerId = row?.ledgerId ?? (mock as { ledger?: string } | undefined)?.ledger ?? 'personal';
  const cardColor = row?.color ?? mock?.color ?? '#374151';

  // Transaction list and live balance come from the projected store state.
  // The posted list is confirmed-only; unconfirmed (pending) rows surface in a
  // separate "To confirm" section and don't affect the balance until confirmed.
  const txs = selectTransactions(allTxns, { ledgerId, accountId, status: 'confirmed' });
  const toConfirm = selectTransactions(allTxns, { ledgerId, accountId, status: 'pending' });
  const balance = row ? accountBalance(accounts, accountId) : (mock?.balance ?? 0);
  const series = balanceSeries(allTxns, accountId, balance);
  // Unrealized FX gain/loss: how far the live ledger-base valuation has drifted
  // from the locked cost basis. Always zero for accounts denominated in the
  // ledger base; only meaningful for foreign-currency accounts.
  const fxDelta = row && row.currency !== active.base ? unrealizedFx(row, allTxns, toBase) : 0;
  // Investment accounts have positions in `holdings` separate from cash; the
  // total account value is cash + Σ holdings_value (in the account's currency).
  const isInvestment = (row?.type ?? (mock ? toDbType(mock.type) : '')) === 'investment';
  const holdingsTotal = isInvestment ? holdingsValueForAccount(holdings, accountId) : 0;
  // Per-merchant stats power the inline "Unusual" badge on transaction rows.
  // One pass over the ledger's transactions per render; row lookup is O(1).
  // Computed inline (not useMemo) because the React Compiler / preserve-
  // manual-memoization lint rule flags the derived `ledgerId` as unstable.
  const merchantStatsMap = merchantStats(allTxns, ledgerId);

  const [detailsOpen, setDetailsOpen] = useState(false);
  const [editOpen, setEditOpen] = useState(false);
  const [confirmArchive, setConfirmArchive] = useState(false);
  const [adjustOpen, setAdjustOpen] = useState(false);
  const [adjustTarget, setAdjustTarget] = useState('');
  const [adjustNote, setAdjustNote] = useState('');
  const [draft, setDraft] = useState({ name: '', type: 'savings' });
  // Reconcile-to-statement session state. Only one account-detail page is in
  // reconcile mode at a time; entering mode swaps the truncated transaction
  // list for a full ticking surface (see RECONCILE_PLAN §5.2).
  const [reconcileMode, setReconcileMode] = useState(false);
  const [statementBalance, setStatementBalance] = useState('');
  const [statementDate, setStatementDate] = useState(() => new Date().toISOString().slice(0, 10));
  // Quick-add-missing-transaction state (RECONCILE_PLAN §10.2): an inline form
  // inside reconcile mode that creates the row and auto-clears it so the
  // difference closes immediately. Income vs expense follows the sign toggle.
  const [addOpen, setAddOpen] = useState(false);
  const [addMerchant, setAddMerchant] = useState('');
  const [addAmount, setAddAmount] = useState('');
  const [addExpense, setAddExpense] = useState(true);
  const setCleared = useFinanceStore((s) => s.setCleared);
  const reconcileAccount = useFinanceStore((s) => s.reconcileAccount);
  const addTransaction = useFinanceStore((s) => s.addTransaction);
  const storeCategories = useFinanceStore((s) => s.categories);
  const { openTransaction } = useTransactionDialog();

  const name = row?.name ?? mock?.name ?? '';
  const type = row?.type ?? (mock ? toDbType(mock.type) : 'savings');
  const currency = row?.currency ?? active.base;

  const openEdit = () => {
    setDraft({ name, type });
    setDetailsOpen(false);
    setEditOpen(true);
  };

  const saveDetails = () => {
    // currency is intentionally omitted — it's fixed at account creation.
    updateAccount(accountId, {
      name: draft.name.trim(),
      type: draft.type,
    });
    toast.success(t('editDialog.updatedToast'), { description: draft.name.trim() || name });
  };

  const openAdjust = () => {
    setAdjustTarget(String(balance));
    setAdjustNote('');
    setAdjustOpen(true);
  };

  // Reconcile session handlers — entering/exiting and finalising.
  const openReconcile = () => {
    // Default the statement balance to whatever the account thinks today (the
    // common case: a recently-arrived statement matches reality and the user
    // just confirms by ticking rows). The user overwrites it if it doesn't.
    setStatementBalance(String(balance));
    setStatementDate(new Date().toISOString().slice(0, 10));
    setReconcileMode(true);
  };
  const exitReconcile = () => setReconcileMode(false);
  const targetNumber = Number.parseFloat(statementBalance);
  const recState = row && Number.isFinite(targetNumber)
    ? reconcileState(row, allTxns, targetNumber)
    : null;
  const finishReconcile = (postAdjustment: boolean) => {
    if (!row || !Number.isFinite(targetNumber)) {
      return void toast.error(t('reconcileCard.statementBalanceError'));
    }
    if (!statementDate) return void toast.error(t('reconcileCard.statementDateError'));
    reconcileAccount({
      accountId,
      statementBalance: targetNumber,
      statementDate,
      postAdjustment,
    });
    toast.success(
      postAdjustment ? t('reconcileCard.reconciledWithAdjustmentToast') : t('reconcileCard.reconciledToast'),
      { description: `${name} → ${targetNumber.toLocaleString()}` },
    );
    exitReconcile();
  };

  // Add a missing transaction during reconcile, then auto-clear it so it counts
  // toward the cleared balance immediately (§10.2(1)). The entry is in the
  // account's currency; mirror add-expense-form's optimistic base figure (the
  // server re-derives + locks it on sync). Defaults the category to the first
  // expense/income category in the ledger; the user recategorises later.
  const addMissing = () => {
    const value = parseFloat(addAmount);
    if (!value || Number.isNaN(value)) return void toast.error(t('reconcileCard.amountError'));
    if (!addMerchant.trim()) return void toast.error(t('reconcileCard.merchantError'));
    const signed = addExpense ? -Math.abs(value) : Math.abs(value);
    const baseAmount = currency === base ? signed : Math.round(convertAmount(signed, currency, base) * 100) / 100;
    const fallbackCat = storeCategories.find((c) => c.ledgerId === ledgerId)?.id ?? null;
    const id = addTransaction({
      merchant: addMerchant.trim(),
      category: fallbackCat,
      amount: baseAmount,
      currency,
      nativeAmount: signed,
      account: accountId,
      date: statementDate,
      time: new Date().toTimeString().slice(0, 5),
      note: '',
      pending: false,
      ledgerId,
    });
    setCleared(id, true); // auto-clear: it's on the statement, that's why we're adding it
    toast.success(t('reconcileCard.addedClearedToast'), { description: `${addMerchant.trim()} · ${fmtNative(Math.abs(value), currency)}` });
    setAddMerchant('');
    setAddAmount('');
    setAddOpen(false);
  };

  // "It posted" shortcut on a pending row: confirm + clear in one tap (§10.2(2)).
  const confirmAndClear = (txId: string) => {
    confirmPending(txId);
    setCleared(txId, true);
    toast.success(t('pending.confirmAndClearedToast'));
  };
  const submitAdjust = () => {
    const target = parseFloat(adjustTarget);
    if (!Number.isFinite(target)) return void toast.error(t('adjustDialog.targetError'));
    if (Math.abs(target - balance) < 0.005) {
      toast.info(t('adjustDialog.alreadyAtToast'));
      setAdjustOpen(false);
      return;
    }
    adjustAccountBalance(accountId, target, adjustNote.trim() || undefined);
    toast.success(t('adjustDialog.adjustedToast'), { description: `${name} → ${target.toLocaleString()}` });
    setAdjustOpen(false);
  };

  const doArchive = () => {
    archiveAccount(accountId);
    toast.success(t('archiveDialog.archivedToast'), { description: name });
    setConfirmArchive(false);
    setEditOpen(false);
    router.push('/accounts');
  };

  const details: [string, string][] = [
    [t('details.type'), accountTypeLabel(type)],
    [t('details.currency'), currency],
    [t('details.lastSync'), t('details.lastSyncValue')],
    [t('details.linkedSince'), t('details.linkedSinceValue')],
  ];

  if (notFound) {
    return (
      <MobilePage
        header={
          <ScreenHeader title={t('notFoundTitle')} back={true} backHref="/accounts" trailing={<></>} />
        }
      >
        <div className="px-5 pb-[22px]">
          <div className="bg-card border-border mt-4 flex flex-col items-center gap-3 rounded-2xl border px-6 py-12 text-center">
            <Wallet size={28} />
            <div className="font-serif text-xl">{t('notFoundHeader')}</div>
            <p className="text-muted-foreground max-w-xs text-sm">
              {t('notFoundBody', { id: accountId })}
            </p>
            <Button variant="outline" onClick={() => router.push('/accounts')}>
              {t('backToAccounts')}
            </Button>
          </div>
        </div>
      </MobilePage>
    );
  }

  return (
    <MobilePage
      header={
        <ScreenHeader title={name} back={true} backHref="/accounts" trailing={<></>} />
      }
    >
      <div className="px-5 pb-[22px]">
        <div className="text-muted-foreground mb-[18px] flex items-center gap-2 text-xs md:hidden">
          <Link href="/accounts" className="text-muted-foreground no-underline">{tNav('accounts')}</Link>
          <Chev size={11} />
          <span className="text-foreground">{name}</span>
        </div>

        <div className="relative mb-6 overflow-hidden rounded-2xl px-7 py-5 text-white" style={{ background: cardColor }}>
          <div className="absolute -top-[60px] -right-20 size-60 rounded-full bg-white/5"/>
          <div className="relative flex items-center justify-between gap-4">
            <div className="min-w-0">
              {/* Primary balance is in the account's own currency; the secondary
                  line converts to the display currency (hidden when they match). */}
              <div className="font-serif text-[40px] leading-none -tracking-[1.5px] tabular-nums">
                {fmtNative(balance, currency)}
              </div>
              {currency !== display && (
                <div className="mt-1.5 text-sm text-white/70 tabular-nums">≈ {fmtFrom(balance, currency)}</div>
              )}
              {row && row.currency !== active.base && Math.abs(fxDelta) >= 0.01 && (
                <div className="mt-1 text-xs text-white/60 tabular-nums">
                  {fxDelta >= 0 ? t('fxGain', { amount: fmt(Math.abs(fxDelta)) }) : t('fxLoss', { amount: fmt(Math.abs(fxDelta)) })}
                </div>
              )}
              {isInvestment && holdingsTotal > 0 && (
                <div className="mt-1.5 text-xs text-white/70 tabular-nums">
                  {t('holdingsLine', { holdings: fmtNative(holdingsTotal, currency), total: fmtNative(balance + holdingsTotal, currency) })}
                </div>
              )}
            </div>
            {/* Mobile: single entry — opens the details sheet, which holds the Edit button. */}
            <button
              type="button"
              onClick={() => setDetailsOpen(true)}
              aria-label={t('detailsAria')}
              className="flex size-9 shrink-0 cursor-pointer items-center justify-center rounded-full border border-white/30 text-white transition-colors hover:bg-white/15 md:hidden"
            >
              <Doc size={16} />
            </button>
            {/* Desktop: details are shown inline, so the card button edits directly. */}
            <button
              type="button"
              onClick={openEdit}
              aria-label={t('editAria')}
              className="hidden size-9 shrink-0 cursor-pointer items-center justify-center rounded-full border border-white/30 text-white transition-colors hover:bg-white/15 md:flex"
            >
              <Edit size={16} />
            </button>
          </div>
          {series.length > 2 && (
            <div className="relative mt-4">
              <Sparkline
                values={series}
                width={320}
                height={44}
                color="rgba(255,255,255,0.9)"
                fillOpacity={0.16}
              />
            </div>
          )}
        </div>

        <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
          {row && <ReconcileStatus account={row} />}
          <div className="flex gap-2">
            <Button variant="outline" size="sm" onClick={openAdjust}>
              <Edit size={13} />{t('adjustBalance')}
            </Button>
            <Button variant="outline" size="sm" onClick={openReconcile} disabled={reconcileMode}>
              <Check size={13} />{t('reconcile')}
            </Button>
          </div>
        </div>

        {reconcileMode && row && (
          <div className="bg-card border-border mb-4 overflow-hidden rounded-[14px] border">
            <div className="border-border flex items-center justify-between border-b px-[18px] py-3.5">
              <div className="text-sm font-semibold">{t('reconcileCard.title')}</div>
              <button
                type="button"
                onClick={exitReconcile}
                aria-label={t('reconcileCard.cancelAria')}
                className="text-muted-foreground hover:text-foreground cursor-pointer text-[11px]"
              >
                {t('reconcileCard.cancel')}
              </button>
            </div>
            <div className="grid grid-cols-2 gap-3 px-[18px] py-3.5">
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="recon-balance" className="text-muted-foreground text-[11px]">
                  {t('reconcileCard.statementBalance', { currency })}
                </Label>
                <Input
                  id="recon-balance"
                  type="number"
                  inputMode="decimal"
                  value={statementBalance}
                  onChange={(e) => setStatementBalance(e.target.value)}
                  className="h-8 text-right font-mono text-[12px]"
                />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="recon-date" className="text-muted-foreground text-[11px]">{t('reconcileCard.asOf')}</Label>
                <Input
                  id="recon-date"
                  type="date"
                  value={statementDate}
                  onChange={(e) => setStatementDate(e.target.value)}
                  className="h-8 text-[12px]"
                />
              </div>
            </div>
            {recState && (
              <div className="border-border space-y-2 border-t px-[18px] py-3.5">
                <div className="flex items-baseline justify-between font-mono text-[11px]">
                  <span className="text-muted-foreground">{t('reconcileCard.cleared')}</span>
                  <span>{fmtNative(recState.clearedBalance, currency)}</span>
                </div>
                <div className="flex items-baseline justify-between font-mono text-[11px]">
                  <span className="text-muted-foreground">{t('reconcileCard.target')}</span>
                  <span>{fmtNative(recState.statementBalance, currency)}</span>
                </div>
                <div className="flex items-baseline justify-between font-mono text-[11px]">
                  <span className="text-muted-foreground">{t('reconcileCard.difference')}</span>
                  <span className={cn(recState.balanced ? 'text-success' : 'text-warning')}>
                    {recState.difference >= 0 ? '+' : '−'}
                    {fmtNative(Math.abs(recState.difference), currency)}
                  </span>
                </div>
                <div className="bg-secondary h-1.5 w-full overflow-hidden rounded-full">
                  <span
                    className={cn(
                      'block h-full transition-all',
                      recState.balanced ? 'bg-success' : 'bg-warning',
                    )}
                    style={{
                      width: `${Math.min(
                        100,
                        recState.statementBalance === 0
                          ? 0
                          : Math.abs((recState.clearedBalance / recState.statementBalance) * 100),
                      )}%`,
                    }}
                  />
                </div>
                <div className="text-muted-foreground flex items-center justify-between text-[11px]">
                  <span>
                    {t('reconcileCard.summary', { cleared: recState.clearedCount, toReview: recState.unclearedCount })}
                  </span>
                </div>
                {!recState.balanced && (
                  <p className="text-muted-foreground text-[11px]">
                    {recState.difference > 0
                      ? t('reconcileCard.shortBy', { amount: fmtNative(Math.abs(recState.difference), currency) })
                      : t('reconcileCard.overBy', { amount: fmtNative(Math.abs(recState.difference), currency) })}
                  </p>
                )}

                {/* Quick-add a missing transaction (§10.2(1)) — primary recovery. */}
                {addOpen ? (
                  <div className="border-border bg-secondary/40 space-y-2 rounded-lg border p-2.5">
                    <div className="flex gap-2">
                      <div role="tablist" aria-label={t('reconcileCard.directionAria')} className="bg-secondary inline-flex rounded-full p-0.5 text-[11px]">
                        {([['expense', true], ['income', false]] as const).map(([key, isExp]) => (
                          <button
                            key={key}
                            type="button"
                            role="tab"
                            aria-selected={addExpense === isExp}
                            onClick={() => setAddExpense(isExp)}
                            className={cn('rounded-full px-2.5 py-1', addExpense === isExp ? 'bg-background text-foreground shadow-sm' : 'text-muted-foreground')}
                          >
                            {t(`reconcileCard.${key}`)}
                          </button>
                        ))}
                      </div>
                    </div>
                    <Input
                      aria-label={t('reconcileCard.merchant')}
                      placeholder={t('reconcileCard.merchant')}
                      value={addMerchant}
                      onChange={(e) => setAddMerchant(e.target.value)}
                      className="h-8 text-[12px]"
                    />
                    <div className="flex gap-2">
                      <Input
                        aria-label={t('reconcileCard.amountAria', { currency })}
                        type="number"
                        inputMode="decimal"
                        placeholder={t('reconcileCard.amountPlaceholder', { currency })}
                        value={addAmount}
                        onChange={(e) => setAddAmount(e.target.value)}
                        onKeyDown={(e) => { if (e.key === 'Enter') addMissing(); }}
                        className="h-8 text-right font-mono text-[12px]"
                      />
                      <Button size="sm" onClick={addMissing}>{t('reconcileCard.addButton')}</Button>
                      <Button size="sm" variant="ghost" onClick={() => setAddOpen(false)}>{t('reconcileCard.addCancel')}</Button>
                    </div>
                  </div>
                ) : (
                  <Button size="sm" variant="outline" className="w-full" onClick={() => setAddOpen(true)}>
                    <Plus size={13} /> {t('reconcileCard.addMissing')}
                  </Button>
                )}

                <div className="flex justify-end gap-2 pt-1">
                  {!recState.balanced && (
                    <Button size="sm" variant="ghost" onClick={() => finishReconcile(true)}>
                      {t('reconcileCard.postAdjustment', { amount: fmtNative(Math.abs(recState.difference), currency) })}
                    </Button>
                  )}
                  <Button size="sm" onClick={() => finishReconcile(false)} disabled={!recState.balanced}>
                    {t('reconcileCard.doneButton')}
                  </Button>
                </div>
              </div>
            )}
          </div>
        )}

        {/* Pending rows during reconcile: a "it posted" one-tap that confirms +
            clears together (§10.2(2)). Pending rows can't be cleared while
            pending, so this is the bridge. */}
        {reconcileMode && toConfirm.length > 0 && (
          <div className="border-border mb-4 overflow-hidden rounded-[14px] border">
            <div className="border-border flex items-center justify-between border-b px-[18px] py-3.5">
              <div className="text-sm font-semibold">{t('pending.headerReconcile', { count: toConfirm.length })}</div>
              <span className="text-muted-foreground text-[11px]">{t('pending.subReconcile')}</span>
            </div>
            {toConfirm.map((tx, i) => {
              const cat = catById(tx.category);
              const inc = tx.amount > 0;
              return (
                <div
                  key={tx.id}
                  className={cn('flex items-center gap-3 px-[18px] py-3', i && 'border-border border-t-[0.5px]')}
                >
                  <CatBar color={cat.color} />
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <span className="truncate text-[13px] font-medium">{tx.merchant}</span>
                      <StatusBadge status="pending" />
                    </div>
                    <div className="text-muted-foreground mt-0.5 text-[11px]">{tx.date.replace(/-/g, '/')}{tx.time ? ' ' + tx.time.slice(0, 5) : ''} · {cat.name || t('pending.incomeFallback')}</div>
                  </div>
                  <Money value={tx.amount} signed={inc} className={cn('font-mono text-[13px] font-semibold', inc ? 'text-success' : 'text-foreground')} />
                  <Button
                    size="sm" variant="outline" className="shrink-0"
                    aria-label={t('pending.confirmAndClearAria', { merchant: tx.merchant })}
                    onClick={() => confirmAndClear(tx.id)}
                  >
                    {t('pending.confirmAndClearLabel')}
                  </Button>
                </div>
              );
            })}
          </div>
        )}

        {toConfirm.length > 0 && !reconcileMode && (
          <div className="border-warning/30 bg-warning/5 mb-4 overflow-hidden rounded-[14px] border">
            <div className="border-warning/20 flex items-center justify-between border-b px-[18px] py-3.5">
              <div className="text-sm font-semibold">{t('pending.headerNormal', { count: toConfirm.length })}</div>
              <span className="text-muted-foreground text-[11px]">{t('pending.subNormal')}</span>
            </div>
            {toConfirm.map((tx, i) => {
              const cat = catById(tx.category);
              const inc = tx.amount > 0;
              return (
                <div
                  key={tx.id}
                  className={cn('flex items-center gap-3 px-[18px] py-3', i && 'border-border border-t-[0.5px]')}
                >
                  <CatBar color={cat.color} />
                  <button type="button" onClick={() => openTransaction(tx.id)} className="min-w-0 flex-1 cursor-pointer text-left">
                    <div className="flex items-center gap-2">
                      <span className="truncate text-[13px] font-medium">{tx.merchant}</span>
                      <StatusBadge status="pending" />
                    </div>
                    <div className="text-muted-foreground mt-0.5 text-[11px]">{tx.date.replace(/-/g, '/')}{tx.time ? ' ' + tx.time.slice(0, 5) : ''} · {cat.name || t('pending.incomeFallback')}</div>
                  </button>
                  <Money value={tx.amount} signed={inc} className={cn('font-mono text-[13px] font-semibold', inc ? 'text-success' : 'text-foreground')} />
                  <div className="flex shrink-0 items-center gap-1">
                    <Button
                      size="icon" variant="ghost" className="size-8" aria-label={t('pending.confirmAria', { merchant: tx.merchant })}
                      onClick={() => { confirmPending(tx.id); toast.success(t('pending.confirmedToast', { merchant: tx.merchant })); }}
                    >
                      <Check size={14} strokeWidth={2} />
                    </Button>
                    <Button
                      size="icon" variant="ghost" className="size-8" aria-label={t('pending.voidAria', { merchant: tx.merchant })}
                      onClick={() => { cancelPending(tx.id); toast(t('pending.voidedToast', { merchant: tx.merchant })); }}
                    >
                      <X size={14} />
                    </Button>
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {isInvestment && (
          <div className="mb-4">
            <AccountHoldings accountId={accountId} ledgerId={ledgerId} accountCurrency={currency} />
          </div>
        )}

        {row && (
          <div className="mb-4">
            <AccountForecast account={row} />
          </div>
        )}

        <div className="grid grid-cols-1 gap-4 md:grid-cols-[2fr_1fr]">
          <div className="bg-card border-border overflow-hidden rounded-[14px] border">
            <div className="border-border flex items-center justify-between border-b px-[18px] py-3.5">
              <div className="text-sm font-semibold">{t('allTransactions', { count: txs.length })}</div>
              <div className="text-muted-foreground flex cursor-pointer items-center gap-1 text-xs"><Filter size={12}/>{t('filterLabel')}</div>
            </div>
            {(reconcileMode ? txs : txs.slice(0, 6)).map((tx, i) => {
              const cat = catById(tx.category);
              const inc = tx.amount > 0;
              const cleared = Boolean(tx.clearedAt);
              const handleClick = reconcileMode
                ? () => setCleared(tx.id, !cleared)
                : () => openTransaction(tx.id);
              return (
                <button
                  key={tx.id}
                  type="button"
                  onClick={handleClick}
                  aria-pressed={reconcileMode ? cleared : undefined}
                  className={cn(
                    'hover:bg-secondary/40 flex w-full cursor-pointer items-center gap-3 px-[18px] py-3 text-left',
                    i && 'border-border border-t-[0.5px]',
                    reconcileMode && cleared && 'bg-success/5',
                  )}
                >
                  {reconcileMode ? (
                    <span
                      className={cn(
                        'flex size-4 shrink-0 items-center justify-center rounded-full border',
                        cleared ? 'bg-success border-success text-background' : 'border-border',
                      )}
                      aria-hidden
                    >
                      {cleared && <Check size={10} />}
                    </span>
                  ) : (
                    <CatBar color={cat.color} />
                  )}
                  <div className="flex-1">
                    <div className="flex items-center gap-1.5">
                      <span className="text-[13px] font-medium">{tx.merchant}</span>
                      {tx.kind === 'refund' && <RefundBadge />}
                      {(() => {
                        const a = anomalyScore(tx, merchantStatsMap);
                        return a?.isAnomaly ? <AnomalyBadge zScore={a.zScore} mean={a.mean} /> : null;
                      })()}
                    </div>
                    <div className="text-muted-foreground mt-0.5 text-[11px]">{tx.date.replace(/-/g, '/')}{tx.time ? ' ' + tx.time.slice(0, 5) : ''} · {cat.name || t('pending.incomeFallback')}</div>
                  </div>
                  <Money value={tx.amount} signed={inc} className={cn('font-mono text-[13px] font-semibold', inc ? 'text-success' : 'text-foreground')}/>
                </button>
              );
            })}
          </div>

          <div className="bg-card border-border hidden rounded-[14px] border p-[18px] md:block">
            <div className="text-muted-foreground mb-2.5 font-mono text-[10px] tracking-[1.2px]">
              {t('detailsHeaderShort')}
            </div>
            {details.map(([l, v], i) => (
              <div key={l} className={cn('flex justify-between py-2 text-xs', i && 'border-border border-t-[0.5px] border-dotted')}>
                <span className="text-muted-foreground">{l}</span>
                <span className="font-mono">{v}</span>
              </div>
            ))}
            <div className="bg-secondary text-secondary-foreground mt-3.5 flex items-center gap-2 rounded-lg px-3.5 py-2.5 text-xs">
              <Sync size={12}/>{t('autoCategorize')}
            </div>
          </div>
        </div>
      </div>

      {/* Mobile-only (md+ shows the same details inline in the side column). */}
      <Dialog open={detailsOpen} onOpenChange={setDetailsOpen}>
        <DialogContent className="md:hidden">
          <DialogHeader>
            <DialogTitle className="font-serif text-xl italic">{t('detailsDialog.title')}</DialogTitle>
            <DialogDescription className="sr-only">
              {t('detailsDialog.description')}
            </DialogDescription>
          </DialogHeader>
          <div>
            {details.map(([l, v], i) => (
              <div key={l} className={cn('flex justify-between py-2.5 text-sm', i && 'border-border border-t-[0.5px] border-dotted')}>
                <span className="text-muted-foreground">{l}</span>
                <span className="font-mono">{v}</span>
              </div>
            ))}
            <div className="bg-secondary text-secondary-foreground mt-4 flex items-center gap-2 rounded-lg px-3.5 py-2.5 text-sm">
              <Sync size={14}/>{t('autoCategorize')}
            </div>
            <Button variant="outline" className="mt-4 w-full" onClick={openEdit}>
              <Edit size={14} />{t('detailsDialog.editButton')}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={editOpen} onOpenChange={setEditOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t('editDialog.title')}</DialogTitle>
            <DialogDescription>{name}</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="acct-name">{t('editDialog.name')}</Label>
              <Input id="acct-name" value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} autoFocus />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="acct-type">{t('editDialog.type')}</Label>
                <Select value={draft.type} onValueChange={(v) => setDraft({ ...draft, type: v })}>
                  <SelectTrigger id="acct-type" className="w-full"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {ACCOUNT_TYPE_OPTIONS.map((o) => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="acct-currency">{t('editDialog.currency')}</Label>
                <div
                  id="acct-currency"
                  className="border-input bg-muted text-muted-foreground flex h-9 w-full items-center rounded-md border px-3 text-sm"
                >
                  {currency}
                </div>
                <p className="text-muted-foreground text-[11px]">{t('editDialog.currencyHint')}</p>
              </div>
            </div>
          </div>
          <DialogFooter className="sm:justify-between">
            <Button variant="ghost" className="text-destructive hover:text-destructive" onClick={() => { setEditOpen(false); setConfirmArchive(true); }}>
              <Trash size={14} />{t('editDialog.archive')}
            </Button>
            <div className="flex gap-2">
              <DialogClose asChild>
                <Button variant="outline">{tCommon('cancel')}</Button>
              </DialogClose>
              <DialogClose asChild>
                <Button onClick={saveDetails}>{tCommon('save')}</Button>
              </DialogClose>
            </div>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={confirmArchive} onOpenChange={setConfirmArchive}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t('archiveDialog.title', { name })}</DialogTitle>
            <DialogDescription>
              {t('archiveDialog.description')}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">{tCommon('cancel')}</Button>
            </DialogClose>
            <Button variant="destructive" onClick={doArchive}>{t('archiveDialog.confirm')}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={adjustOpen} onOpenChange={setAdjustOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t('adjustDialog.title', { name })}</DialogTitle>
            <DialogDescription>
              {t('adjustDialog.description')}
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <Label>{t('adjustDialog.currentBalance')}</Label>
              <div className="text-muted-foreground text-sm">{balance.toLocaleString()}</div>
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="adjust-target">{t('adjustDialog.targetBalance')}</Label>
              <Input
                id="adjust-target"
                type="number"
                inputMode="decimal"
                value={adjustTarget}
                onChange={(e) => setAdjustTarget(e.target.value)}
                autoFocus
              />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="adjust-note">{t('adjustDialog.noteOptional')}</Label>
              <Input
                id="adjust-note"
                value={adjustNote}
                onChange={(e) => setAdjustNote(e.target.value)}
                placeholder={t('adjustDialog.notePlaceholder')}
              />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">{tCommon('cancel')}</Button>
            </DialogClose>
            <Button onClick={submitAdjust}>{t('adjustDialog.submit')}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MobilePage>
  );
}
