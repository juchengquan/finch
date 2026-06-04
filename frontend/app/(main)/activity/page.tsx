'use client';

import { useMemo, useState } from 'react';
import { Money, Icon, CatBar } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { SearchButton } from '@/components/command-palette';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { catById, acctById } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { useLedger } from '@/components/ledger-provider';
import { useTransactionSheet } from '@/components/transaction-sheet';
import { RefundBadge } from '@/components/refund-badge';
import { AnomalyBadge } from '@/components/anomaly-badge';
import { merchantStats, anomalyScore } from '@/lib/select';
import { cn } from '@/lib/utils';

const FILTERS = [
  { id: 'all', label: 'All' },
  { id: 'out', label: 'Out' },
  { id: 'in', label: 'In' },
] as const;

type Filter = (typeof FILTERS)[number]['id'];

function dayLabel(date: string) {
  return new Date(`${date}T00:00`).toLocaleDateString('en-US', {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
  });
}

export default function ActivityPage() {
  const [filter, setFilter] = useState<Filter>('all');
  const [query, setQuery] = useState('');
  const [tagFilter, setTagFilter] = useState<string | null>(null);
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [fromDate, setFromDate] = useState('');
  const [toDate, setToDate] = useState('');
  const [minAmt, setMinAmt] = useState('');
  const [maxAmt, setMaxAmt] = useState('');
  const allTxns = useFinanceStore((s) => s.transactions);
  const allTags = useFinanceStore((s) => s.tags);
  const { activeId } = useLedger();
  const { openTransaction } = useTransactionSheet();
  const ledgerTags = allTags.filter((t) => t.ledgerId === activeId);
  // Per-merchant stats for the anomaly badge. One pass over the transaction
  // list per render; lookup per row is O(1). Memoized on the txn list + ledger
  // so we don't recompute on every render.
  const stats = useMemo(() => merchantStats(allTxns, activeId), [allTxns, activeId]);

  const minA = minAmt.trim() === '' ? null : Number(minAmt);
  const maxA = maxAmt.trim() === '' ? null : Number(maxAmt);
  const activeRangeCount =
    (fromDate ? 1 : 0) + (toDate ? 1 : 0) + (minA != null && Number.isFinite(minA) ? 1 : 0) + (maxA != null && Number.isFinite(maxA) ? 1 : 0);

  const txns = allTxns.filter((t) => {
    if ((t.ledgerId ?? 'personal') !== activeId) return false;
    if (filter === 'in' && t.amount <= 0) return false;
    if (filter === 'out' && t.amount >= 0) return false;
    if (query && !t.merchant.toLowerCase().includes(query.toLowerCase())) return false;
    if (tagFilter && !(t.tags ?? []).includes(tagFilter)) return false;
    if (fromDate && t.date < fromDate) return false;
    if (toDate && t.date > toDate) return false;
    if (minA != null && Number.isFinite(minA) && Math.abs(t.amount) < minA) return false;
    if (maxA != null && Number.isFinite(maxA) && Math.abs(t.amount) > maxA) return false;
    return true;
  });

  const clearRangeFilters = () => {
    setFromDate('');
    setToDate('');
    setMinAmt('');
    setMaxAmt('');
  };

  // Sort newest-first (date, then time) before grouping: the consecutive-run
  // grouping below assumes same-date rows are adjacent, but the store's order
  // isn't guaranteed date-contiguous (pre-hydration seed order, optimistic
  // prepends). Without this, one date can land in several groups → duplicate
  // `key={group.date}` React warnings.
  const sorted = [...txns].sort((a, b) => {
    if (a.date !== b.date) return a.date < b.date ? 1 : -1;
    const at = a.time ?? '';
    const bt = b.time ?? '';
    return at < bt ? 1 : at > bt ? -1 : 0;
  });
  const groups: { date: string; items: typeof txns }[] = [];
  for (const t of sorted) {
    const last = groups[groups.length - 1];
    if (last && last.date === t.date) last.items.push(t);
    else groups.push({ date: t.date, items: [t] });
  }

  return (
    <MobilePage
      header={<ScreenHeader title="Activity" trailing={<SearchButton />} />}
    >
      <div className="px-5 pb-[120px]">
        <div className="bg-secondary mb-3 flex h-9 items-center gap-2 rounded-full px-3.5">
          <Icon name="search" size={14} className="text-muted-foreground" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            aria-label="Search transactions" placeholder="Search transactions"
            className="placeholder:text-muted-foreground w-full bg-transparent text-[13px] outline-none"
          />
        </div>

        <div className="mb-4 flex items-center gap-2">
          <div className="bg-secondary flex flex-1 gap-1 rounded-full p-1">
            {FILTERS.map((f) => (
              <button
                key={f.id}
                type="button"
                onClick={() => setFilter(f.id)}
                className={cn(
                  'h-7 flex-1 rounded-full text-xs font-medium transition-colors',
                  filter === f.id ? 'bg-background text-foreground shadow-sm' : 'text-muted-foreground',
                )}
              >
                {f.label}
              </button>
            ))}
          </div>
          <button
            type="button"
            onClick={() => setFiltersOpen((o) => !o)}
            aria-label="Toggle filters"
            aria-expanded={filtersOpen}
            className={cn(
              'border-border flex h-9 cursor-pointer items-center gap-1.5 rounded-full border px-3 text-[11px] font-medium',
              activeRangeCount > 0 ? 'border-primary text-primary' : 'text-muted-foreground',
            )}
          >
            <Icon name="filter" size={13} />
            Filters{activeRangeCount > 0 ? ` · ${activeRangeCount}` : ''}
          </button>
        </div>

        {filtersOpen && (
          <div className="bg-card border-border mb-4 flex flex-col gap-3 rounded-xl border p-3.5">
            <div className="grid grid-cols-2 gap-3">
              <div className="flex flex-col gap-1">
                <Label htmlFor="filter-from" className="text-muted-foreground text-[11px]">From</Label>
                <Input id="filter-from" type="date" value={fromDate} onChange={(e) => setFromDate(e.target.value)} className="h-8 text-[12px]" />
              </div>
              <div className="flex flex-col gap-1">
                <Label htmlFor="filter-to" className="text-muted-foreground text-[11px]">To</Label>
                <Input id="filter-to" type="date" value={toDate} onChange={(e) => setToDate(e.target.value)} className="h-8 text-[12px]" />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="flex flex-col gap-1">
                <Label htmlFor="filter-min" className="text-muted-foreground text-[11px]">Min amount</Label>
                <Input
                  id="filter-min"
                  type="number"
                  inputMode="decimal"
                  min="0"
                  placeholder="0"
                  value={minAmt}
                  onChange={(e) => setMinAmt(e.target.value)}
                  className="h-8 text-right font-mono text-[12px]"
                />
              </div>
              <div className="flex flex-col gap-1">
                <Label htmlFor="filter-max" className="text-muted-foreground text-[11px]">Max amount</Label>
                <Input
                  id="filter-max"
                  type="number"
                  inputMode="decimal"
                  min="0"
                  placeholder="∞"
                  value={maxAmt}
                  onChange={(e) => setMaxAmt(e.target.value)}
                  className="h-8 text-right font-mono text-[12px]"
                />
              </div>
            </div>
            {activeRangeCount > 0 && (
              <div className="flex justify-end">
                <Button size="sm" variant="ghost" onClick={clearRangeFilters}>
                  Clear
                </Button>
              </div>
            )}
          </div>
        )}

        {ledgerTags.length > 0 && (
          <div className="mb-4 flex flex-wrap gap-1.5">
            {ledgerTags.map((t) => (
              <button
                key={t.id}
                type="button"
                onClick={() => setTagFilter((prev) => (prev === t.id ? null : t.id))}
                className={cn(
                  'rounded-lg px-2.5 py-1 text-[11px] transition-colors',
                  tagFilter === t.id
                    ? 'bg-foreground text-background'
                    : 'bg-secondary text-secondary-foreground',
                )}
              >
                {t.name}
              </button>
            ))}
          </div>
        )}

        {txns.length === 0 && (
          <div className="text-muted-foreground py-10 text-center text-sm">No transactions</div>
        )}

        {/* Mobile: grouped feed */}
        <div className="md:hidden">
          {groups.map((group) => (
            <div key={group.date} className="mb-4">
              <div className="text-muted-foreground mb-1 px-1 font-mono text-[10px] tracking-wider uppercase">
                {dayLabel(group.date)}
              </div>
              <div className="bg-card border-border overflow-hidden rounded-xl border">
                {group.items.map((t, i) => {
                  const cat = catById(t.category);
                  const inc = t.amount > 0;
                  return (
                    <button
                      key={t.id}
                      type="button"
                      onClick={() => openTransaction(t.id)}
                      className={cn('flex w-full items-center gap-3 p-3.5 text-left', i && 'border-border border-t')}
                    >
                      <CatBar color={cat.color} />
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-1.5">
                          <span className="truncate text-sm font-medium">{t.merchant}</span>
                          {t.kind === 'refund' && <RefundBadge />}
                          {(() => {
                            const a = anomalyScore(t, stats);
                            return a?.isAnomaly ? <AnomalyBadge zScore={a.zScore} mean={a.mean} /> : null;
                          })()}
                        </div>
                        <div className="text-muted-foreground mt-0.5 truncate text-[11px]">
                          {cat.name} · {acctById(t.account).name}
                          {t.pending && <span className="text-warning"> · pending</span>}
                        </div>
                      </div>
                      <Money
                        value={t.amount}
                        signed={inc}
                        className={cn('text-sm font-medium', inc ? 'text-success' : 'text-foreground')}
                      />
                    </button>
                  );
                })}
              </div>
            </div>
          ))}
        </div>

        {/* Desktop: table */}
        {txns.length > 0 && (
          <div className="bg-card border-border hidden overflow-hidden rounded-xl border md:block">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-muted-foreground border-border border-b text-left text-[11px] tracking-wide uppercase">
                  <th className="px-4 py-2.5 font-medium">Date</th>
                  <th className="px-4 py-2.5 font-medium">Merchant</th>
                  <th className="px-4 py-2.5 font-medium">Category</th>
                  <th className="px-4 py-2.5 font-medium">Account</th>
                  <th className="px-4 py-2.5 font-medium">Status</th>
                  <th className="px-4 py-2.5 text-right font-medium">Amount</th>
                </tr>
              </thead>
              <tbody>
                {txns.map((t) => {
                  const cat = catById(t.category);
                  const inc = t.amount > 0;
                  return (
                    <tr
                      key={t.id}
                      onClick={() => openTransaction(t.id)}
                      className="border-border hover:bg-secondary/40 cursor-pointer border-t first:border-t-0"
                    >
                      <td className="text-muted-foreground px-4 py-2.5 font-mono text-xs whitespace-nowrap">
                        {t.date.replace(/-/g, '/')}{t.time ? ' ' + t.time.slice(0, 5) : ''}
                      </td>
                      <td className="px-4 py-2.5">
                        <div className="flex items-center gap-2.5">
                          <CatBar color={cat.color} className="h-4" />
                          {t.merchant}
                          {t.kind === 'refund' && <RefundBadge />}
                          {(() => {
                            const a = anomalyScore(t, stats);
                            return a?.isAnomaly ? <AnomalyBadge zScore={a.zScore} mean={a.mean} /> : null;
                          })()}
                        </div>
                      </td>
                      <td className="text-muted-foreground px-4 py-2.5">{cat.name}</td>
                      <td className="text-muted-foreground px-4 py-2.5">{acctById(t.account).name}</td>
                      <td className="px-4 py-2.5 text-xs">
                        {t.pending ? (
                          <span className="text-warning">Pending</span>
                        ) : (
                          <span className="text-muted-foreground">Posted</span>
                        )}
                      </td>
                      <td className={cn('px-4 py-2.5 text-right font-mono', inc ? 'text-success' : 'text-foreground')}>
                        <Money value={t.amount} signed={inc} />
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </MobilePage>
  );
}
