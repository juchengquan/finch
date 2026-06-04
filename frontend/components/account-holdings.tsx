'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Icon } from '@/components/primitives';
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
import { useFinanceStore } from '@/lib/store';
import { useMoney } from '@/components/use-money';
import { fmtNative } from '@/lib/data';
import {
  holdingsForAccount,
  holdingValue,
  holdingGainLoss,
  holdingsValueForAccount,
} from '@/lib/select';
import type { Holding } from '@/lib/db/queries/holdings';
import { cn } from '@/lib/utils';

interface Props {
  accountId: string;
  ledgerId: string;
  /** The account's own currency — used as the default for new holdings. */
  accountCurrency: string;
}

const today = () => new Date().toISOString().slice(0, 10);

/** Investment-account holdings panel: lists positions with live valuation +
 *  gain/loss, and offers add / edit (shares + cost basis) / price-update /
 *  delete dialogs. All amounts are in the holding's own currency. */
export function AccountHoldings({ accountId, ledgerId, accountCurrency }: Props) {
  const holdings = useFinanceStore((s) => s.holdings);
  const createHolding = useFinanceStore((s) => s.createHolding);
  const updateHolding = useFinanceStore((s) => s.updateHolding);
  const setHoldingPrice = useFinanceStore((s) => s.setHoldingPrice);
  const deleteHolding = useFinanceStore((s) => s.deleteHolding);
  const { fmtFrom } = useMoney();

  const rows = holdingsForAccount(holdings, accountId);
  const totalValue = holdingsValueForAccount(holdings, accountId);
  const totalCost = rows.reduce((s, h) => s + h.costBasis, 0);
  const totalGain = Math.round((totalValue - totalCost) * 100) / 100;

  const [addOpen, setAddOpen] = useState(false);
  const [editTarget, setEditTarget] = useState<Holding | null>(null);
  const [priceTarget, setPriceTarget] = useState<Holding | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<Holding | null>(null);

  return (
    <div className="bg-card border-border overflow-hidden rounded-[14px] border">
      <div className="border-border flex items-center justify-between border-b px-[18px] py-3.5">
        <div className="text-sm font-semibold">Holdings · {rows.length}</div>
        <Button variant="ghost" size="sm" onClick={() => setAddOpen(true)}>
          <Icon name="plus" size={13} />Add
        </Button>
      </div>

      {rows.length === 0 ? (
        <div className="px-[18px] py-8 text-center">
          <div className="text-muted-foreground text-sm">No positions yet</div>
          <div className="text-muted-foreground/70 mt-1 text-xs">
            Log a stock, ETF, or fund you hold to see its live valuation.
          </div>
        </div>
      ) : (
        <>
          {rows.map((h, i) => {
            const value = holdingValue(h);
            const gain = holdingGainLoss(h);
            return (
              <div key={h.id} className={cn('flex items-center gap-3 px-[18px] py-3', i && 'border-border border-t-[0.5px]')}>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <span className="text-[13px] font-semibold">{h.symbol}</span>
                    {h.name && <span className="text-muted-foreground truncate text-[11px]">{h.name}</span>}
                  </div>
                  <div className="text-muted-foreground mt-0.5 text-[11px] tabular-nums">
                    {h.shares.toLocaleString(undefined, { maximumFractionDigits: 4 })} shares · cost {fmtNative(h.costBasis, h.currency)}
                    {h.lastPrice != null && h.lastPriceDate && (
                      <> · @ {fmtNative(h.lastPrice, h.currency)} on {h.lastPriceDate.replace(/-/g, '/')}</>
                    )}
                  </div>
                </div>
                <div className="text-right">
                  {value == null ? (
                    <div className="text-muted-foreground text-[12px]">no quote</div>
                  ) : (
                    <>
                      <div className="font-mono text-[13px] font-semibold tabular-nums">{fmtNative(value, h.currency)}</div>
                      {gain != null && (
                        <div className={cn('mt-0.5 text-[11px] tabular-nums', gain >= 0 ? 'text-success' : 'text-destructive')}>
                          {gain >= 0 ? '+' : ''}{fmtNative(gain, h.currency)}
                        </div>
                      )}
                    </>
                  )}
                </div>
                <div className="flex shrink-0 items-center gap-1">
                  <Button size="icon" variant="ghost" className="size-8" aria-label={`Update ${h.symbol} price`} onClick={() => setPriceTarget(h)}>
                    <Icon name="sync" size={13} />
                  </Button>
                  <Button size="icon" variant="ghost" className="size-8" aria-label={`Edit ${h.symbol}`} onClick={() => setEditTarget(h)}>
                    <Icon name="edit" size={13} />
                  </Button>
                  <Button size="icon" variant="ghost" className="size-8" aria-label={`Delete ${h.symbol}`} onClick={() => setDeleteTarget(h)}>
                    <Icon name="trash" size={13} />
                  </Button>
                </div>
              </div>
            );
          })}

          <div className="border-border bg-secondary/40 border-t px-[18px] py-3">
            <div className="flex items-center justify-between text-[12px]">
              <span className="text-muted-foreground">Holdings value</span>
              <span className="font-mono font-semibold tabular-nums">{fmtNative(totalValue, accountCurrency)}</span>
            </div>
            <div className="text-muted-foreground mt-1 flex items-center justify-between text-[11px]">
              <span>≈ {fmtFrom(totalValue, accountCurrency)}</span>
              <span className={cn('tabular-nums', totalGain >= 0 ? 'text-success' : 'text-destructive')}>
                {totalGain >= 0 ? '+' : ''}{fmtNative(totalGain, accountCurrency)} unrealized
              </span>
            </div>
          </div>
        </>
      )}

      <AddHoldingDialog
        open={addOpen}
        onOpenChange={setAddOpen}
        accountId={accountId}
        ledgerId={ledgerId}
        defaultCurrency={accountCurrency}
        onCreate={(input) => createHolding(input)}
      />

      <EditHoldingDialog
        holding={editTarget}
        onClose={() => setEditTarget(null)}
        onSave={(id, patch) => {
          updateHolding(id, patch);
          toast.success(`Updated ${patch.symbol ?? editTarget?.symbol ?? 'holding'}`);
        }}
      />

      <PriceDialog
        holding={priceTarget}
        onClose={() => setPriceTarget(null)}
        onSave={(id, price, date) => {
          setHoldingPrice(id, price, date);
          toast.success(`Price updated`);
        }}
      />

      <Dialog open={deleteTarget != null} onOpenChange={(o) => !o && setDeleteTarget(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete {deleteTarget?.symbol}?</DialogTitle>
            <DialogDescription>
              The position is removed permanently. Transactions you logged for buys / sells / dividends are not touched.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <DialogClose asChild><Button variant="outline">Cancel</Button></DialogClose>
            <Button
              variant="destructive"
              onClick={() => {
                if (deleteTarget) {
                  deleteHolding(deleteTarget.id);
                  toast.success(`Removed ${deleteTarget.symbol}`);
                  setDeleteTarget(null);
                }
              }}
            >
              Delete
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Add / Edit / Price dialogs
// ---------------------------------------------------------------------------

interface AddInput {
  accountId: string;
  ledgerId?: string;
  symbol: string;
  name?: string | null;
  shares: number;
  costBasis: number;
  currency?: string;
  lastPrice?: number | null;
  lastPriceDate?: string | null;
}

function AddHoldingDialog({
  open,
  onOpenChange,
  accountId,
  ledgerId,
  defaultCurrency,
  onCreate,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  accountId: string;
  ledgerId: string;
  defaultCurrency: string;
  onCreate: (input: AddInput) => void;
}) {
  const [symbol, setSymbol] = useState('');
  const [name, setName] = useState('');
  const [shares, setShares] = useState('');
  const [costBasis, setCostBasis] = useState('');
  const [lastPrice, setLastPrice] = useState('');
  const [lastPriceDate, setLastPriceDate] = useState(today());

  const reset = () => {
    setSymbol('');
    setName('');
    setShares('');
    setCostBasis('');
    setLastPrice('');
    setLastPriceDate(today());
  };

  const submit = () => {
    const sym = symbol.trim().toUpperCase();
    if (!sym) return void toast.error('Enter a symbol');
    const s = parseFloat(shares);
    if (!Number.isFinite(s) || s <= 0) return void toast.error('Shares must be greater than 0');
    const c = parseFloat(costBasis);
    if (!Number.isFinite(c) || c < 0) return void toast.error('Cost basis must be 0 or greater');
    const price = lastPrice === '' ? null : parseFloat(lastPrice);
    if (price !== null && (!Number.isFinite(price) || price < 0)) return void toast.error('Price must be 0 or greater');
    // Holding currency is locked to the account's currency. Summing values
    // across mixed currencies without conversion would silently corrupt the
    // total — see code-review finding. A foreign-currency position belongs
    // in a foreign-currency investment account.
    onCreate({
      accountId,
      ledgerId,
      symbol: sym,
      name: name.trim() || null,
      shares: s,
      costBasis: c,
      currency: defaultCurrency,
      lastPrice: price,
      lastPriceDate: price == null ? null : lastPriceDate,
    });
    toast.success(`Added ${sym}`);
    reset();
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!o) reset(); onOpenChange(o); }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Add a holding</DialogTitle>
          <DialogDescription>Log a stock, ETF, or fund position you hold in this account.</DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-3">
          <div className="grid grid-cols-2 gap-3">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="h-symbol">Symbol</Label>
              <Input id="h-symbol" value={symbol} onChange={(e) => setSymbol(e.target.value)} placeholder="VTI" autoFocus />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="h-currency">Currency</Label>
              <div
                id="h-currency"
                className="border-input bg-muted text-muted-foreground flex h-9 w-full items-center rounded-md border px-3 text-sm"
              >
                {defaultCurrency}
              </div>
            </div>
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="h-name">Name (optional)</Label>
            <Input id="h-name" value={name} onChange={(e) => setName(e.target.value)} placeholder="Vanguard Total Stock Market ETF" />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="h-shares">Shares</Label>
              <Input id="h-shares" type="number" inputMode="decimal" value={shares} onChange={(e) => setShares(e.target.value)} placeholder="50" />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="h-cost">Cost basis (total paid)</Label>
              <Input id="h-cost" type="number" inputMode="decimal" value={costBasis} onChange={(e) => setCostBasis(e.target.value)} placeholder="11250" />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="h-price">Current price (optional)</Label>
              <Input id="h-price" type="number" inputMode="decimal" value={lastPrice} onChange={(e) => setLastPrice(e.target.value)} placeholder="248.50" />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="h-pdate">Price date</Label>
              <Input id="h-pdate" type="date" value={lastPriceDate} onChange={(e) => setLastPriceDate(e.target.value)} />
            </div>
          </div>
        </div>
        <DialogFooter>
          <DialogClose asChild><Button variant="outline">Cancel</Button></DialogClose>
          <Button onClick={submit}>Add</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function EditHoldingDialog({
  holding,
  onClose,
  onSave,
}: {
  holding: Holding | null;
  onClose: () => void;
  onSave: (id: string, patch: { symbol?: string; name?: string | null; shares?: number; costBasis?: number; notes?: string | null }) => void;
}) {
  // Keep the dialog mounted only while there's a target — wrapping the form in
  // a child component means useState seeds from the holding's current values
  // once, on mount, instead of needing an effect to sync them.
  return (
    <Dialog open={holding != null} onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        {holding && <EditHoldingForm key={holding.id} holding={holding} onClose={onClose} onSave={onSave} />}
      </DialogContent>
    </Dialog>
  );
}

function EditHoldingForm({
  holding,
  onClose,
  onSave,
}: {
  holding: Holding;
  onClose: () => void;
  onSave: (id: string, patch: { symbol?: string; name?: string | null; shares?: number; costBasis?: number; notes?: string | null }) => void;
}) {
  const [symbol, setSymbol] = useState(holding.symbol);
  const [name, setName] = useState(holding.name ?? '');
  const [shares, setShares] = useState(String(holding.shares));
  const [costBasis, setCostBasis] = useState(String(holding.costBasis));

  const submit = () => {
    const sym = symbol.trim().toUpperCase();
    if (!sym) return void toast.error('Enter a symbol');
    const s = parseFloat(shares);
    if (!Number.isFinite(s) || s <= 0) return void toast.error('Shares must be greater than 0');
    const c = parseFloat(costBasis);
    if (!Number.isFinite(c) || c < 0) return void toast.error('Cost basis must be 0 or greater');
    onSave(holding.id, { symbol: sym, name: name.trim() || null, shares: s, costBasis: c });
    onClose();
  };

  return (
    <>
      <DialogHeader>
        <DialogTitle>Edit {holding.symbol}</DialogTitle>
        <DialogDescription>Shares + cost basis. Update the price separately to refresh the live value.</DialogDescription>
      </DialogHeader>
      <div className="flex flex-col gap-3">
        <div className="grid grid-cols-2 gap-3">
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="he-symbol">Symbol</Label>
            <Input id="he-symbol" value={symbol} onChange={(e) => setSymbol(e.target.value)} />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="he-currency">Currency</Label>
            <div
              id="he-currency"
              className="border-input bg-muted text-muted-foreground flex h-9 w-full items-center rounded-md border px-3 text-sm"
            >
              {holding.currency}
            </div>
          </div>
        </div>
        <div className="flex flex-col gap-1.5">
          <Label htmlFor="he-name">Name (optional)</Label>
          <Input id="he-name" value={name} onChange={(e) => setName(e.target.value)} />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="he-shares">Shares</Label>
            <Input id="he-shares" type="number" inputMode="decimal" value={shares} onChange={(e) => setShares(e.target.value)} />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="he-cost">Cost basis (total paid)</Label>
            <Input id="he-cost" type="number" inputMode="decimal" value={costBasis} onChange={(e) => setCostBasis(e.target.value)} />
          </div>
        </div>
      </div>
      <DialogFooter>
        <Button variant="outline" onClick={onClose}>Cancel</Button>
        <Button onClick={submit}>Save</Button>
      </DialogFooter>
    </>
  );
}

function PriceDialog({
  holding,
  onClose,
  onSave,
}: {
  holding: Holding | null;
  onClose: () => void;
  onSave: (id: string, price: number | null, date: string | null) => void;
}) {
  return (
    <Dialog open={holding != null} onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        {holding && <PriceForm key={holding.id} holding={holding} onClose={onClose} onSave={onSave} />}
      </DialogContent>
    </Dialog>
  );
}

function PriceForm({
  holding,
  onClose,
  onSave,
}: {
  holding: Holding;
  onClose: () => void;
  onSave: (id: string, price: number | null, date: string | null) => void;
}) {
  const [price, setPrice] = useState(holding.lastPrice != null ? String(holding.lastPrice) : '');
  const [date, setDate] = useState(holding.lastPriceDate ?? today());

  const submit = () => {
    if (price === '') {
      onSave(holding.id, null, null);
      onClose();
      return;
    }
    const p = parseFloat(price);
    if (!Number.isFinite(p) || p < 0) return void toast.error('Price must be 0 or greater');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return void toast.error('Pick a valid date');
    onSave(holding.id, p, date);
    onClose();
  };

  return (
    <>
      <DialogHeader>
        <DialogTitle>Update {holding.symbol} price</DialogTitle>
        <DialogDescription>
          Per-share price in {holding.currency}. Leave blank to clear the quote.
        </DialogDescription>
      </DialogHeader>
      <div className="flex flex-col gap-3">
        <div className="grid grid-cols-2 gap-3">
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="hp-price">Price</Label>
            <Input id="hp-price" type="number" inputMode="decimal" value={price} onChange={(e) => setPrice(e.target.value)} autoFocus />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="hp-date">As of</Label>
            <Input id="hp-date" type="date" value={date} onChange={(e) => setDate(e.target.value)} />
          </div>
        </div>
      </div>
      <DialogFooter>
        <Button variant="outline" onClick={onClose}>Cancel</Button>
        <Button onClick={submit}>Save</Button>
      </DialogFooter>
    </>
  );
}
