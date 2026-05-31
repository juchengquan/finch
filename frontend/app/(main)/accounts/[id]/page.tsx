'use client';

import { useParams, useRouter } from 'next/navigation';
import { useState } from 'react';
import Link from 'next/link';
import { toast } from 'sonner';
import { Icon, Money, CatBar, Sparkline } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { StatusBadge } from '@/components/StatusBadge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
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
import { useTransactionSheet } from '@/components/transaction-sheet';
import { MOCK, catById, CURRENCIES, fmtNative } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { ACCOUNT_TYPE_OPTIONS, accountTypeLabel, toDbType } from '@/lib/account-types';
import { selectTransactions, accountBalance, balanceSeries } from '@/lib/select';
import { cn } from '@/lib/utils';

export default function AccountDetailPage() {
  const { active } = useLedger();
  const { display, fmtFrom } = useMoney();
  const params = useParams();
  const router = useRouter();
  const accountId = params.id as string;
  const mock = MOCK.accounts.find(a => a.id === accountId) || MOCK.accounts[0];
  const allTxns = useFinanceStore((s) => s.transactions);
  const accounts = useFinanceStore((s) => s.accounts);
  const updateAccount = useFinanceStore((s) => s.updateAccount);
  const archiveAccount = useFinanceStore((s) => s.archiveAccount);
  const adjustAccountBalance = useFinanceStore((s) => s.adjustAccountBalance);
  const confirmPending = useFinanceStore((s) => s.confirmPending);
  const cancelPending = useFinanceStore((s) => s.cancelPending);

  // The projected DB row is the source of truth; the mock is a pre-hydration
  // fallback for structural fields (color, ledger).
  const row = accounts.find((a) => a.id === accountId);
  const ledgerId = row?.ledgerId ?? (mock as { ledger?: string }).ledger ?? 'personal';
  const cardColor = row?.color ?? mock.color;

  // Transaction list and live balance come from the projected store state.
  // The posted list is confirmed-only; unconfirmed (pending) rows surface in a
  // separate "To confirm" section and don't affect the balance until confirmed.
  const txs = selectTransactions(allTxns, { ledgerId, accountId, status: 'confirmed' });
  const toConfirm = selectTransactions(allTxns, { ledgerId, accountId, status: 'pending' });
  const balance = row ? accountBalance(accounts, accountId) : mock.balance;
  const series = balanceSeries(allTxns, accountId, balance);

  const [detailsOpen, setDetailsOpen] = useState(false);
  const [editOpen, setEditOpen] = useState(false);
  const [confirmArchive, setConfirmArchive] = useState(false);
  const [reconcileOpen, setReconcileOpen] = useState(false);
  const [reconcileTarget, setReconcileTarget] = useState('');
  const [reconcileNote, setReconcileNote] = useState('');
  const [draft, setDraft] = useState({ name: '', type: 'savings', currency: '' });
  const { openTransaction } = useTransactionSheet();

  const name = row?.name ?? mock.name;
  const type = row?.type ?? toDbType(mock.type);
  const currency = row?.currency ?? active.base;

  const openEdit = () => {
    setDraft({ name, type, currency });
    setDetailsOpen(false);
    setEditOpen(true);
  };

  const saveDetails = () => {
    updateAccount(accountId, {
      name: draft.name.trim(),
      type: draft.type,
      currency: draft.currency,
    });
    toast.success('Account updated', { description: draft.name.trim() || name });
  };

  const openReconcile = () => {
    setReconcileTarget(String(balance));
    setReconcileNote('');
    setReconcileOpen(true);
  };
  const submitReconcile = () => {
    const target = parseFloat(reconcileTarget);
    if (!Number.isFinite(target)) return void toast.error('Enter a target balance');
    if (Math.abs(target - balance) < 0.005) {
      toast.info('Already at this balance — nothing to adjust');
      setReconcileOpen(false);
      return;
    }
    adjustAccountBalance(accountId, target, reconcileNote.trim() || undefined);
    toast.success('Balance reconciled', { description: `${name} → ${target.toLocaleString()}` });
    setReconcileOpen(false);
  };

  const doArchive = () => {
    archiveAccount(accountId);
    toast.success('Account archived', { description: name });
    setConfirmArchive(false);
    setEditOpen(false);
    router.push('/accounts');
  };

  const details: [string, string][] = [
    ['Type', accountTypeLabel(type)],
    ['Currency', currency],
    ['Last sync', '2 min ago'],
    ['Linked since', 'Jan 2024'],
  ];

  return (
    <MobilePage
      header={
        <ScreenHeader title={name} back={true} backHref="/accounts" trailing={<></>} />
      }
    >
      <div className="px-5 pb-[22px]">
        <div className="text-muted-foreground mb-[18px] flex items-center gap-2 text-xs md:hidden">
          <Link href="/accounts" className="text-muted-foreground no-underline">Accounts</Link>
          <Icon name="chev" size={11}/>
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
            </div>
            {/* Mobile: single entry — opens the details sheet, which holds the Edit button. */}
            <button
              type="button"
              onClick={() => setDetailsOpen(true)}
              aria-label="Account details"
              className="flex size-9 shrink-0 cursor-pointer items-center justify-center rounded-full border border-white/30 text-white transition-colors hover:bg-white/15 md:hidden"
            >
              <Icon name="doc" size={16} />
            </button>
            {/* Desktop: details are shown inline, so the card button edits directly. */}
            <button
              type="button"
              onClick={openEdit}
              aria-label="Edit account"
              className="hidden size-9 shrink-0 cursor-pointer items-center justify-center rounded-full border border-white/30 text-white transition-colors hover:bg-white/15 md:flex"
            >
              <Icon name="edit" size={16} />
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

        <div className="mb-4 flex items-center justify-end">
          <Button variant="outline" size="sm" onClick={openReconcile}>
            <Icon name="sync" size={13} />Reconcile balance
          </Button>
        </div>

        {toConfirm.length > 0 && (
          <div className="border-warning/30 bg-warning/5 mb-4 overflow-hidden rounded-[14px] border">
            <div className="border-warning/20 flex items-center justify-between border-b px-[18px] py-3.5">
              <div className="text-sm font-semibold">To confirm · {toConfirm.length}</div>
              <span className="text-muted-foreground text-[11px]">Not in your balance yet</span>
            </div>
            {toConfirm.map((tx, i) => {
              const cat = catById(tx.category);
              const inc = tx.amount > 0;
              return (
                <div
                  key={tx.id}
                  className={cn('flex items-center gap-3 px-[18px] py-3', i && 'border-border border-t-[0.5px]')}
                >
                  <CatBar hue={cat.hue} />
                  <button type="button" onClick={() => openTransaction(tx.id)} className="min-w-0 flex-1 cursor-pointer text-left">
                    <div className="flex items-center gap-2">
                      <span className="truncate text-[13px] font-medium">{tx.merchant}</span>
                      <StatusBadge status="pending" />
                    </div>
                    <div className="text-muted-foreground mt-0.5 text-[11px]">{tx.date.replace(/-/g, '/')}{tx.time ? ' ' + tx.time.slice(0, 5) : ''} · {cat.name || 'Income'}</div>
                  </button>
                  <Money value={tx.amount} signed={inc} className={cn('font-mono text-[13px] font-semibold', inc ? 'text-success' : 'text-foreground')} />
                  <div className="flex shrink-0 items-center gap-1">
                    <Button
                      size="icon" variant="ghost" className="size-8" aria-label={`Confirm ${tx.merchant}`}
                      onClick={() => { confirmPending(tx.id); toast.success(`Confirmed ${tx.merchant}`); }}
                    >
                      <Icon name="check" size={14} stroke={2} />
                    </Button>
                    <Button
                      size="icon" variant="ghost" className="size-8" aria-label={`Void ${tx.merchant}`}
                      onClick={() => { cancelPending(tx.id); toast(`Voided ${tx.merchant}`); }}
                    >
                      <Icon name="x" size={14} />
                    </Button>
                  </div>
                </div>
              );
            })}
          </div>
        )}

        <div className="grid grid-cols-1 gap-4 md:grid-cols-[2fr_1fr]">
          <div className="bg-card border-border overflow-hidden rounded-[14px] border">
            <div className="border-border flex items-center justify-between border-b px-[18px] py-3.5">
              <div className="text-sm font-semibold">All transactions · {txs.length}</div>
              <div className="text-muted-foreground flex cursor-pointer items-center gap-1 text-xs"><Icon name="filter" size={12}/>Filter</div>
            </div>
            {txs.slice(0, 6).map((tx, i) => {
              const cat = catById(tx.category);
              const inc = tx.amount > 0;
              return (
                <button
                  key={tx.id}
                  type="button"
                  onClick={() => openTransaction(tx.id)}
                  className={cn('hover:bg-secondary/40 flex w-full cursor-pointer items-center gap-3 px-[18px] py-3 text-left', i && 'border-border border-t-[0.5px]')}
                >
                  <CatBar hue={cat.hue} />
                  <div className="flex-1">
                    <div className="text-[13px] font-medium">{tx.merchant}</div>
                    <div className="text-muted-foreground mt-0.5 text-[11px]">{tx.date.replace(/-/g, '/')}{tx.time ? ' ' + tx.time.slice(0, 5) : ''} · {cat.name || 'Income'}</div>
                  </div>
                  <Money value={tx.amount} signed={inc} className={cn('font-mono text-[13px] font-semibold', inc ? 'text-success' : 'text-foreground')}/>
                </button>
              );
            })}
          </div>

          <div className="bg-card border-border hidden rounded-[14px] border p-[18px] md:block">
            <div className="text-muted-foreground mb-2.5 font-mono text-[10px] tracking-[1.2px]">
              ACCOUNT DETAILS
            </div>
            {details.map(([l, v], i) => (
              <div key={l} className={cn('flex justify-between py-2 text-xs', i && 'border-border border-t-[0.5px] border-dotted')}>
                <span className="text-muted-foreground">{l}</span>
                <span className="font-mono">{v}</span>
              </div>
            ))}
            <div className="bg-secondary text-secondary-foreground mt-3.5 flex items-center gap-2 rounded-lg px-3.5 py-2.5 text-xs">
              <Icon name="sync" size={12}/>Auto-categorize: on
            </div>
          </div>
        </div>
      </div>

      <Sheet open={detailsOpen} onOpenChange={setDetailsOpen}>
        <SheetContent side="bottom" className="rounded-t-2xl pb-8 md:hidden">
          <SheetHeader>
            <SheetTitle className="font-serif text-xl italic">Account details</SheetTitle>
          </SheetHeader>
          <div className="px-4">
            {details.map(([l, v], i) => (
              <div key={l} className={cn('flex justify-between py-2.5 text-sm', i && 'border-border border-t-[0.5px] border-dotted')}>
                <span className="text-muted-foreground">{l}</span>
                <span className="font-mono">{v}</span>
              </div>
            ))}
            <div className="bg-secondary text-secondary-foreground mt-4 flex items-center gap-2 rounded-lg px-3.5 py-2.5 text-sm">
              <Icon name="sync" size={14}/>Auto-categorize: on
            </div>
            <Button variant="outline" className="mt-4 w-full" onClick={openEdit}>
              <Icon name="edit" size={14} />Edit details
            </Button>
          </div>
        </SheetContent>
      </Sheet>

      <Dialog open={editOpen} onOpenChange={setEditOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit account</DialogTitle>
            <DialogDescription>{name}</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="acct-name">Name</Label>
              <Input id="acct-name" value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} autoFocus />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="acct-type">Type</Label>
                <Select value={draft.type} onValueChange={(v) => setDraft({ ...draft, type: v })}>
                  <SelectTrigger id="acct-type" className="w-full"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {ACCOUNT_TYPE_OPTIONS.map((o) => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="acct-currency">Currency</Label>
                <Select value={draft.currency} onValueChange={(v) => setDraft({ ...draft, currency: v })}>
                  <SelectTrigger id="acct-currency" className="w-full"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {Object.keys(CURRENCIES).map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            </div>
          </div>
          <DialogFooter className="sm:justify-between">
            <Button variant="ghost" className="text-destructive hover:text-destructive" onClick={() => { setEditOpen(false); setConfirmArchive(true); }}>
              <Icon name="trash" size={14} />Archive
            </Button>
            <div className="flex gap-2">
              <DialogClose asChild>
                <Button variant="outline">Cancel</Button>
              </DialogClose>
              <DialogClose asChild>
                <Button onClick={saveDetails}>Save</Button>
              </DialogClose>
            </div>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={confirmArchive} onOpenChange={setConfirmArchive}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Archive {name}?</DialogTitle>
            <DialogDescription>
              The account is hidden from your lists but its transaction history is kept. You can&rsquo;t undo this from the app.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button variant="destructive" onClick={doArchive}>Archive</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={reconcileOpen} onOpenChange={setReconcileOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Reconcile {name}</DialogTitle>
            <DialogDescription>
              Set the actual balance — we&rsquo;ll record an adjustment for the difference.
              Adjustments don&rsquo;t count toward spending or income.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <Label>Current balance</Label>
              <div className="text-muted-foreground text-sm">{balance.toLocaleString()}</div>
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="reconcile-target">Target balance</Label>
              <Input
                id="reconcile-target"
                type="number"
                inputMode="decimal"
                value={reconcileTarget}
                onChange={(e) => setReconcileTarget(e.target.value)}
                autoFocus
              />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="reconcile-note">Note (optional)</Label>
              <Input
                id="reconcile-note"
                value={reconcileNote}
                onChange={(e) => setReconcileNote(e.target.value)}
                placeholder="e.g. Manual reconcile after bank statement"
              />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button onClick={submitReconcile}>Adjust</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MobilePage>
  );
}
