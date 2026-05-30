'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Icon, CatBar } from '@/components/primitives';
import { useMoney } from '@/components/use-money';
import { catById, acctById, MOCK, fmtNative } from '@/lib/data';
import { useFinanceStore, type Tx, type TxSplitInput } from '@/lib/store';
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

interface SplitRow {
  key: string;
  categoryId: string;
  amount: string;
  description: string;
}

const r2 = (n: number) => Math.round(n * 100) / 100;
const nextKey = (() => {
  let k = 0;
  return () => `r-${++k}`;
})();

function rowsFromTx(tx: Tx, fallbackCategoryId: string): SplitRow[] {
  if (tx.splits?.length) {
    return tx.splits.map((s) => ({
      key: s.id,
      categoryId: s.categoryId ?? fallbackCategoryId,
      amount: String(Math.abs(s.amount).toFixed(2)),
      description: s.description ?? '',
    }));
  }
  const targetAbs = Math.abs(tx.nativeAmount ?? tx.amount);
  const half = r2(targetAbs / 2);
  return [
    { key: nextKey(), categoryId: tx.category ?? fallbackCategoryId, amount: half.toFixed(2), description: '' },
    { key: nextKey(), categoryId: fallbackCategoryId, amount: r2(targetAbs - half).toFixed(2), description: '' },
  ];
}

/**
 * Edits ad-hoc category splits for one transaction. The trigger element is
 * supplied as the child. Splits' magnitudes must sum to the parent's native
 * amount; on save we re-apply the parent's sign and send to the store.
 */
function SplitEditorBody({
  tx,
  categoryOptions,
  onClose,
}: {
  tx: Tx;
  categoryOptions: { id: string; name: string }[];
  onClose: () => void;
}) {
  const setTransactionSplits = useFinanceStore((s) => s.setTransactionSplits);
  const fallbackCategoryId = categoryOptions[0]?.id ?? '';
  const targetAbs = useMemo(() => Math.abs(tx.nativeAmount ?? tx.amount), [tx]);
  const sign = (tx.nativeAmount ?? tx.amount) < 0 ? -1 : 1;
  const currency = tx.currency ?? '';
  const [rows, setRows] = useState<SplitRow[]>(() => rowsFromTx(tx, fallbackCategoryId));

  const update = (key: string, patch: Partial<SplitRow>) =>
    setRows((rs) => rs.map((r) => (r.key === key ? { ...r, ...patch } : r)));
  const remove = (key: string) => setRows((rs) => rs.filter((r) => r.key !== key));
  const add = () => setRows((rs) => [...rs, { key: nextKey(), categoryId: fallbackCategoryId, amount: '0.00', description: '' }]);
  const balanceLast = () => {
    setRows((rs) => {
      if (rs.length === 0) return rs;
      const headSum = rs.slice(0, -1).reduce((s, r) => s + (parseFloat(r.amount) || 0), 0);
      const rem = r2(targetAbs - headSum);
      const last = rs[rs.length - 1];
      return [...rs.slice(0, -1), { ...last, amount: rem.toFixed(2) }];
    });
  };

  const parsedSum = rows.reduce((s, r) => s + (parseFloat(r.amount) || 0), 0);
  const diff = r2(targetAbs - parsedSum);
  const invalidRow = rows.some((r) => !(parseFloat(r.amount) > 0) || !r.categoryId);
  const tooFew = rows.length < 2;
  const sumOff = Math.abs(diff) > 0.005;
  const canSave = !tooFew && !invalidRow && !sumOff;

  const save = () => {
    const inputs: TxSplitInput[] = rows.map((r) => ({
      categoryId: r.categoryId,
      amount: sign * Math.abs(parseFloat(r.amount) || 0),
      description: r.description.trim() ? r.description.trim() : null,
    }));
    try {
      setTransactionSplits(tx.id, inputs);
      toast.success('Splits saved');
      onClose();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not save splits');
    }
  };

  const clearAll = () => {
    setTransactionSplits(tx.id, []);
    toast.success('Splits cleared');
    onClose();
  };

  const fmtTarget = currency ? fmtNative(targetAbs, currency) : targetAbs.toFixed(2);
  const fmtDiff = currency ? fmtNative(Math.abs(diff), currency) : Math.abs(diff).toFixed(2);

  return (
    <>
      <DialogHeader>
        <DialogTitle>Edit splits</DialogTitle>
        <DialogDescription>
          Allocate {fmtTarget} across categories. Splits must sum to the transaction amount.
        </DialogDescription>
      </DialogHeader>
      <div className="flex max-h-[55vh] flex-col gap-2 overflow-y-auto pr-1">
        {rows.map((r) => (
          <div key={r.key} className="grid grid-cols-[1fr_120px_32px] items-center gap-2">
            <Select value={r.categoryId} onValueChange={(v) => update(r.key, { categoryId: v })}>
              <SelectTrigger aria-label="Category" size="sm">
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
            <Input
              type="number"
              inputMode="decimal"
              step="0.01"
              min="0"
              aria-label="Amount"
              placeholder="0.00"
              value={r.amount}
              onChange={(e) => update(r.key, { amount: e.target.value })}
              className="h-8 text-right font-mono text-[12px]"
            />
            <button
              type="button"
              onClick={() => remove(r.key)}
              disabled={rows.length <= 1}
              className="text-muted-foreground hover:text-foreground disabled:opacity-30 flex h-8 w-8 items-center justify-center rounded-md"
              aria-label="Remove split"
            >
              <Icon name="x" size={14} />
            </button>
          </div>
        ))}
        <div className="flex items-center gap-2 pt-1">
          <Button size="sm" variant="outline" onClick={add} type="button">
            <Icon name="plus" size={12} />
            Add split
          </Button>
          <Button size="sm" variant="ghost" onClick={balanceLast} type="button">
            Balance to total
          </Button>
        </div>
      </div>
      <div className="border-border mt-2 flex items-center justify-between border-t pt-3 text-[12px]">
        <span className="text-muted-foreground">Target {fmtTarget}</span>
        {sumOff ? (
          <span className="text-warning">
            {diff > 0 ? `Short ${fmtDiff}` : `Over ${fmtDiff}`}
          </span>
        ) : (
          <span className="text-success">Balanced</span>
        )}
      </div>
      <DialogFooter className="flex-row justify-between sm:justify-between">
        <div>
          {tx.splits?.length ? (
            <Button variant="ghost" type="button" onClick={clearAll}>
              Clear splits
            </Button>
          ) : null}
        </div>
        <div className="flex gap-2">
          <DialogClose asChild>
            <Button variant="outline" type="button">
              Cancel
            </Button>
          </DialogClose>
          <Button type="button" onClick={save} disabled={!canSave}>
            Save
          </Button>
        </div>
      </DialogFooter>
    </>
  );
}

