'use client';

import Link from 'next/link';
import { useState } from 'react';
import { toast } from 'sonner';
import { Icon, Sparkline } from '@/components/primitives';
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
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { LEDGER, CURRENCIES } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { cn } from '@/lib/utils';

const SOURCE_STYLE: Record<string, string> = {
  ECB: 'bg-success/10 text-success',
  Yahoo: 'bg-primary/10 text-primary',
  manual: 'bg-warning/10 text-warning',
};
const SOURCES = ['ECB', 'Yahoo', 'manual'];

/**
 * Exchange-rate management: the per-currency rate list (with trend sparkline and
 * source) plus an add/delete dialog. Rates are SGD-pivoted ledger reference data,
 * so this lives under Settings › Ledger.
 */
export function ExchangeRates() {
  const storeRates = useFinanceStore((s) => s.exchangeRates);
  const setExchangeRate = useFinanceStore((s) => s.setExchangeRate);
  const deleteExchangeRate = useFinanceStore((s) => s.deleteExchangeRate);
  // Projected DB rows once hydrated; static LEDGER data as the SSR fallback.
  const rates = storeRates.length ? storeRates : LEDGER.exchangeRates;
  const editable = storeRates.length > 0;
  const currencies = [...new Set(rates.map((r) => r.currency))];
  const byCurrency = currencies.map((cur) => {
    const series = rates
      .filter((r) => r.currency === cur)
      .slice()
      .sort((a, b) => (a.date < b.date ? -1 : 1));
    return { cur, latest: series[series.length - 1], values: series.map((s) => s.rate) };
  });

  const today = new Date().toISOString().slice(0, 10);
  const EMPTY = { date: today, currency: 'JPY', rate: '', source: 'manual' };
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState(EMPTY);
  const openAdd = () => {
    setDraft({ ...EMPTY, date: today });
    setOpen(true);
  };
  const submit = () => {
    const rate = Number(draft.rate);
    if (!(rate > 0)) return void toast.error('Enter a rate greater than 0');
    setExchangeRate({ date: draft.date, currency: draft.currency, rate, source: draft.source });
    toast.success(`${draft.currency} → SGD set`, { description: `${rate} on ${draft.date}` });
    setOpen(false);
  };

  return (
    <div>
      <div className="bg-card border-border overflow-hidden rounded-xl border">
        {byCurrency.map((row, i) => (
          <div key={row.cur} className={cn('flex items-center gap-3 p-3.5', i && 'border-border border-t')}>
            <div className="w-10 font-mono text-sm font-semibold">{row.cur}</div>
            <div className="flex-1">
              {row.values.length > 1 ? (
                <Sparkline values={row.values} width={120} height={26} color="var(--primary)" />
              ) : (
                <span className="text-muted-foreground text-[11px]">single point</span>
              )}
            </div>
            <span
              className={cn(
                'rounded px-1.5 py-0.5 font-mono text-[9px] uppercase',
                SOURCE_STYLE[row.latest.source ?? ''] ?? 'bg-secondary text-muted-foreground',
              )}
            >
              {row.latest.source ?? 'manual'}
            </span>
            <div className="w-24 text-right font-mono text-[13px] tabular-nums">{row.latest.rate.toFixed(5)}</div>
            {editable && (
              <button
                type="button"
                aria-label={`Delete latest ${row.cur} rate`}
                onClick={() => {
                  deleteExchangeRate(row.latest.date, row.cur);
                  toast.success(`${row.cur} rate removed`, { description: row.latest.date });
                }}
                className="text-muted-foreground hover:text-destructive ml-1"
              >
                <Icon name="trash" size={13} />
              </button>
            )}
          </div>
        ))}
      </div>
      <div className="mt-2.5 flex items-center justify-between px-1">
        <Link href="/fx" className="text-primary text-xs">
          See a locked FX transaction →
        </Link>
        <Button variant="outline" size="sm" onClick={openAdd}>
          <Icon name="plus" size={12} />
          Add rate
        </Button>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Add exchange rate</DialogTitle>
            <DialogDescription>
              How many SGD equals one unit of the foreign currency (SGD-pivoted). Used by display
              conversion and locked into new transactions at insert time.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-3">
            <div className="grid grid-cols-2 gap-3">
              <div className="flex flex-col gap-1.5">
                <Label>Currency</Label>
                <Select value={draft.currency} onValueChange={(v) => setDraft({ ...draft, currency: v })}>
                  <SelectTrigger className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {Object.keys(CURRENCIES)
                      .filter((c) => c !== 'SGD')
                      .map((c) => (
                        <SelectItem key={c} value={c}>
                          {c}
                        </SelectItem>
                      ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="rate-date">Date</Label>
                <Input
                  id="rate-date"
                  type="date"
                  value={draft.date}
                  onChange={(e) => setDraft({ ...draft, date: e.target.value })}
                />
              </div>
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="rate-value">Rate (1 {draft.currency} = ? SGD)</Label>
              <Input
                id="rate-value"
                type="number"
                inputMode="decimal"
                step="0.000001"
                value={draft.rate}
                onChange={(e) => setDraft({ ...draft, rate: e.target.value })}
                placeholder="0.00872"
                autoFocus
              />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label>Source</Label>
              <Select value={draft.source} onValueChange={(v) => setDraft({ ...draft, source: v })}>
                <SelectTrigger className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {SOURCES.map((s) => (
                    <SelectItem key={s} value={s}>
                      {s}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button onClick={submit}>Save</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
