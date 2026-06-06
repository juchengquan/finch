'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Icon, CatBar } from '@/components/primitives';
import { useMoney } from '@/components/use-money';
import { catById, acctById, MOCK, fmtNative } from '@/lib/data';
import { useFinanceStore, type Tx, type TxSplitInput } from '@/lib/store';
import { useLedger } from '@/components/ledger-provider';
import { RuleBuilderSheet, type RulePrefill } from '@/components/rule-builder-sheet';
import type { Leaf, Action } from '@/lib/rules/types';
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
import { Label } from '@/components/ui/label';
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
import { useEditTransaction } from '@/components/edit-transaction-sheet';

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
 * Records a refund against an expense. A refund is a positive `kind='refund'`
 * row linked back via `refundedTransactionId`; it nets against the original's
 * category (not income). Amount + category + account are pre-filled from the
 * original; the user can adjust the amount (e.g. a partial return).
 */
function RefundDialog({ tx, onClose }: { tx: Tx; onClose: () => void }) {
  const addTransaction = useFinanceStore((s) => s.addTransaction);
  const nativeMag = Math.abs(tx.nativeAmount ?? tx.amount);
  const baseMag = Math.abs(tx.amount);
  // Reuse the original's native→base rate for the optimistic base figure; the
  // server re-derives + locks the real rate for the refund's own date on sync.
  const rate = nativeMag ? baseMag / nativeMag : 1;
  const currency = tx.currency ?? '';
  const [amount, setAmount] = useState(nativeMag.toFixed(2));
  const value = parseFloat(amount);
  const valid = value > 0;
  const over = value > nativeMag + 0.005;

  const submit = () => {
    if (!valid) {
      toast.error('Enter a refund amount');
      return;
    }
    addTransaction({
      merchant: `Refund · ${tx.merchant}`,
      category: tx.category,
      amount: r2(value * rate), // ledger base, positive (optimistic; server re-derives)
      nativeAmount: value, // native, positive
      currency: tx.currency,
      account: tx.account,
      date: new Date().toISOString().slice(0, 10),
      time: new Date().toTimeString().slice(0, 5),
      note: '',
      pending: false,
      ledgerId: tx.ledgerId,
      kind: 'refund',
      refundedTransactionId: tx.id,
    });
    toast.success('Refund recorded', {
      description: currency ? fmtNative(value, currency) : value.toFixed(2),
    });
    onClose();
  };

  return (
    <DialogContent>
      <DialogHeader>
        <DialogTitle>Refund this purchase</DialogTitle>
        <DialogDescription>
          Records money coming back from {tx.merchant}. It nets against the original&rsquo;s category, not income.
        </DialogDescription>
      </DialogHeader>
      <div className="flex flex-col gap-3">
        <div className="flex flex-col gap-1.5">
          <Label htmlFor="refund-amount">Amount{currency ? ` · ${currency}` : ''}</Label>
          <Input
            id="refund-amount"
            type="number"
            inputMode="decimal"
            step="0.01"
            min="0"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
          />
          {over && (
            <p className="text-warning text-[11px]">
              More than the original {fmtNative(nativeMag, currency)} — allowed, but unusual.
            </p>
          )}
        </div>
        <div className="text-muted-foreground flex items-center justify-between text-[12px]">
          <span>Category</span>
          <span>{catById(tx.category).name}</span>
        </div>
        <div className="text-muted-foreground flex items-center justify-between text-[12px]">
          <span>To account</span>
          <span>{acctById(tx.account).name}</span>
        </div>
      </div>
      <DialogFooter>
        <DialogClose asChild>
          <Button variant="outline">Cancel</Button>
        </DialogClose>
        <Button onClick={submit} disabled={!valid}>
          Record refund
        </Button>
      </DialogFooter>
    </DialogContent>
  );
}

