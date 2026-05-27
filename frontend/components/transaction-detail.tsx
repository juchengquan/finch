'use client';

import { useEffect, useState } from 'react';
import { toast } from 'sonner';
import { Icon, MerchantGlyph } from '@/components/primitives';
import { useMoney } from '@/components/use-money';
import { catById, acctById, MOCK } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { useDb } from '@/components/db-provider';
import { listCategories } from '@/lib/db/queries/categories';
import { cn } from '@/lib/utils';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';

/**
 * The "more actions" dropdown (mark recurring / delete) shared by the
 * standalone /tx route header and the transaction sheet header.
 */
export function TransactionActionsMenu({
  txId,
  onDeleted,
}: {
  txId: string;
  onDeleted?: () => void;
}) {
  const { fmt } = useMoney();
  const tx = useFinanceStore((s) => s.transactions.find((t) => t.id === txId));
  const deleteTransaction = useFinanceStore((s) => s.deleteTransaction);
  const [confirmOpen, setConfirmOpen] = useState(false);

  if (!tx) return null;

  const remove = () => {
    deleteTransaction(tx.id);
    toast.success('Transaction deleted');
    setConfirmOpen(false);
    onDeleted?.();
  };

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            aria-label="More actions"
            className="border-border text-foreground flex size-9 cursor-pointer items-center justify-center rounded-full border"
          >
            <Icon name="dots" size={16} />
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem variant="destructive" onSelect={() => setConfirmOpen(true)}>
            <Icon name="x" size={14} />
            Delete
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <Dialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete transaction?</DialogTitle>
            <DialogDescription>
              {tx.merchant} · {fmt(Math.abs(tx.amount))} will be permanently removed. This can’t be undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button variant="destructive" onClick={remove}>
              Delete
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

/**
 * The transaction detail body — hero, quick actions, and detail rows.
 * Rendered both inside the right-side sheet and on the standalone /tx route.
 * Contains no page chrome (header/back/padding); the consumer supplies that.
 */
export function TransactionDetail({ txId }: { txId: string }) {
  const { fmt } = useMoney();
  const tx = useFinanceStore((s) => s.transactions.find((t) => t.id === txId));
  const updateTransaction = useFinanceStore((s) => s.updateTransaction);
  const addTransaction = useFinanceStore((s) => s.addTransaction);
  const { exec, version } = useDb();
  const [splitAmt, setSplitAmt] = useState('');
  const [splitCat, setSplitCat] = useState(MOCK.categories[0].id);

  // Category options come from the live DB, scoped to this transaction's ledger.
  const ledgerId = tx?.ledgerId ?? 'personal';
  const [cats, setCats] = useState<{ id: string; name: string }[]>([]);
  useEffect(() => {
    if (!exec) return;
    let cancelled = false;
    listCategories(exec, ledgerId)
      .then((c) => {
        if (cancelled) return;
        const opts = c.map((x) => ({ id: x.id, name: x.name }));
        setCats(opts);
        setSplitCat((prev) => (opts.some((o) => o.id === prev) ? prev : opts[0]?.id ?? prev));
      })
      .catch((err) => console.error('Could not load categories from DB', err));
    return () => {
      cancelled = true;
    };
  }, [exec, version, ledgerId]);

  if (!tx) {
    return (
      <div className="text-muted-foreground py-20 text-center text-sm">Transaction not found</div>
    );
  }

  const categoryOptions = cats.length
    ? cats
    : MOCK.categories
        .filter((c) => ((c as { ledger?: string }).ledger ?? 'personal') === ledgerId)
        .map((c) => ({ id: c.id, name: c.name }));

  const cat = catById(tx.category);
  const acct = acctById(tx.account);
  const when = new Date(`${tx.date}T${tx.time ?? '00:00'}`);
  const whenStr = `${when.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })} · ${when.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}`;
  const acctLabel = acct.last4 ? `${acct.name} · ${acct.last4}` : acct.name;

  const toggleRecurring = () => {
    updateTransaction(tx.id, { recurring: !tx.recurring });
    toast.success(tx.recurring ? 'Removed recurring' : 'Marked as recurring');
  };

  const origAbs = Math.abs(tx.amount);
  const sign = tx.amount < 0 ? -1 : 1;
  const doSplit = () => {
    const part = parseFloat(splitAmt);
    if (!part || part <= 0 || part >= origAbs) {
      toast.error(`Enter an amount between 0 and ${origAbs}`);
      return;
    }
    updateTransaction(tx.id, { amount: sign * (origAbs - part) });
    addTransaction({
      merchant: tx.merchant,
      category: splitCat,
      amount: sign * part,
      account: tx.account,
      date: tx.date,
      time: tx.time,
      note: `Split from ${tx.merchant}`,
      pending: tx.pending,
      ledgerId: tx.ledgerId,
    });
    setSplitAmt('');
    toast.success('Transaction split');
  };

  return (
    <>
      <div className="px-6 pb-7 text-center">
        <MerchantGlyph name={tx.merchant} size={64} hue={cat.hue} />
        <div className="text-muted-foreground mt-[18px] font-serif text-[22px] italic">
          {tx.amount > 0 ? 'You received from' : 'You spent at'}
        </div>
        <div className="mt-1 font-serif text-[34px] leading-none -tracking-[0.8px]">{tx.merchant}</div>
        <div className="mt-[18px] font-serif text-[56px] font-normal -tracking-[2px]">
          {fmt(Math.abs(tx.amount))}
        </div>
        <div className="text-muted-foreground mt-1.5 text-xs">
          {whenStr} · {acct.name}
        </div>
      </div>

      <div className="flex gap-2 pb-[22px]">
        <Dialog>
          <DialogTrigger asChild>
            <button
              type="button"
              className="border-border text-foreground flex h-[60px] flex-1 cursor-pointer flex-col items-center justify-center gap-1 rounded-xl border"
            >
              <Icon name="split" size={18} />
              <span className="text-[10px] font-medium">Split</span>
            </button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Split transaction</DialogTitle>
              <DialogDescription>
                Move part of {fmt(origAbs)} into another category.
              </DialogDescription>
            </DialogHeader>
            <div className="flex flex-col gap-3">
              <div className="flex items-center gap-2">
                <span className="text-muted-foreground font-serif text-xl">$</span>
                <Input
                  type="number"
                  inputMode="decimal"
                  aria-label="Split amount"
                  placeholder="0.00"
                  value={splitAmt}
                  onChange={(e) => setSplitAmt(e.target.value)}
                  autoFocus
                />
              </div>
              <Select value={splitCat} onValueChange={setSplitCat}>
                <SelectTrigger aria-label="Split category">
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
            </div>
            <DialogFooter>
              <DialogClose asChild>
                <Button variant="outline">Cancel</Button>
              </DialogClose>
              <DialogClose asChild>
                <Button onClick={doSplit}>Split</Button>
              </DialogClose>
            </DialogFooter>
          </DialogContent>
        </Dialog>
        <button
          type="button"
          onClick={toggleRecurring}
          className={cn(
            'flex h-[60px] flex-1 cursor-pointer flex-col items-center justify-center gap-1 rounded-xl border',
            tx.recurring ? 'border-primary text-primary' : 'border-border text-foreground',
          )}
        >
          <Icon name="sync" size={18} />
          <span className="text-[10px] font-medium">Recurring</span>
        </button>
        <button
          type="button"
          onClick={() => toast('Receipt — coming soon')}
          className="border-border text-foreground flex h-[60px] flex-1 cursor-pointer flex-col items-center justify-center gap-1 rounded-xl border"
        >
          <Icon name="cam" size={18} />
          <span className="text-[10px] font-medium">Receipt</span>
        </button>
      </div>

      <div className="bg-card border-border rounded-[14px] border px-4 py-1">
        <div className="border-border flex items-center justify-between py-2 text-[13px]">
          <span className="text-muted-foreground">Category</span>
          <Select
            value={tx.category ?? 'uncategorized'}
            onValueChange={(v) => {
              updateTransaction(tx.id, { category: v === 'uncategorized' ? null : v });
              toast.success('Category updated');
            }}
          >
            <SelectTrigger size="sm" className="h-7 border-0 shadow-none">
              <SelectValue placeholder="Uncategorized" />
            </SelectTrigger>
            <SelectContent align="end">
              {categoryOptions.map((c) => (
                <SelectItem key={c.id} value={c.id}>
                  {c.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        {[
          { l: 'Account', v: acctLabel },
          { l: 'Status', v: tx.pending ? 'Pending' : 'Posted' },
          { l: 'Note', v: tx.note || '—' },
          { l: 'Recurring', v: tx.recurring ? 'Yes' : 'No' },
        ].map((r) => (
          <div key={r.l} className="border-border flex items-center justify-between border-t-[0.5px] py-3 text-[13px]">
            <span className="text-muted-foreground">{r.l}</span>
            <span>{r.v}</span>
          </div>
        ))}
      </div>
    </>
  );
}
