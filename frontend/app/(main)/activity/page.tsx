'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { useTranslations } from 'next-intl';
import { CatBar } from '@/components/ui/cat-bar';
import { Money } from '@/components/primitives';
import { Bookmark, Check, Doc, Filter, Search, X } from '@/components/icons';
import { MobilePage } from '@/components/mobile-page';
import { ScreenHeader } from '@/components/ui/screen-header';
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
import { useTransactionDialog } from '@/components/transaction-dialog';
import { RefundBadge } from '@/components/ui/refund-badge';
import { AnomalyBadge } from '@/components/anomaly-badge';
import { EmptyState } from '@/components/empty-state';
import { merchantStats, anomalyScore, txMatchesQuery } from '@/lib/select';
import { cn } from '@/lib/utils';

const FILTER_IDS = ['all', 'out', 'in'] as const;

type Filter = (typeof FILTER_IDS)[number];

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
  // Review-triage filter: when on, the list narrows to unreviewed confirmed
  // rows so Activity becomes a "what still needs a look" queue.
  const [reviewOnly, setReviewOnly] = useState(false);
  const t = useTranslations('activity');
  const tCommon = useTranslations('common');
  const allTxns = useFinanceStore((s) => s.transactions);
  const allTags = useFinanceStore((s) => s.tags);
  const allCategories = useFinanceStore((s) => s.categories);
  const bulkRecategorize = useFinanceStore((s) => s.bulkRecategorize);
  const markAllReviewed = useFinanceStore((s) => s.markAllReviewed);
  const { searches: savedSearches, save: saveSearch, remove: deleteSavedSearch } = useSavedSearches();
  const { activeId } = useLedger();
  const { openTransaction } = useTransactionDialog();
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
    toast.success(t('selectMode.appliedToast', { category: cat?.name ?? t('row.uncategorized'), count: ids.length }));
    exitSelectMode();
  };
  // Per-merchant stats for the anomaly badge. One pass over the transaction
  // list per render; lookup per row is O(1). Memoized on the txn list + ledger
  // so we don't recompute on every render.
  const stats = useMemo(() => merchantStats(allTxns, activeId), [allTxns, activeId]);

  // Search matches what a row displays (merchant, category title, tags), not
  // just the merchant text — id→name lookups for txMatchesQuery.
  const searchNames = useMemo(
    () => ({
      categories: Object.fromEntries(allCategories.map((c) => [c.id, c.name])),
      tags: Object.fromEntries(allTags.map((t) => [t.id, t.name])),
    }),
    [allCategories, allTags],
  );

  const minA = minAmt.trim() === '' ? null : Number(minAmt);
  const maxA = maxAmt.trim() === '' ? null : Number(maxAmt);
  const activeRangeCount =
    (fromDate ? 1 : 0) + (toDate ? 1 : 0) + (minA != null && Number.isFinite(minA) ? 1 : 0) + (maxA != null && Number.isFinite(maxA) ? 1 : 0);

  const txns = allTxns.filter((t) => {
    if ((t.ledgerId ?? 'personal') !== activeId) return false;
    if (filter === 'in' && t.amount <= 0) return false;
    if (filter === 'out' && t.amount >= 0) return false;
    if (query && !txMatchesQuery(t, query, searchNames)) return false;
    if (tagFilter && !(t.tags ?? []).includes(tagFilter)) return false;
    if (fromDate && t.date < fromDate) return false;
    if (toDate && t.date > toDate) return false;
    if (minA != null && Number.isFinite(minA) && Math.abs(t.amount) < minA) return false;
    if (maxA != null && Number.isFinite(maxA) && Math.abs(t.amount) > maxA) return false;
    if (reviewOnly && (t.pending || t.reviewedAt)) return false;
    return true;
  });

  // Count of unreviewed confirmed rows in the active ledger — drives the
  // "Needs review" toggle badge + the empty-queue celebration.
  const unreviewedCount = allTxns.reduce(
    (n, t) => n + ((t.ledgerId ?? 'personal') === activeId && !t.pending && !t.reviewedAt ? 1 : 0),
    0,
  );

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
    toast.success(t('saveDialog.savedToast', { name }));
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
      header={<ScreenHeader title={t('title')} trailing={<SearchButton />} />}
    >
      <div className="px-5 pb-[120px]">
        <div className="bg-secondary mb-3 flex h-9 items-center gap-2 rounded-full px-3.5">
          <Search size={14} className="text-muted-foreground" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            aria-label={t('searchAria')} placeholder={t('searchPlaceholder')}
            className="placeholder:text-muted-foreground focus-ring w-full bg-transparent text-[13px] outline-none"
          />
        </div>

        <div className="mb-4 flex items-center gap-2">
          <div className="bg-secondary flex flex-1 gap-1 rounded-full p-1">
            {FILTER_IDS.map((f) => (
              <button
                key={f}
                type="button"
                onClick={() => setFilter(f)}
                className={cn(
                  'h-7 flex-1 rounded-full text-xs font-medium transition-colors',
                  filter === f ? 'bg-background text-foreground shadow-sm' : 'text-muted-foreground',
                )}
              >
                {t(`filters.${f}`)}
              </button>
            ))}
          </div>
          <button
            type="button"
            onClick={() => setFiltersOpen((o) => !o)}
            aria-label={t('toggleFilters')}
            aria-expanded={filtersOpen}
            className={cn(
              'border-border flex h-9 cursor-pointer items-center gap-1.5 rounded-full border px-3 text-[11px] font-medium',
              activeRangeCount > 0 ? 'border-primary text-primary' : 'text-muted-foreground',
            )}
          >
            <Filter size={13} />
            {t('filtersLabel')}{activeRangeCount > 0 ? ` · ${activeRangeCount}` : ''}
          </button>
          {hasActiveFilters && !selectMode && (
            <button
              type="button"
              onClick={() => setSaveOpen(true)}
              aria-label={t('saveSearchAria')}
              className="border-border text-muted-foreground hover:text-foreground flex h-9 cursor-pointer items-center gap-1.5 rounded-full border px-3 text-[11px] font-medium"
            >
              <Bookmark size={13} />
              {t('saveSearch')}
            </button>
          )}
          <button
            type="button"
            onClick={() => (selectMode ? exitSelectMode() : setSelectMode(true))}
            aria-label={selectMode ? t('selectMode.exitAria') : t('selectMode.enterAria')}
            aria-pressed={selectMode}
            className={cn(
              'border-border flex h-9 cursor-pointer items-center gap-1.5 rounded-full border px-3 text-[11px] font-medium',
              selectMode ? 'border-primary text-primary' : 'text-muted-foreground',
            )}
          >
            {selectMode ? <X size={13} /> : <Check size={13} />}
            {selectMode ? t('selectMode.exit') : t('selectMode.enter')}
          </button>
          <button
            type="button"
            onClick={() => setReviewOnly((v) => !v)}
            aria-label={t('reviewToggleAria')}
            aria-pressed={reviewOnly}
            className={cn(
              'border-border flex h-9 cursor-pointer items-center gap-1.5 rounded-full border px-3 text-[11px] font-medium',
              reviewOnly ? 'border-primary text-primary' : 'text-muted-foreground',
            )}
          >
            <Doc size={13} />
            {t('reviewToggle')}{unreviewedCount > 0 ? ` · ${unreviewedCount}` : ''}
          </button>
        </div>

        {reviewOnly && unreviewedCount > 0 && (
          <div className="mb-4 flex items-center justify-between gap-2">
            <span className="text-muted-foreground text-[11px]">
              {t('reviewCount', { count: unreviewedCount })}
            </span>
            <button
              type="button"
              onClick={() => {
                markAllReviewed(activeId);
                toast.success(t('markedReviewedToast', { count: unreviewedCount }));
              }}
              className="text-primary text-[11px] font-medium underline-offset-2 hover:underline"
            >
              {t('markAllReviewed')}
            </button>
          </div>
        )}
        {reviewOnly && unreviewedCount === 0 && (
          <div className="text-muted-foreground mb-4 flex items-center gap-1.5 text-[12px]">
            <Check size={13} className="text-success" />
            {t('reviewEmpty')}
          </div>
        )}

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
                  <Bookmark size={11} />
                  {s.name}
                </button>
                <button
                  type="button"
                  onClick={() => deleteSavedSearch(s.id)}
                  aria-label={t('deleteSavedSearchAria', { name: s.name })}
                  className="hover:text-foreground text-muted-foreground flex size-4 items-center justify-center rounded-full"
                >
                  <X size={11} />
                </button>
              </span>
            ))}
          </div>
        )}

        {filtersOpen && (
          <div className="bg-card border-border mb-4 flex flex-col gap-3 rounded-xl border p-3.5">
            <div className="grid grid-cols-2 gap-3">
              <div className="flex flex-col gap-1">
                <Label htmlFor="filter-from" className="text-muted-foreground text-[11px]">{t('filterPanel.from')}</Label>
                <Input id="filter-from" type="date" value={fromDate} onChange={(e) => setFromDate(e.target.value)} className="h-8 text-[12px]" />
              </div>
              <div className="flex flex-col gap-1">
                <Label htmlFor="filter-to" className="text-muted-foreground text-[11px]">{t('filterPanel.to')}</Label>
                <Input id="filter-to" type="date" value={toDate} onChange={(e) => setToDate(e.target.value)} className="h-8 text-[12px]" />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="flex flex-col gap-1">
                <Label htmlFor="filter-min" className="text-muted-foreground text-[11px]">{t('filterPanel.minAmount')}</Label>
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
                <Label htmlFor="filter-max" className="text-muted-foreground text-[11px]">{t('filterPanel.maxAmount')}</Label>
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
                  {t('filterPanel.clear')}
                </Button>
              </div>
            )}
          </div>
        )}

        {ledgerTags.length > 0 && (
          <div className="mb-4 flex flex-wrap gap-1.5">
            {ledgerTags.map((tg) => (
              <button
                key={tg.id}
                type="button"
                onClick={() => setTagFilter((prev) => (prev === tg.id ? null : tg.id))}
                className={cn(
                  'rounded-lg px-2.5 py-1 text-[11px] transition-colors',
                  tagFilter === tg.id
                    ? 'bg-foreground text-background'
                    : 'bg-secondary text-secondary-foreground',
                )}
              >
                {tg.name}
              </button>
            ))}
          </div>
        )}

        {txns.length === 0 && (
          <EmptyState
            icon="search"
            title={t('empty.title')}
            description={
              query || tagFilter || activeRangeCount > 0
                ? t('empty.filteredDescription')
                : t('empty.freshDescription')
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
                {group.items.map((tx, i) => {
                  const cat = catById(tx.category);
                  const inc = tx.amount > 0;
                  const selected = selectedIds.has(tx.id);
                  return (
                    <button
                      key={tx.id}
                      type="button"
                      onClick={() => (selectMode ? toggleSelected(tx.id) : openTransaction(tx.id))}
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
                              {selected && <Check size={10} />}
                        </span>
                      ) : (
                        <CatBar color={cat.color} />
                      )}
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-1.5">
                          {!selectMode && !tx.pending && !tx.reviewedAt && (
                            <span
                              className="bg-primary/70 size-1.5 shrink-0 rounded-full"
                              aria-label={t('row.needsReview')}
                              title={t('row.needsReview')}
                            />
                          )}
                          <span className="truncate text-sm font-medium">{tx.merchant}</span>
                          {tx.kind === 'refund' && <RefundBadge />}
                          {(() => {
                            const a = anomalyScore(tx, stats);
                            return a?.isAnomaly ? <AnomalyBadge zScore={a.zScore} mean={a.mean} /> : null;
                          })()}
                        </div>
                        <div className="text-muted-foreground mt-0.5 truncate text-[11px]">
                          {cat.name} · {acctById(tx.account).name}
                          {tx.pending && <span className="text-warning"> · {t('row.pending')}</span>}
                        </div>
                      </div>
                      <Money
                        value={tx.amount}
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
                  <th className="px-4 py-2.5 font-medium">{t('table.date')}</th>
                  <th className="px-4 py-2.5 font-medium">{t('table.merchant')}</th>
                  <th className="px-4 py-2.5 font-medium">{t('table.category')}</th>
                  <th className="px-4 py-2.5 font-medium">{t('table.account')}</th>
                  <th className="px-4 py-2.5 font-medium">{t('table.status')}</th>
                  <th className="px-4 py-2.5 text-right font-medium">{t('table.amount')}</th>
                </tr>
              </thead>
              <tbody>
                {txns.map((tx) => {
                  const cat = catById(tx.category);
                  const inc = tx.amount > 0;
                  const selected = selectedIds.has(tx.id);
                  return (
                    <tr
                      key={tx.id}
                      onClick={() => (selectMode ? toggleSelected(tx.id) : openTransaction(tx.id))}
                      aria-pressed={selectMode ? selected : undefined}
                      className={cn(
                        'border-border hover:bg-secondary/40 cursor-pointer border-t first:border-t-0',
                        selectMode && selected && 'bg-primary/5',
                      )}
                    >
                      <td className="text-muted-foreground px-4 py-2.5 font-mono text-xs whitespace-nowrap">
                        {tx.date.replace(/-/g, '/')}{tx.time ? ' ' + tx.time.slice(0, 5) : ''}
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
                          {selected && <Check size={10} />}
                            </span>
                          ) : (
                            <CatBar color={cat.color} className="h-4" />
                          )}
                          {tx.merchant}
                          {tx.kind === 'refund' && <RefundBadge />}
                          {(() => {
                            const a = anomalyScore(tx, stats);
                            return a?.isAnomaly ? <AnomalyBadge zScore={a.zScore} mean={a.mean} /> : null;
                          })()}
                        </div>
                      </td>
                      <td className="text-muted-foreground px-4 py-2.5">{cat.name}</td>
                      <td className="text-muted-foreground px-4 py-2.5">{acctById(tx.account).name}</td>
                      <td className="px-4 py-2.5 text-xs">
                        {tx.pending ? (
                          <span className="text-warning">{t('table.pending')}</span>
                        ) : (
                          <span className="text-muted-foreground">{t('table.posted')}</span>
                        )}
                      </td>
                      <td className={cn('px-4 py-2.5 text-right font-mono', inc ? 'text-success' : 'text-foreground')}>
                        <Money value={tx.amount} signed={inc} />
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
          aria-label={t('selectMode.regionAria')}
          className="bg-card border-border fixed inset-x-3 bottom-[88px] z-30 flex items-center gap-2 rounded-2xl border p-2.5 shadow-lg md:right-6 md:bottom-6 md:left-auto md:max-w-md"
        >
          <span className="font-mono text-[11px] font-medium">
            {t('selectMode.selectedCount', { count: selectedIds.size })}
          </span>
          {selectedIds.size < txns.length && (
            <button
              type="button"
              onClick={() => setSelectedIds(new Set(txns.map((tx) => tx.id)))}
              className="text-primary text-[11px] underline-offset-2 hover:underline"
            >
              {t('selectMode.selectAll', { total: txns.length })}
            </button>
          )}
          <div className="flex-1" />
          <Select
            value=""
            onValueChange={applyBulkCategory}
            disabled={selectedIds.size === 0}
          >
            <SelectTrigger size="sm" className="w-[150px]">
              <SelectValue placeholder={t('selectMode.recategorizePlaceholder')} />
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
            <DialogTitle>{t('saveDialog.title')}</DialogTitle>
          </DialogHeader>
          <div className="flex flex-col gap-2">
            <Label htmlFor="saved-search-name" className="text-muted-foreground text-[11px]">{t('saveDialog.name')}</Label>
            <Input
              id="saved-search-name"
              autoFocus
              value={saveName}
              onChange={(e) => setSaveName(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') confirmSaveSearch();
              }}
              placeholder={t('saveDialog.namePlaceholder')}
            />
            <p className="text-muted-foreground text-[11px]">
              {t('saveDialog.hint')}
            </p>
          </div>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setSaveOpen(false)}>{tCommon('cancel')}</Button>
            <Button onClick={confirmSaveSearch} disabled={!saveName.trim()}>{tCommon('save')}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MobilePage>
  );
}