/**
 * Reclassifies an income row as a refund. A refund must offset a real expense,
 * so the user is required to pick the original purchase; on confirm the row's
 * kind becomes 'refund', it links back via refundedTransactionId, and it adopts
 * the original's category so it nets against the right spend (not income). The
 * amount/sign is untouched — income and refund are both stored positive, so the
 * account balance doesn't move; only the classification changes.
 */
function ConvertToRefundDialog({ tx, onClose }: { tx: Tx; onClose: () => void }) {
  const allTxns = useFinanceStore((s) => s.transactions);
  const updateTransaction = useFinanceStore((s) => s.updateTransaction);
  const { fmt } = useMoney();
  const [query, setQuery] = useState('');
  const [selectedId, setSelectedId] = useState<string | null>(null);

  // Candidates: confirmed, non-transfer expenses in the same ledger — the same
  // notion of "refundable" used for the Refund button on an expense.
  const candidates = useMemo(() => {
    const q = query.trim().toLowerCase();
    return allTxns
      .filter((t) => (t.ledgerId ?? 'personal') === (tx.ledgerId ?? 'personal'))
      .filter((t) => !t.pending && !t.transferGroupId && (t.kind === 'expense' || (t.kind == null && t.amount < 0)))
      .filter((t) => (q ? t.merchant.toLowerCase().includes(q) : true))
      .slice(0, 50);
  }, [allTxns, tx.ledgerId, query]);

  const original = selectedId ? allTxns.find((t) => t.id === selectedId) : undefined;
  const over = original ? Math.abs(tx.amount) > Math.abs(original.amount) + 0.005 : false;

  const submit = () => {
    if (!original) {
      toast.error('Pick the purchase this refunds');
      return;
    }
    updateTransaction(tx.id, {
      kind: 'refund',
      refundedTransactionId: original.id,
      category: original.category, // net against the original's category, not income
    });
    toast.success('Converted to refund', { description: `Linked to ${original.merchant}` });
    onClose();
  };

  return (
    <DialogContent>
      <DialogHeader>
        <DialogTitle>Convert to refund</DialogTitle>
        <DialogDescription>
          Reclassifies this {fmt(Math.abs(tx.amount))} from income to a refund. Pick the purchase it offsets — it
          will net against that purchase&rsquo;s category instead of counting as income.
        </DialogDescription>
      </DialogHeader>
      <div className="flex flex-col gap-3">
        <Input
          aria-label="Search purchases"
          placeholder="Search a purchase by merchant…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <div className="border-border max-h-[260px] divide-y divide-border overflow-y-auto rounded-lg border">
          {candidates.length === 0 ? (
            <div className="text-muted-foreground px-3 py-6 text-center text-[13px]">No matching purchases</div>
          ) : (
            candidates.map((c) => (
              <button
                key={c.id}
                type="button"
                onClick={() => setSelectedId(c.id)}
                className={cn(
                  'flex w-full items-center justify-between px-3 py-2.5 text-left text-[13px]',
                  selectedId === c.id ? 'bg-secondary' : 'hover:bg-secondary/50',
                )}
              >
                <span className="flex flex-col">
                  <span className="truncate">{c.merchant}</span>
                  <span className="text-muted-foreground text-[11px]">
                    {c.date} · {catById(c.category).name}
                  </span>
                </span>
                <span className="font-mono">{fmt(Math.abs(c.amount))}</span>
              </button>
            ))
          )}
        </div>
        {over && original && (
          <p className="text-warning text-[11px]">
            More than the original {fmt(Math.abs(original.amount))} — allowed, but unusual.
          </p>
        )}
      </div>
      <DialogFooter>
        <DialogClose asChild>
          <Button variant="outline">Cancel</Button>
        </DialogClose>
        <Button onClick={submit} disabled={!original}>
          Convert to refund
        </Button>
      </DialogFooter>
    </DialogContent>
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
  const { activeId } = useLedger();
  const allTxns = useFinanceStore((s) => s.transactions);
  const tx = allTxns.find((t) => t.id === txId);
  const updateTransaction = useFinanceStore((s) => s.updateTransaction);
  const deleteTransaction = useFinanceStore((s) => s.deleteTransaction);
  const setReviewed = useFinanceStore((s) => s.setReviewed);
  const storeCats = useFinanceStore((s) => s.categories);
  const rules = useFinanceStore((s) => s.rules);
  // Inline "create rule" prompt: after the user manually picks a new
  // category, surface a non-blocking pill suggesting a forward-applying rule
  // for that (merchant, category) combo. INSPIRATION_IDEAS §4 + RULES_ENGINE_PLAN §6.
  const [suggestion, setSuggestion] = useState<{ merchant: string; categoryId: string } | null>(null);
  const [rulePrefill, setRulePrefill] = useState<RulePrefill | null>(null);
  const [ruleBuilderOpen, setRuleBuilderOpen] = useState(false);
  const storeTags = useFinanceStore((s) => s.tags);
  const createTag = useFinanceStore((s) => s.createTag);
  const setTransactionTags = useFinanceStore((s) => s.setTransactionTags);
  const [newTag, setNewTag] = useState('');
  const [confirmDeleteOpen, setConfirmDeleteOpen] = useState(false);
  const [refundOpen, setRefundOpen] = useState(false);
  const [convertOpen, setConvertOpen] = useState(false);
  const { openEditTransaction } = useEditTransaction();

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
  const acctLabel = acct.name;

  const remove = () => {
    deleteTransaction(tx.id);
    toast.success('Transaction deleted');
    setConfirmDeleteOpen(false);
    onDeleted?.();
  };

  const splits = tx.splits ?? [];
  const categoryNameById = new Map(categoryOptions.map((c) => [c.id, c.name]));

  // Refund wiring. Only confirmed, non-transfer expenses can be refunded; a row
  // that is itself a refund links back to its original via refundedTransactionId.
  const isRefund = tx.kind === 'refund';
  const isRefundable = !tx.pending && !tx.transferGroupId && (tx.kind === 'expense' || (tx.kind == null && tx.amount < 0));
  // An income can be reclassified as a refund of a prior expense; transfers and
  // already-typed non-income rows can't.
  const isConvertibleToRefund = !tx.transferGroupId && (tx.kind === 'income' || (tx.kind == null && tx.amount > 0));
  const refunds = allTxns.filter((t) => t.refundedTransactionId === tx.id && t.kind === 'refund');
  const refundTotalBase = refunds.reduce((s, r) => s + Math.abs(r.amount), 0);
  const refundedOriginal = tx.refundedTransactionId ? allTxns.find((t) => t.id === tx.refundedTransactionId) : undefined;

  return (
    <>
      <div className="px-6 pb-7 text-center">
        <CatBar color={cat.color} className="mx-auto mb-4 block h-1 w-10" />
        <div className="text-muted-foreground font-serif text-[22px] italic">
          {isRefund ? 'Refund from' : tx.amount > 0 ? 'You received from' : 'You spent at'}
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
        {isRefundable && (
          <button
            type="button"
            onClick={() => setRefundOpen(true)}
            className="border-border text-foreground hover:border-primary flex h-[60px] flex-1 cursor-pointer flex-col items-center justify-center gap-1 rounded-xl border transition-colors"
          >
            <Icon name="sync" size={18} />
            <span className="text-[10px] font-medium">Refund</span>
          </button>
        )}
        {isConvertibleToRefund && (
          <button
            type="button"
            onClick={() => setConvertOpen(true)}
            className="border-border text-foreground hover:border-primary flex h-[60px] flex-1 cursor-pointer flex-col items-center justify-center gap-1 rounded-xl border transition-colors"
          >
            <Icon name="sync" size={18} />
            <span className="text-[10px] font-medium">To refund</span>
          </button>
        )}
        <button
          type="button"
          onClick={() => openEditTransaction(tx.id)}
          className="border-border text-foreground hover:border-primary flex h-[60px] flex-1 cursor-pointer flex-col items-center justify-center gap-1 rounded-xl border transition-colors"
          aria-label="Edit transaction"
        >
          <Icon name="pencil" size={18} />
          <span className="text-[10px] font-medium">Edit</span>
        </button>
        <button
          type="button"
          onClick={() => setConfirmDeleteOpen(true)}
          className="border-border text-destructive hover:border-destructive flex h-[60px] flex-1 cursor-pointer flex-col items-center justify-center gap-1 rounded-xl border transition-colors"
        >
          <Icon name="x" size={18} />
          <span className="text-[10px] font-medium">Delete</span>
        </button>
      </div>

      {tx.currency && tx.currency !== base && tx.nativeAmount != null && (() => {
        const native = tx.nativeAmount;
        const baseAmt = tx.amount;
        const rate = native !== 0 ? baseAmt / native : 1;
        return (
          <div className="mb-4">
            <div className="grid grid-cols-2 gap-3">
              <div className="bg-card border-border rounded-[14px] border p-4">
                <div className="text-muted-foreground font-mono text-[9px] tracking-[1px]">ORIGINAL · {tx.currency}</div>
                <div className="mt-1 font-serif text-2xl">{fmtNative(Math.abs(native), tx.currency)}</div>
              </div>
              <div className="bg-card border-border rounded-[14px] border p-4">
                <div className="text-muted-foreground font-mono text-[9px] tracking-[1px]">BASE · {base} (LOCKED)</div>
                <div className="mt-1 font-serif text-2xl">{fmtNative(Math.abs(baseAmt), base)}</div>
              </div>
            </div>
            <div className="bg-secondary text-secondary-foreground mt-2 inline-flex items-center gap-2 rounded-[12px] px-3 py-1 font-mono text-[10px] tracking-[0.5px]">
              <Icon name="check" size={11} className="text-success" stroke={2} />
              RATE LOCKED @ {Math.abs(rate).toFixed(6)} · {tx.currency}→{base} · {tx.date}
            </div>
          </div>
        );
      })()}

      {suggestion && (
        <div className="bg-primary/5 border-primary/30 flex items-center gap-2 rounded-[14px] border px-3 py-2">
          <Icon name="sparkle" size={14} className="text-primary shrink-0" />
          <div className="min-w-0 flex-1 text-[12px]">
            Always categorize{' '}
            <span className="text-foreground font-medium">{suggestion.merchant}</span>{' '}
            as{' '}
            <span className="text-foreground font-medium">
              {catById(suggestion.categoryId).name ?? suggestion.categoryId}
            </span>
            ?
          </div>
          <button
            type="button"
            onClick={() => {
              const leaves: Leaf[] = [
                { field: 'merchant', op: 'contains', value: suggestion.merchant },
              ];
              const actions: Action[] = [
                { type: 'set_category', categoryId: suggestion.categoryId },
              ];
              setRulePrefill({
                name: `${suggestion.merchant} → ${catById(suggestion.categoryId).name ?? suggestion.categoryId}`,
                leaves,
                actions,
              });
              setRuleBuilderOpen(true);
              setSuggestion(null);
            }}
            className="text-primary shrink-0 text-[12px] font-medium underline-offset-2 hover:underline"
          >
            Create rule
          </button>
          <button
            type="button"
            onClick={() => setSuggestion(null)}
            aria-label="Dismiss"
            className="text-muted-foreground hover:text-foreground shrink-0 rounded p-1"
          >
            <Icon name="x" size={13} />
          </button>
        </div>
      )}

      <div className="bg-card border-border rounded-[14px] border px-4 py-1">
        <div className="border-border flex items-center justify-between py-2 text-[13px]">
          <span className="text-muted-foreground">Category</span>
          {splits.length ? (
            <span className="text-muted-foreground text-[12px] italic">Split across {splits.length} categories</span>
          ) : (
            <Select
              value={tx.category ?? 'uncategorized'}
              onValueChange={(v) => {
                const next = v === 'uncategorized' ? null : v;
                const prev = tx.category ?? null;
                updateTransaction(tx.id, { category: next });
                toast.success('Category updated');
                // Only offer the rule-create pill when:
                //   - it's a real change (not picking the same category)
                //   - we landed on a category (clearing → category isn't a "rule" pattern)
                //   - the merchant string is non-empty (the pattern needs something to match)
                //   - no existing rule already targets this (merchant, category) pair
                //     so we don't pester users who've already set the rule up
                const merchant = tx.merchant.trim();
                if (next && next !== prev && merchant) {
                  const already = rules.some((r) => {
                    if (r.ledgerId !== activeId) return false;
                    const lc = JSON.stringify(r.condition).toLowerCase();
                    if (!lc.includes(merchant.toLowerCase())) return false;
                    return r.actions.some(
                      (a) => a.type === 'set_category' && a.categoryId === next,
                    );
                  });
                  if (!already) setSuggestion({ merchant, categoryId: next });
                } else {
                  setSuggestion(null);
                }
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
          ...(isRefund ? [{ l: 'Refund of', v: refundedOriginal?.merchant ?? 'original removed' }] : []),
          { l: 'Status', v: tx.pending ? 'Pending' : 'Posted' },
          { l: 'Note', v: tx.note || '—' },
        ].map((r) => (
          <div key={r.l} className="border-border flex items-center justify-between border-t-[0.5px] py-3 text-[13px]">
            <span className="text-muted-foreground">{r.l}</span>
            <span>{r.v}</span>
          </div>
        ))}
        {!tx.pending && (
          <div className="border-border flex items-center justify-between border-t-[0.5px] py-3 text-[13px]">
            <span className="text-muted-foreground">Review</span>
            <button
              type="button"
              onClick={() => {
                const next = !tx.reviewedAt;
                setReviewed(tx.id, next);
                toast.success(next ? 'Marked reviewed' : 'Marked needs-review');
              }}
              className={cn(
                'focus-ring inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[12px] font-medium outline-none',
                tx.reviewedAt
                  ? 'bg-success/10 text-success'
                  : 'bg-secondary text-muted-foreground',
              )}
            >
              <Icon name={tx.reviewedAt ? 'check' : 'doc'} size={12} />
              {tx.reviewedAt ? 'Reviewed' : 'Needs review'}
            </button>
          </div>
        )}
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

      {refunds.length > 0 && (
        <div className="mt-4">
          <div className="text-muted-foreground mb-2 px-1 font-mono text-[10px] tracking-wider uppercase">Refunds</div>
          <div className="bg-card border-border divide-border divide-y rounded-[14px] border px-4">
            {refunds.map((rfd) => (
              <div key={rfd.id} className="flex items-center justify-between py-2.5 text-[13px]">
                <span className="text-muted-foreground">{rfd.date}</span>
                <span className="text-success font-mono">+{fmt(Math.abs(rfd.amount))}</span>
              </div>
            ))}
            <div className="flex items-center justify-between py-2.5 text-[13px]">
              <span>{refundTotalBase >= Math.abs(tx.amount) - 0.005 ? 'Fully refunded' : 'Refunded'}</span>
              <span className="font-mono">{fmt(refundTotalBase)} of {fmt(Math.abs(tx.amount))}</span>
            </div>
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
                    style={t?.color ? { color: t.color } : undefined}
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

      <Dialog open={refundOpen} onOpenChange={setRefundOpen}>
        {refundOpen && <RefundDialog tx={tx} onClose={() => setRefundOpen(false)} />}
      </Dialog>

      <Dialog open={convertOpen} onOpenChange={setConvertOpen}>
        {convertOpen && <ConvertToRefundDialog tx={tx} onClose={() => setConvertOpen(false)} />}
      </Dialog>

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

      <RuleBuilderSheet
        rule={null}
        open={ruleBuilderOpen}
        onClose={() => setRuleBuilderOpen(false)}
        prefill={rulePrefill ?? undefined}
      />
    </>
  );
}
