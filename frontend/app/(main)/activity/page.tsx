'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Money, Icon, CatBar } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { SearchButton } from '@/components/command-palette';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { catById, acctById } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { useSavedSearches, type SavedSearch } from '@/lib/use-saved-searches';
import { useLedger } from '@/components/ledger-provider';
import { useTransactionSheet } from '@/components/transaction-sheet';
import { RefundBadge } from '@/components/refund-badge';
import { AnomalyBadge } from '@/components/anomaly-badge';
import { EmptyState } from '@/components/empty-state';
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
  const [saveOpen, setSaveOpen] = useState(false);
  const [saveName, setSaveName] = useState('');
  const allTxns = useFinanceStore((s) => s.transactions);
  const allTags = useFinanceStore((s) => s.tags);
  const allCategories = useFinanceStore((s) => s.categories);
  const bulkRecategorize = useFinanceStore((s) => s.bulkRecategorize);
  const { searches: savedSearches, save: saveSearch, remove: deleteSavedSearch } = useSavedSearches();
  const { activeId } = useLedger();
  const { openTransaction } = useTransactionSheet();
  const ledgerTags = allTags.filter((t) => t.ledgerId === activeId);
  const ledgerCategories = allCategories.filter((c) => c.ledgerId === activeId);

  // Bulk-recategorize mode: a row tap toggles selection instead of opening the
  // detail sheet, and a floating action bar appears with a category picker.
  // Cleared whenever the user exits the page or switches ledger (Set rebuilds).
  const [selectMode, setSelectMode] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const toggleSelected = (id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };
  const exitSelectMode = () => {
    setSelectMode(false);
    setSelectedIds(new Set());
  };
  const applyBulkCategory = (categoryId: string) => {
    const ids = [...selectedIds];
    if (!ids.length) return;
    bulkRecategorize(ids, categoryId);
    const cat = ledgerCategories.find((c) => c.id === categoryId);
    toast.success(`Set category to ${cat?.name ?? 'Uncategorized'} on ${ids.length} ${ids.length === 1 ? 'transaction' : 'transactions'}`);
    exitSelectMode();
  };
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

  // Saved searches (client-only, localStorage) scoped to the active ledger. Any
  // non-default filter makes the current view "saveable"; the chips re-apply a
  // stored set in one tap.
  const ledgerSearches = savedSearches.filter((s) => s.ledgerId === activeId);
  const hasActiveFilters = query.trim() !== '' || filter !== 'all' || tagFilter !== null || activeRangeCount > 0;

  const applySavedSearch = (s: SavedSearch) => {
    setQuery(s.query);
    setFilter(s.direction);
    setTagFilter(s.tagId);
    setFromDate(s.fromDate);
    setToDate(s.toDate);
    setMinAmt(s.minAmount != null ? String(s.minAmount) : '');
    setMaxAmt(s.maxAmount != null ? String(s.maxAmount) : '');
    if (s.fromDate || s.toDate || s.minAmount != null || s.maxAmount != null) setFiltersOpen(true);
  };

  const confirmSaveSearch = () => {
    const name = saveName.trim();
    if (!name) return;
    saveSearch({
      ledgerId: activeId,
      name,
      query: query.trim(),
      direction: filter,
      tagId: tagFilter,
      fromDate,
      toDate,
      minAmount: minA != null && Number.isFinite(minA) ? minA : null,
      maxAmount: maxA != null && Number.isFinite(maxA) ? maxA : null,
    });
    toast.success(`Saved “${name}”`);
    setSaveName('');
    setSaveOpen(false);
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
            className="placeholder:text-muted-foreground focus-ring w-full bg-transparent text-[13px] outline-none"
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
          {hasActiveFilters && !selectMode && (
            <button
              type="button"
              onClick={() => setSaveOpen(true)}
              aria-label="Save current filters as a search"
              className="border-border text-muted-foreground hover:text-foreground flex h-9 cursor-pointer items-center gap-1.5 rounded-full border px-3 text-[11px] font-medium"
            >
              <Icon name="bookmark" size={13} />
              Save
            </button>
          )}
          <button
            type="button"
            onClick={() => (selectMode ? exitSelectMode() : setSelectMode(true))}
            aria-label={selectMode ? 'Exit select mode' : 'Select transactions to recategorize'}
            aria-pressed={selectMode}
            className={cn(
              'border-border flex h-9 cursor-pointer items-center gap-1.5 rounded-full border px-3 text-[11px] font-medium',
              selectMode ? 'border-primary text-primary' : 'text-muted-foreground',
            )}
          >
            <Icon name={selectMode ? 'x' : 'check'} size={13} />
            {selectMode ? 'Cancel' : 'Select'}
          </button>
        </div>

        {ledgerSearches.length > 0 && (
          <div className="mb-4 flex flex-wrap gap-1.5">
            {ledgerSearches.map((s) => (
              <span
                key={s.id}
                className="bg-secondary text-secondary-foreground flex items-center gap-1 rounded-lg py-1 pr-1 pl-2.5 text-[11px]"
              >
                <button
                  type="button"
                  onClick={() => applySavedSearch(s)}
                  className="hover:text-foreground flex items-center gap-1"
                >
                  <Icon name="bookmark" size={11} />
                  {s.name}
                </button>
                <button
                  type="button"
                  onClick={() => deleteSavedSearch(s.id)}
                  aria-label={`Delete saved search ${s.name}`}
                  className="hover:text-foreground text-muted-foreground flex size-4 items-center justify-center rounded-full"
                >
                  <Icon name="x" size={11} />
                </button>
              </span>
            ))}
          </div>
        )}

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
          <EmptyState
            icon="search"
            title="No transactions"
            description={
              query || tagFilter || activeRangeCount > 0
                ? 'Nothing matches the current filters. Clear them to see all rows.'
                : 'Add an expense to get started — it’ll show up here.'
            }
          />
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
                  const selected = selectedIds.has(t.id);
                  return (
                    <button
                      key={t.id}
                      type="button"
                      onClick={() => (selectMode ? toggleSelected(t.id) : openTransaction(t.id))}
                      aria-pressed={selectMode ? selected : undefined}
                      className={cn(
                        'flex w-full items-center gap-3 p-3.5 text-left',
                        i && 'border-border border-t',
                        selectMode && selected && 'bg-primary/5',
                      )}
                    >
                      {selectMode ? (
                        <span
                          className={cn(
                            'flex size-4 shrink-0 items-center justify-center rounded-full border',
                            selected ? 'bg-primary border-primary text-primary-foreground' : 'border-border',
                          )}
                          aria-hidden
                        >
                          {selected && <Icon name="check" size={10} />}
                        </span>
                      ) : (
                        <CatBar color={cat.color} />
                      )}
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
                  const selected = selectedIds.has(t.id);
                  return (
                    <tr
                      key={t.id}
                      onClick={() => (selectMode ? toggleSelected(t.id) : openTransaction(t.id))}
                      aria-pressed={selectMode ? selected : undefined}
                      className={cn(
                        'border-border hover:bg-secondary/40 cursor-pointer border-t first:border-t-0',
                        selectMode && selected && 'bg-primary/5',
                      )}
                    >
                      <td className="text-muted-foreground px-4 py-2.5 font-mono text-xs whitespace-nowrap">
                        {t.date.replace(/-/g, '/')}{t.time ? ' ' + t.time.slice(0, 5) : ''}
                      </td>
                      <td className="px-4 py-2.5">
                        <div className="flex items-center gap-2.5">
                          {selectMode ? (
                            <span
                              className={cn(
                                'flex size-4 shrink-0 items-center justify-center rounded-full border',
                                selected ? 'bg-primary border-primary text-primary-foreground' : 'border-border',
                              )}
                              aria-hidden
                            >
                              {selected && <Icon name="check" size={10} />}
                            </span>
                          ) : (
                            <CatBar color={cat.color} className="h-4" />
                          )}
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

      {selectMode && (
        <div
          role="region"
          aria-label="Bulk recategorize"
          className="bg-card border-border fixed inset-x-3 bottom-[88px] z-30 flex items-center gap-2 rounded-2xl border p-2.5 shadow-lg md:right-6 md:bottom-6 md:left-auto md:max-w-md"
        >
          <span className="font-mono text-[11px] font-medium">
            {selectedIds.size} selected
          </span>
          {selectedIds.size < txns.length && (
            <button
              type="button"
              onClick={() => setSelectedIds(new Set(txns.map((t) => t.id)))}
              className="text-primary text-[11px] underline-offset-2 hover:underline"
            >
              Select all {txns.length}
            </button>
          )}
          <div className="flex-1" />
          <Select
            value=""
            onValueChange={applyBulkCategory}
            disabled={selectedIds.size === 0}
          >
            <SelectTrigger size="sm" className="w-[150px]">
              <SelectValue placeholder="Recategorize…" />
            </SelectTrigger>
            <SelectContent>
              {ledgerCategories.map((c) => (
                <SelectItem key={c.id} value={c.id}>
                  {c.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      )}

      <Dialog open={saveOpen} onOpenChange={setSaveOpen}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Save search</DialogTitle>
          </DialogHeader>
          <div className="flex flex-col gap-2">
            <Label htmlFor="saved-search-name" className="text-muted-foreground text-[11px]">Name</Label>
            <Input
              id="saved-search-name"
              autoFocus
              value={saveName}
              onChange={(e) => setSaveName(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') confirmSaveSearch();
              }}
              placeholder="e.g. Subscriptions > $20"
            />
            <p className="text-muted-foreground text-[11px]">
              Pinned on this device only — saved searches aren’t stored in your ledger or included in exports.
            </p>
          </div>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setSaveOpen(false)}>Cancel</Button>
            <Button onClick={confirmSaveSearch} disabled={!saveName.trim()}>Save</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MobilePage>
  );
}
