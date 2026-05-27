'use client';

import { useParams } from 'next/navigation';
import { useEffect, useState } from 'react';
import Link from 'next/link';
import { toast } from 'sonner';
import { Icon, Money, CatBar } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
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
import { useMoney } from '@/components/use-money';
import { useTransactionSheet } from '@/components/transaction-sheet';
import { useDb } from '@/components/db-provider';
import { listTransactions } from '@/lib/db/queries/transactions';
import { listAccounts } from '@/lib/db/queries/accounts';
import { MOCK, catById } from '@/lib/data';
import { useFinanceStore, type Tx } from '@/lib/store';
import { cn } from '@/lib/utils';

export default function AccountDetailPage() {
  const { display } = useMoney();
  const params = useParams();
  const accountId = params.id as string;
  const account = MOCK.accounts.find(a => a.id === accountId) || MOCK.accounts[0];
  const ledgerId = (account as { ledger?: string }).ledger ?? 'personal';
  const override = useFinanceStore((s) => s.accountOverrides)[accountId];
  const setAccountDetails = useFinanceStore((s) => s.setAccountDetails);
  const storeTxs = useFinanceStore((s) => s.transactions).filter(t => t.account === account.id);
  const { exec, version } = useDb();

  // Transaction list and live balance come from the DB; store fallback until ready.
  const [dbTxs, setDbTxs] = useState<Tx[] | null>(null);
  const [dbBalance, setDbBalance] = useState<number | null>(null);
  useEffect(() => {
    if (!exec) return;
    let cancelled = false;
    Promise.all([listTransactions(exec, { ledgerId, accountId }), listAccounts(exec, ledgerId)])
      .then(([rows, accts]) => {
        if (cancelled) return;
        setDbTxs(rows);
        const a = accts.find((x) => x.id === accountId);
        setDbBalance(a ? a.balance : null);
      })
      .catch((err) => console.error('Could not load account detail from DB', err));
    return () => {
      cancelled = true;
    };
  }, [exec, version, ledgerId, accountId]);
  const txs = dbTxs ?? storeTxs;
  const balance = dbBalance ?? account.balance;

  const [detailsOpen, setDetailsOpen] = useState(false);
  const [editOpen, setEditOpen] = useState(false);
  const [draft, setDraft] = useState({ name: '', type: 'checking', last4: '', institution: '', routing: '' });
  const { openTransaction } = useTransactionSheet();

  // Effective values: a saved override wins, otherwise fall back to the mock
  // account / a sensible default for fields the mock doesn't carry.
  const name = override?.name || account.name;
  const type = override?.type || account.type;
  const last4 = override?.last4 || account.last4;
  const institution = override?.institution || 'Chase Bank, N.A.';
  const routing = override?.routing || '021000021';

  const openEdit = () => {
    setDraft({ name, type, last4, institution, routing });
    setDetailsOpen(false);
    setEditOpen(true);
  };

  const saveDetails = () => {
    setAccountDetails(accountId, {
      name: draft.name.trim(),
      type: draft.type,
      last4: draft.last4.trim(),
      institution: draft.institution.trim(),
      routing: draft.routing.trim(),
    });
    toast.success('Account updated', { description: draft.name.trim() || account.name });
  };

  const details: [string, string][] = [
    ['Type', type.charAt(0).toUpperCase() + type.slice(1)],
    ['Number', `•••• ${last4}`],
    ['Routing', routing],
    ['Institution', institution],
    ['Currency', display],
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

        <div className="relative mb-6 overflow-hidden rounded-2xl px-7 py-5 text-white" style={{ background: account.color }}>
          <div className="absolute -top-[60px] -right-20 size-60 rounded-full bg-white/5"/>
          <div className="relative flex items-center justify-between gap-4">
            <div className="min-w-0 font-serif text-[40px] leading-none -tracking-[1.5px]">
              <Money value={balance} mono={false} className="font-serif"/>
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
        </div>

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
                    <div className="text-muted-foreground mt-0.5 text-[11px]">{tx.date.slice(5).replace('-','/')} · {cat.name || 'Income'}</div>
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
            <DialogDescription>{account.name}</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="acct-name">Name</Label>
              <Input id="acct-name" value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} autoFocus />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="acct-type">Type</Label>
              <Select value={draft.type} onValueChange={(v) => setDraft({ ...draft, type: v })}>
                <SelectTrigger id="acct-type" className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="checking">Checking</SelectItem>
                  <SelectItem value="savings">Savings</SelectItem>
                  <SelectItem value="credit">Credit</SelectItem>
                  <SelectItem value="invest">Investment</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="acct-last4">Number (last 4)</Label>
              <Input id="acct-last4" inputMode="numeric" maxLength={4} value={draft.last4} onChange={(e) => setDraft({ ...draft, last4: e.target.value })} />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="acct-institution">Institution</Label>
              <Input id="acct-institution" value={draft.institution} onChange={(e) => setDraft({ ...draft, institution: e.target.value })} />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="acct-routing">Routing</Label>
              <Input id="acct-routing" inputMode="numeric" value={draft.routing} onChange={(e) => setDraft({ ...draft, routing: e.target.value })} />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <DialogClose asChild>
              <Button onClick={saveDetails}>Save</Button>
            </DialogClose>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MobilePage>
  );
}
