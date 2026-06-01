'use client';

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Icon } from '@/components/primitives';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { useFinanceStore } from '@/lib/store';
import { useLedger } from '@/components/ledger-provider';
import { useTransactionSheet } from '@/components/transaction-sheet';
import { cn } from '@/lib/utils';

// The set of pages we expose to the palette. `icon` reuses the existing string
// shim in primitives.tsx so the UI stays consistent with the tab bar.
const PAGES: { label: string; href: string; icon: string; keywords: string[] }[] = [
  { label: 'Accounts', href: '/accounts', icon: 'wallet', keywords: ['balance', 'net worth'] },
  { label: 'Activity', href: '/activity', icon: 'doc', keywords: ['transactions', 'feed'] },
  { label: 'Budgets', href: '/budgets', icon: 'chart', keywords: ['spending', 'limit', 'goals', 'save', 'income'] },
  { label: 'Insights', href: '/insights', icon: 'sparkle', keywords: ['analytics', 'reports'] },
  { label: 'Scheduled', href: '/scheduled', icon: 'calendar', keywords: ['bills', 'upcoming', 'subscriptions'] },
  { label: 'Add', href: '/add', icon: 'plus', keywords: ['new', 'expense', 'transaction'] },
  { label: 'Settings', href: '/settings', icon: 'cog', keywords: ['preferences'] },
  // Ledger admin
  { label: 'Pending', href: '/pending', icon: 'clock', keywords: ['confirm'] },
  { label: 'Transfers', href: '/transfers', icon: 'swap', keywords: ['move'] },
  { label: 'Merchants', href: '/merchants', icon: 'tag', keywords: ['counterparties'] },
  { label: 'Scheduled', href: '/scheduled', icon: 'sync', keywords: ['templates'] },
  { label: 'Categories', href: '/categories', icon: 'tags', keywords: [] },
  { label: 'Tags', href: '/tags', icon: 'tag', keywords: [] },
  { label: 'Exchange rates', href: '/settings/ledger', icon: 'coins', keywords: ['fx', 'exchange', 'rates', 'currency'] },
];

interface CommandPaletteValue {
  open: () => void;
  close: () => void;
}
const Ctx = createContext<CommandPaletteValue | null>(null);

export function useCommandPalette(): CommandPaletteValue {
  const v = useContext(Ctx);
  if (!v) throw new Error('useCommandPalette must be used inside CommandPaletteProvider');
  return v;
}

/** Button that opens the palette. Replaces the placeholder search affordance in headers. */
export function SearchButton() {
  const { open } = useCommandPalette();
  return (
    <Button variant="outline" size="icon" className="rounded-full" aria-label="Search" onClick={open}>
      <Icon name="search" size={16} />
    </Button>
  );
}

interface Result {
  key: string;
  group: string;
  label: string;
  hint?: string;
  icon: string;
  /** Hex `#rrggbb` to tint the icon chip. Omitted = neutral chip. */
  iconColor?: string;
  run: () => void;
}

const lc = (s: string) => s.toLowerCase();
function matches(query: string, haystack: string): boolean {
  if (!query) return true;
  return lc(haystack).includes(lc(query));
}

export function CommandPaletteProvider({ children }: { children: React.ReactNode }) {
  const [isOpen, setIsOpen] = useState(false);
  const open = useCallback(() => setIsOpen(true), []);
  const close = useCallback(() => setIsOpen(false), []);
  const value = useMemo(() => ({ open, close }), [open, close]);

  // Global Cmd+K / Ctrl+K hotkey. Listening on `window` so the shortcut works
  // regardless of focused element (input, button, scroll container, etc.).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const isHotkey = (e.metaKey || e.ctrlKey) && (e.key === 'k' || e.key === 'K');
      if (!isHotkey) return;
      e.preventDefault();
      setIsOpen((o) => !o);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  return (
    <Ctx.Provider value={value}>
      {children}
      <CommandPaletteDialog open={isOpen} onOpenChange={setIsOpen} />
    </Ctx.Provider>
  );
}

function CommandPaletteDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  // Body lives in a child component that mounts fresh each time `open` flips on,
  // so query/highlight reset to their initial values without a state-in-effect.
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        showCloseButton={false}
        className="top-[15%] max-w-xl translate-y-0 gap-0 overflow-hidden p-0 sm:rounded-2xl"
      >
        <DialogTitle className="sr-only">Search and commands</DialogTitle>
        <DialogDescription className="sr-only">
          Search transactions, accounts, and categories, or jump to a page.
        </DialogDescription>
        {open && <PaletteBody close={() => onOpenChange(false)} />}
      </DialogContent>
    </Dialog>
  );
}

function PaletteBody({ close }: { close: () => void }) {
  const router = useRouter();
  const { activeId } = useLedger();
  const { openTransaction } = useTransactionSheet();
  const transactions = useFinanceStore((s) => s.transactions);
  const counterparties = useFinanceStore((s) => s.counterparties);
  const categories = useFinanceStore((s) => s.categories);
  const accounts = useFinanceStore((s) => s.accounts);
  const tags = useFinanceStore((s) => s.tags);
  const [query, setQuery] = useState('');
  const [highlight, setHighlight] = useState(0);
  const listRef = useRef<HTMLDivElement>(null);

  const results = useMemo<Result[]>(() => {
    const q = query.trim();
    const out: Result[] = [];

    // Pages (filtered when there's a query).
    const pageMatches = PAGES.filter(
      (p) => matches(q, p.label) || p.keywords.some((k) => matches(q, k)),
    ).slice(0, q ? 8 : 8);
    for (const p of pageMatches) {
      out.push({
        key: `page:${p.href}`,
        group: 'Pages',
        label: p.label,
        icon: p.icon,
        run: () => {
          router.push(p.href);
          close();
        },
      });
    }

    if (q) {
      // Transactions: match merchant or note. Scope to active ledger.
      const txMatches = transactions
        .filter((t) => (t.ledgerId ?? 'personal') === activeId)
        .filter((t) => matches(q, t.merchant) || (t.note ? matches(q, t.note) : false))
        .slice(0, 8);
      for (const t of txMatches) {
        out.push({
          key: `tx:${t.id}`,
          group: 'Transactions',
          label: t.merchant,
          hint: `${t.date} · ${t.amount < 0 ? '−' : '+'}${Math.abs(t.amount).toFixed(2)}`,
          icon: 'doc',
          run: () => {
            openTransaction(t.id);
            close();
          },
        });
      }

      // Merchants (counterparties).
      const cpMatches = counterparties
        .filter((c) => c.ledgerId === activeId)
        .filter((c) => matches(q, c.name))
        .slice(0, 5);
      for (const c of cpMatches) {
        out.push({
          key: `cp:${c.id}`,
          group: 'Merchants',
          label: c.name,
          icon: 'tag',
          run: () => {
            router.push('/merchants');
            close();
          },
        });
      }

      // Categories — jump to the category's budget detail page.
      const catMatches = categories
        .filter((c) => c.ledgerId === activeId)
        .filter((c) => matches(q, c.name))
        .slice(0, 5);
      for (const c of catMatches) {
        out.push({
          key: `cat:${c.id}`,
          group: 'Categories',
          label: c.name,
          icon: c.icon ?? 'tags',
          iconColor: c.color ?? undefined,
          run: () => {
            router.push(`/budgets/${c.id}`);
            close();
          },
        });
      }

      // Accounts.
      const acctMatches = accounts
        .filter((a) => a.ledgerId === activeId)
        .filter((a) => matches(q, a.name))
        .slice(0, 5);
      for (const a of acctMatches) {
        out.push({
          key: `acct:${a.id}`,
          group: 'Accounts',
          label: a.name,
          icon: 'wallet',
          run: () => {
            router.push(`/accounts/${a.id}`);
            close();
          },
        });
      }

      // Tags.
      const tagMatches = tags
        .filter((t) => t.ledgerId === activeId)
        .filter((t) => matches(q, t.name))
        .slice(0, 5);
      for (const t of tagMatches) {
        out.push({
          key: `tag:${t.id}`,
          group: 'Tags',
          label: t.name,
          icon: 'tag',
          run: () => {
            router.push('/tags');
            close();
          },
        });
      }
    }

    return out;
  }, [query, transactions, counterparties, categories, accounts, tags, activeId, router, openTransaction, close]);

  // Group results in source order so the headings appear in the natural order
  // each kind was appended above. A Map preserves insertion order.
  const grouped = useMemo(() => {
    const m = new Map<string, Result[]>();
    for (const r of results) {
      const arr = m.get(r.group) ?? [];
      arr.push(r);
      m.set(r.group, arr);
    }
    return [...m.entries()];
  }, [results]);

  // Clamp the highlight to the visible range without an effect — `highlight`
  // can drift past `results.length` as the user types; we just bound it at
  // render time and use this derived value everywhere.
  const safeHighlight = Math.min(highlight, Math.max(0, results.length - 1));

  const activate = useCallback(
    (idx: number) => {
      const r = results[idx];
      if (r) r.run();
    },
    [results],
  );

  const onKey = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setHighlight(Math.min(results.length - 1, safeHighlight + 1));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setHighlight(Math.max(0, safeHighlight - 1));
    } else if (e.key === 'Enter') {
      e.preventDefault();
      activate(safeHighlight);
    }
  };

  // Scroll the highlighted row into view as the user navigates with arrows.
  useEffect(() => {
    const node = listRef.current?.querySelector<HTMLButtonElement>(`[data-idx="${safeHighlight}"]`);
    node?.scrollIntoView({ block: 'nearest' });
  }, [safeHighlight]);

  return (
    <>
      <div className="flex items-center gap-3 border-b border-border px-4 py-3">
        <Icon name="search" size={16} className="text-muted-foreground" />
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={onKey}
          placeholder="Search transactions, accounts, screens…"
          aria-label="Command palette search"
          autoFocus
          className="placeholder:text-muted-foreground w-full bg-transparent text-sm outline-none"
        />
        <kbd className="text-muted-foreground hidden font-mono text-[10px] tracking-wide sm:inline">
          esc
        </kbd>
      </div>
      <div ref={listRef} className="max-h-[60vh] overflow-y-auto py-1">
        {results.length === 0 ? (
          <div className="text-muted-foreground px-4 py-6 text-center text-sm">No results</div>
        ) : (
          grouped.map(([group, items]) => (
            <div key={group} className="mb-1">
              <div className="text-muted-foreground px-3 pb-1 pt-2 font-mono text-[10px] tracking-wider uppercase">
                {group}
              </div>
              {items.map((r) => {
                const idx = results.indexOf(r);
                const active = idx === safeHighlight;
                return (
                  <button
                    key={r.key}
                    type="button"
                    data-idx={idx}
                    onMouseEnter={() => setHighlight(idx)}
                    onClick={() => activate(idx)}
                    className={cn(
                      'flex w-full items-center gap-3 px-3 py-2 text-left text-sm',
                      active ? 'bg-secondary text-foreground' : 'text-foreground',
                    )}
                  >
                    <span
                      className="flex size-7 items-center justify-center rounded-md"
                      style={
                        r.iconColor
                          ? { background: r.iconColor, color: 'white' }
                          : { background: 'var(--secondary)' }
                      }
                    >
                      <Icon name={r.icon} size={14} />
                    </span>
                    <span className="flex-1 truncate">{r.label}</span>
                    {r.hint && <span className="text-muted-foreground shrink-0 font-mono text-[11px]">{r.hint}</span>}
                  </button>
                );
              })}
            </div>
          ))
        )}
      </div>
      <div className="bg-muted/30 text-muted-foreground border-border flex items-center justify-between border-t px-4 py-2 text-[10px] font-mono">
        <span>↑↓ navigate · ↵ select · esc close</span>
        <span>⌘K</span>
      </div>
    </>
  );
}