function SplitEditorDialog({
  tx,
  categoryOptions,
  children,
}: {
  tx: Tx;
  categoryOptions: { id: string; name: string }[];
  children: React.ReactNode;
}) {
  const [open, setOpen] = useState(false);
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>{children}</DialogTrigger>
      <DialogContent className="sm:max-w-lg">
        {open && (
          <SplitEditorBody tx={tx} categoryOptions={categoryOptions} onClose={() => setOpen(false)} />
        )}
      </DialogContent>
    </Dialog>
  );
}

/**
 * The transaction detail body — hero, quick actions, and detail rows.
 * Rendered both inside the right-side sheet and on the standalone /tx route.
 * Contains no page chrome (header/back/padding); the consumer supplies that.
 */
export function TransactionDetail({
  txId,
  onDeleted,
}: {
  txId: string;
  /** Called after the transaction is deleted, so the host can close the sheet
   *  or navigate away (the detail body would otherwise show "not found"). */
  onDeleted?: () => void;
}) {
  const { fmt, base } = useMoney();
  const tx = useFinanceStore((s) => s.transactions.find((t) => t.id === txId));
  const updateTransaction = useFinanceStore((s) => s.updateTransaction);
  const deleteTransaction = useFinanceStore((s) => s.deleteTransaction);
  const storeCats = useFinanceStore((s) => s.categories);
  const storeTags = useFinanceStore((s) => s.tags);
  const createTag = useFinanceStore((s) => s.createTag);
  const setTransactionTags = useFinanceStore((s) => s.setTransactionTags);
  const [newTag, setNewTag] = useState('');
  const [confirmDeleteOpen, setConfirmDeleteOpen] = useState(false);

  // Category options come from the projected store, scoped to this tx's ledger.
  const ledgerId = tx?.ledgerId ?? 'personal';
  const cats = storeCats.filter((c) => c.ledgerId === ledgerId).map((x) => ({ id: x.id, name: x.name }));

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

  const remove = () => {
    deleteTransaction(tx.id);
    toast.success('Transaction deleted');
    setConfirmDeleteOpen(false);
    onDeleted?.();
  };

  const splits = tx.splits ?? [];
  const categoryNameById = new Map(categoryOptions.map((c) => [c.id, c.name]));

  return (
    <>
      <div className="px-6 pb-7 text-center">
        <CatBar hue={cat.hue} className="mx-auto mb-4 block h-1 w-10" />
        <div className="text-muted-foreground font-serif text-[22px] italic">
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
        <SplitEditorDialog tx={tx} categoryOptions={categoryOptions}>
          <button
            type="button"
            className={cn(
              'flex h-[60px] flex-1 cursor-pointer flex-col items-center justify-center gap-1 rounded-xl border',
              splits.length ? 'border-primary text-primary' : 'border-border text-foreground',
            )}
          >
            <Icon name="split" size={18} />
            <span className="text-[10px] font-medium">{splits.length ? `Split (${splits.length})` : 'Split'}</span>
          </button>
        </SplitEditorDialog>
        <button
          type="button"
          onClick={() => setConfirmDeleteOpen(true)}
          className="border-border text-destructive hover:border-destructive flex h-[60px] flex-1 cursor-pointer flex-col items-center justify-center gap-1 rounded-xl border transition-colors"
        >
          <Icon name="x" size={18} />
          <span className="text-[10px] font-medium">Delete</span>
        </button>
      </div>

      <div className="bg-card border-border rounded-[14px] border px-4 py-1">
        <div className="border-border flex items-center justify-between py-2 text-[13px]">
          <span className="text-muted-foreground">Category</span>
          {splits.length ? (
            <span className="text-muted-foreground text-[12px] italic">Split across {splits.length} categories</span>
          ) : (
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
          )}
        </div>
        {[
          { l: 'Account', v: acctLabel },
          ...(tx.currency && tx.currency !== base && tx.nativeAmount != null
            ? [{ l: 'Original', v: fmtNative(Math.abs(tx.nativeAmount), tx.currency) }]
            : []),
          { l: 'Status', v: tx.pending ? 'Pending' : 'Posted' },
          { l: 'Note', v: tx.note || '—' },
        ].map((r) => (
          <div key={r.l} className="border-border flex items-center justify-between border-t-[0.5px] py-3 text-[13px]">
            <span className="text-muted-foreground">{r.l}</span>
            <span>{r.v}</span>
          </div>
        ))}
      </div>

      {splits.length > 0 && (
        <div className="mt-4">
          <div className="text-muted-foreground mb-2 px-1 font-mono text-[10px] tracking-wider uppercase">Splits</div>
          <div className="bg-card border-border divide-border divide-y rounded-[14px] border px-4">
            {splits.map((s) => (
              <div key={s.id} className="flex items-center justify-between py-2.5 text-[13px]">
                <div className="flex flex-col">
                  <span>{s.categoryId ? categoryNameById.get(s.categoryId) ?? '—' : 'Uncategorized'}</span>
                  {s.description && (
                    <span className="text-muted-foreground text-[11px]">{s.description}</span>
                  )}
                </div>
                <span className="font-mono">{fmt(Math.abs(s.amountBase))}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {(() => {
        const ledgerTags = storeTags.filter((t) => t.ledgerId === ledgerId);
        const applied = tx.tags ?? [];
        const available = ledgerTags.filter((t) => !applied.includes(t.id));
        const tagById = new Map(ledgerTags.map((t) => [t.id, t]));
        const addTag = (id: string) => setTransactionTags(tx.id, [...applied, id]);
        const removeTag = (id: string) => setTransactionTags(tx.id, applied.filter((x) => x !== id));
        const submitNewTag = () => {
          const n = newTag.trim();
          if (!n) return;
          const id = createTag({ name: n, ledgerId });
          setTransactionTags(tx.id, [...applied, id]);
          setNewTag('');
        };
        return (
          <div className="mt-4">
            <div className="text-muted-foreground mb-2 px-1 font-mono text-[10px] tracking-wider uppercase">Tags</div>
            <div className="flex flex-wrap items-center gap-1.5">
              {applied.map((id) => {
                const t = tagById.get(id);
                return (
                  <button
                    key={id}
                    type="button"
                    onClick={() => removeTag(id)}
                    className="bg-secondary text-secondary-foreground flex items-center gap-1 rounded-lg px-2.5 py-1 text-[11px]"
                    style={t?.color ? { color: `oklch(0.55 0.15 ${t.color})` } : undefined}
                  >
                    {t?.name ?? id}
                    <Icon name="x" size={11} />
                  </button>
                );
              })}
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <button
                    type="button"
                    className="text-muted-foreground hover:text-foreground rounded-lg border border-dashed px-2.5 py-1 text-[11px]"
                  >
                    + tag
                  </button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="start">
                  {available.map((t) => (
                    <DropdownMenuItem key={t.id} onSelect={() => addTag(t.id)}>
                      {t.name}
                    </DropdownMenuItem>
                  ))}
                  {available.length === 0 && (
                    <div className="text-muted-foreground px-2 py-1.5 text-[11px]">All tags applied</div>
                  )}
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
            <div className="mt-2 flex items-center gap-1.5">
              <Input
                value={newTag}
                onChange={(e) => setNewTag(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && submitNewTag()}
                placeholder="New tag…"
                className="h-7 w-36 text-[11px]"
              />
              <Button size="sm" variant="outline" className="h-7" onClick={submitNewTag}>
                Create
              </Button>
            </div>
          </div>
        );
      })()}

      <Dialog open={confirmDeleteOpen} onOpenChange={setConfirmDeleteOpen}>
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
