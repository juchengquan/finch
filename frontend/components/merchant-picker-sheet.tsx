'use client';

import { createContext, useCallback, useContext, useMemo, useState } from 'react';
import { toast } from 'sonner';
import { useTranslations } from 'next-intl';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Chev, Plus, Search } from '@/components/icons';
import { useFinanceStore } from '@/lib/store';

/** Resolution the picker returns to the caller. Mirrors the `confirmPendingWithMatch`
 *  action's accepted shapes, so the caller can pipe the result straight through. */
export type MerchantResolution =
  | { kind: 'existing'; id: string; name: string }
  | { kind: 'new'; name: string };

interface MerchantPickerValue {
  /** Open the merchant picker. Optional `seedQuery` pre-fills the search box
   *  (e.g. the raw bank-string for a pending row). The caller receives the
   *  resolution when the user picks a row, or `null` if they cancel. */
  openMerchantPicker: (
    seedQuery?: string,
    onResolve?: (resolution: MerchantResolution | null) => void,
  ) => void;
  close: () => void;
}

const MerchantPickerContext = createContext<MerchantPickerValue | null>(null);

export function useMerchantPicker(): MerchantPickerValue {
  const ctx = useContext(MerchantPickerContext);
  if (!ctx) throw new Error('useMerchantPicker must be used within MerchantPickerSheetProvider');
  return ctx;
}

export function MerchantPickerSheetProvider({ children }: { children: React.ReactNode }) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [onResolveCb, setOnResolveCb] = useState<
    ((resolution: MerchantResolution | null) => void) | null
  >(null);
  const counterparties = useFinanceStore((s) => s.counterparties);
  const verifyCounterparty = useFinanceStore((s) => s.verifyCounterparty);
  const t = useTranslations('merchantPicker');

  const close = useCallback(() => {
    setOpen(false);
    setQuery('');
    onResolveCb?.(null);
    setOnResolveCb(null);
  }, [onResolveCb]);

  const openMerchantPicker = useCallback<MerchantPickerValue['openMerchantPicker']>(
    (seedQuery, onResolve) => {
      setQuery(seedQuery ?? '');
      setOnResolveCb(() => onResolve ?? null);
      setOpen(true);
    },
    [],
  );

  const pick = useCallback(
    (id: string, name: string) => {
      // Picking an unverified row auto-verifies it (the user just
      // committed to it). Mirrors the "Confirm & verify" chip on the Pending row.
      const cp = counterparties.find((c) => c.id === id);
      if (cp && !cp.verified) {
        verifyCounterparty(id);
        toast.success(t('verifiedToast', { name }));
      }
      onResolveCb?.({ kind: 'existing', id, name });
      setOpen(false);
      setQuery('');
      setOnResolveCb(null);
    },
    [counterparties, verifyCounterparty, onResolveCb, t],
  );

  const createAndPick = useCallback(
    (name: string) => {
      const trimmed = name.trim();
      if (!trimmed) {
        toast.error(t('nameError'));
        return;
      }
      onResolveCb?.({ kind: 'new', name: trimmed });
      setOpen(false);
      setQuery('');
      setOnResolveCb(null);
    },
    [onResolveCb, t],
  );

  const value = useMemo(() => ({ openMerchantPicker, close }), [openMerchantPicker, close]);

  // Filter the catalog by the user's query (case-insensitive substring). The
  // server's `searchCounterparties` does the same thing; we mirror it client-
  // side for instant feedback.
  const q = query.trim().toLowerCase();
  const matches = q
    ? counterparties.filter((c) => c.name.toLowerCase().includes(q))
    : counterparties;
  // Sort: verified first, then alphabetical.
  const sorted = [...matches].sort((a, b) => {
    if (a.verified !== b.verified) return a.verified ? -1 : 1;
    return a.name.localeCompare(b.name);
  });
  const exactMatch = q && counterparties.some((c) => c.name.toLowerCase() === q);

  return (
    <MerchantPickerContext.Provider value={value}>
      {children}
      <Dialog open={open} onOpenChange={(o) => (o ? setOpen(true) : close())}>
        {/* Centered popout card, matching the other entity dialogs. Fixed height
            (not max-h) so the card doesn't grow/shrink as the search narrows. */}
        <DialogContent className="flex h-[70vh] flex-col gap-0 overflow-hidden p-0 sm:max-w-md">
          <DialogHeader className="border-border border-b px-5 py-4">
            <DialogTitle className="font-serif text-xl italic">{t('title')}</DialogTitle>
            <DialogDescription className="sr-only">{t('description')}</DialogDescription>
          </DialogHeader>
          <div className="min-h-0 flex-1 overflow-y-auto">
            <div className="px-5 pt-4 pb-3">
              <div className="bg-secondary flex h-10 items-center gap-2.5 rounded-full px-3.5">
                <Search size={14} className="text-muted-foreground" />
                <Input
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  placeholder={t('searchPlaceholder')}
                  className="h-auto border-0 bg-transparent px-0 shadow-none focus-visible:ring-0"
                  autoFocus
                />
              </div>
            </div>
            <div className="flex flex-col px-2">
              {sorted.length === 0 && !q && (
                <div className="text-muted-foreground py-8 text-center text-sm">
                  {t('emptyHint')}
                </div>
              )}
              {sorted.length === 0 && q && (
                <div className="text-muted-foreground py-8 text-center text-sm">
                  {t('noMatches', { query })}
                </div>
              )}
              {sorted.map((c) => (
                <button
                  key={c.id}
                  type="button"
                  onClick={() => pick(c.id, c.name)}
                  className="hover:bg-secondary flex items-center gap-3 rounded-lg px-3 py-2.5 text-left transition-colors"
                >
                  <div
                    className="flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-md font-mono text-[10px] font-semibold text-white"
                    style={{ background: `oklch(0.65 0.2 ${hashHue(c.id)})` }}
                  >
                    {c.name.slice(0, 2).toUpperCase()}
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <div className="truncate text-sm font-medium">{c.name}</div>
                      {!c.verified && (
                        <span className="border-warning/40 text-warning rounded border px-1.5 py-0.2 font-mono text-[9px] tracking-[0.6px]">
                          {t('unverifiedChip')}
                        </span>
                      )}
                    </div>
                  </div>
                  <Chev size={12} className="text-muted-foreground shrink-0 -rotate-180" />
                </button>
              ))}
            </div>
            {!exactMatch && q.trim() && (
              <div className="border-border border-t px-5 py-3">
                <Button
                  variant="outline"
                  className="w-full justify-start"
                  onClick={() => createAndPick(query)}
                >
                  <Plus size={14} />
                  {t('createNew', { name: titleCase(query.trim()) })}
                </Button>
              </div>
            )}
          </div>
        </DialogContent>
      </Dialog>
    </MerchantPickerContext.Provider>
  );
}

// Stable hue from a string, mirroring the Merchants page so the same merchant
// always has the same badge colour.
function hashHue(s: string): number {
  return [...s].reduce((a, ch) => a + ch.charCodeAt(0), 0) % 360;
}

function titleCase(s: string): string {
  return s
    .split(' ')
    .filter(Boolean)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(' ');
}
