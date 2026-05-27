'use client';

import { useEffect, useState } from 'react';
import { Money, MerchantGlyph, Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton } from '@/components/MobileComponents';
import { catById, acctById } from '@/lib/data';
import { useFinanceStore, type Tx } from '@/lib/store';
import { useLedger } from '@/components/ledger-provider';
import { useDb } from '@/components/db-provider';
import { listTransactions, type Direction } from '@/lib/db/queries/transactions';
import { useTransactionSheet } from '@/components/transaction-sheet';
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
  const allTxns = useFinanceStore((s) => s.transactions);
  const { activeId } = useLedger();
  const { openTransaction } = useTransactionSheet();
  const { exec, version } = useDb();

  // Client-side filter over the store — used until the query DB is ready and as
  // a fallback if a SQL query fails.
  const storeTxns = allTxns.filter((t) => {
    if ((t.ledgerId ?? 'personal') !== activeId) return false;
    if (filter === 'in' && t.amount <= 0) return false;
    if (filter === 'out' && t.amount >= 0) return false;
    if (query && !t.merchant.toLowerCase().includes(query.toLowerCase())) return false;
    return true;
  });

  // DB-backed list/search/filter. Re-runs when the query DB rebuilds (version),
  // the active ledger changes, or the filter/search input changes.
  const [dbTxns, setDbTxns] = useState<Tx[] | null>(null);
  useEffect(() => {
    if (!exec) return; // not ready yet — storeTxns fallback is shown
    let cancelled = false;
    const direction: Direction = filter === 'all' ? 'all' : filter;
    listTransactions(exec, { ledgerId: activeId, direction, query: query || undefined })
      .then((rows) => {
        if (!cancelled) setDbTxns(rows);
      })
      .catch((err) => {
        console.error('Activity SQL query failed; using store fallback', err);
        if (!cancelled) setDbTxns(null);
      });
    return () => {
      cancelled = true;
    };
  }, [exec, version, activeId, filter, query]);

  const txns = dbTxns ?? storeTxns;

  const groups: { date: string; items: typeof txns }[] = [];
  for (const t of txns) {
    const last = groups[groups.length - 1];
    if (last && last.date === t.date) last.items.push(t);
    else groups.push({ date: t.date, items: [t] });
  }

  return (
    <MobilePage
      header={<ScreenHeader title="Activity" trailing={<IconButton icon="search" aria-label="Search" />} />}
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

        <div className="bg-secondary mb-4 flex gap-1 rounded-full p-1">
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
                      <MerchantGlyph name={t.merchant} hue={cat.hue} size={36} />
                      <div className="min-w-0 flex-1">
                        <div className="truncate text-sm font-medium">{t.merchant}</div>
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
                        {t.date.slice(5).replace('-', '/')}
                      </td>
                      <td className="px-4 py-2.5">
                        <div className="flex items-center gap-2.5">
                          <MerchantGlyph name={t.merchant} hue={cat.hue} size={26} />
                          {t.merchant}
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
