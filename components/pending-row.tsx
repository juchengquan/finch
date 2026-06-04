'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Icon } from '@/components/primitives';
import { acctById, catById } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { useMoney } from '@/components/use-money';
import { useMerchantPicker, type MerchantResolution } from '@/components/merchant-picker-sheet';
import { matchCounterparty, type CatalogEntry, type Match } from '@/lib/matcher/counterparty';
import { cn } from '@/lib/utils';

import type { Tx } from '@/lib/store';

interface PendingRowProps {
  tx: Tx;
  /** When true, no Confirm/Verify actions render — used in a read-only preview. */
  readOnly?: boolean;
}

/**
 * A single pending row with merchant verification baked in.
 *
 *   - `match.kind === 'verified'`      → row renders the canonical name
 *                                        in a green chip; Confirm is one tap.
 *   - `match.kind === 'unverified'`    → yellow UNVERIFIED tag; Confirm also
 *                                        verifies the counterparty.
 *   - `match.kind === 'ambiguous'`     → chip group with top 3 candidates;
 *                                        user picks one before Confirm.
 *   - `match.kind === 'none'`          → "Save as: [input]" inline with a
 *                                        clean default name; Confirm is
 *                                        disabled until the name is non-empty.
 */
export function PendingRow({ tx, readOnly = false }: PendingRowProps) {
  const { fmt } = useMoney();
  const counterparties = useFinanceStore((s) => s.counterparties);
  const confirmPendingWithMatch = useFinanceStore((s) => s.confirmPendingWithMatch);
  const cancelPending = useFinanceStore((s) => s.cancelPending);
  const { openMerchantPicker } = useMerchantPicker();

  // Project the store's `counterparties` into the matcher's shape. We re-run
  // the matcher only when the raw merchant or the catalog changes — the rest
  // of the row re-renders on every keystroke of unrelated inputs, but the
  // matcher doesn't re-evaluate.
  const catalog: CatalogEntry[] = useMemo(
    () => counterparties.map((c) => ({ id: c.id, name: c.name, verified: c.verified })),
    [counterparties],
  );
  const match = useMemo(() => matchCounterparty(tx.merchant, catalog), [tx.merchant, catalog]);

  // User-overridden merchant resolution (set when the user picks something
  // other than the matcher's top suggestion). Stored as local state per row.
  const [override, setOverride] = useState<MerchantResolution | null>(null);
  const resolution: MerchantResolution | null = override ?? defaultResolution(match);

  // For 'none', track the user-edited name (the suggested default is
  // pre-filled).
  const [newName, setNewName] = useState<string>(() => {
    if (match.kind === 'none') return match.suggestedName;
    return '';
  });

  const inc = tx.amount > 0;
  const cat = catById(tx.category);
  const acct = acctById(tx.account);
  const isFx = tx.currency && tx.currency !== 'SGD' && tx.currency !== 'USD';

  const handleConfirm = () => {
    if (!resolution) {
      toast.error('Pick or name a merchant first');
      return;
    }
    confirmPendingWithMatch(tx.id, resolution);
    toast.success(`Confirmed ${acct?.name ?? ''} · ${resolutionLabel(resolution, tx.merchant)}`);
  };

  const handleCancel = () => {
    cancelPending(tx.id);
    toast(`Voided ${tx.merchant}`);
  };

  const handlePick = (seedQuery: string) => {
    openMerchantPicker(seedQuery, (res) => {
      if (res) setOverride(res);
    });
  };

  return (
    <div className="border-border bg-card mb-2.5 rounded-[14px] border p-4">
      <div className="flex items-start gap-3">
        <div
          className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-lg font-mono text-[11px] font-semibold text-white"
          style={{ background: `oklch(0.65 0.2 ${hashHue(tx.merchant)})` }}
        >
          {tx.merchant.slice(0, 2).toUpperCase()}
        </div>
        <div className="flex-1">
          <div className="flex items-baseline justify-between gap-2">
            <div className="text-sm font-medium">{tx.merchant}</div>
            <div
              className={cn(
                'font-sans text-[15px] font-medium tabular-nums',
                inc ? 'text-success' : 'text-foreground',
              )}
            >
              {fmt(Math.abs(tx.amount))}
            </div>
          </div>
          <div className="text-muted-foreground mt-0.5 flex items-center gap-1.5 text-[11px]">
            {acct?.name ?? tx.account} · {tx.date.replace(/-/g, '/')}
            {tx.time ? ' ' + tx.time.slice(0, 5) : ''} · {cat?.name ?? tx.category}
            {isFx && <span className="text-warning font-mono text-[10px]">· FX</span>}
          </div>
          {tx.note && (
            <div className="bg-secondary text-secondary-foreground mt-2.5 flex items-center gap-2 rounded-lg px-2.5 py-2 text-xs">
              <Icon name="sparkle" size={13} className="text-primary" style={{ flexShrink: 0 }} />
              {tx.note}
            </div>
          )}
        </div>
      </div>

      {!readOnly && (
        <MerchantRow
          tx={tx}
          match={match}
          resolution={resolution}
          newName={newName}
          onNewNameChange={setNewName}
          onPick={handlePick}
          onClearOverride={() => setOverride(null)}
        />
      )}

      {!readOnly && (
        <div className="mt-3 flex gap-1.5">
          <button
            type="button"
            onClick={handleConfirm}
            disabled={!canConfirm(match, resolution, newName)}
            className={cn(
              'flex h-8 flex-1 items-center justify-center gap-1.5 rounded-[16px] text-xs font-medium transition-opacity',
              canConfirm(match, resolution, newName)
                ? 'bg-foreground text-background'
                : 'bg-foreground/30 text-background/70 cursor-not-allowed',
            )}
          >
            <Icon name="check" size={12} stroke={2} />
            {confirmLabel(match, resolution)}
          </button>
          <button
            type="button"
            aria-label="Cancel"
            onClick={handleCancel}
            className="border-border text-muted-foreground flex h-8 w-8 items-center justify-center rounded-[16px] border"
          >
            <Icon name="x" size={12} />
          </button>
        </div>
      )}
    </div>
  );
}

interface MerchantRowProps {
  tx: Tx;
  match: Match;
  resolution: MerchantResolution | null;
  newName: string;
  onNewNameChange: (s: string) => void;
  onPick: (seed: string) => void;
  onClearOverride: () => void;
}

function MerchantRow({ tx, match, resolution, newName, onNewNameChange, onPick, onClearOverride }: MerchantRowProps) {
  // If the user explicitly picked something, show that override.
  if (resolution) {
    return (
      <div className="mt-3 flex items-center gap-1.5">
        <span className="text-muted-foreground text-[11px]">Merchant:</span>
        <button
          type="button"
          onClick={() => onPick(resolution.kind === 'new' ? resolution.name : tx.merchant)}
          className="border-success/30 bg-success/10 text-success inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium"
        >
          {resolution.name}
          <Icon name="chev" size={10} className="-rotate-180" />
        </button>
        <button
          type="button"
          onClick={onClearOverride}
          aria-label="Clear override"
          className="text-muted-foreground hover:text-foreground ml-1 p-1"
        >
          <Icon name="x" size={11} />
        </button>
      </div>
    );
  }

  if (match.kind === 'verified') {
    return (
      <div className="mt-3 flex items-center gap-1.5">
        <span className="text-muted-foreground text-[11px]">Merchant:</span>
        <button
          type="button"
          onClick={() => onPick(tx.merchant)}
          className="border-success/30 bg-success/10 text-success inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium"
        >
          <Icon name="check" size={10} stroke={2.5} />
          {match.candidate.name}
          <Icon name="chev" size={10} className="-rotate-180" />
        </button>
      </div>
    );
  }

  if (match.kind === 'unverified') {
    return (
      <div className="mt-3 flex flex-wrap items-center gap-1.5">
        <span className="text-muted-foreground text-[11px]">Merchant:</span>
        <button
          type="button"
          onClick={() => onPick(tx.merchant)}
          className="border-warning/40 bg-warning/10 text-warning inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium"
        >
          {match.candidate.name}
          <span className="border-warning/40 rounded border px-1 py-0 font-mono text-[8px] tracking-[0.6px]">
            UNVERIFIED
          </span>
          <Icon name="chev" size={10} className="-rotate-180" />
        </button>
      </div>
    );
  }

  if (match.kind === 'ambiguous') {
    return (
      <div className="mt-3 flex flex-col gap-1.5">
        <div className="text-muted-foreground text-[11px]">Pick a merchant:</div>
        <div className="flex flex-wrap gap-1.5">
          {match.candidates.map((c) => (
            <button
              key={c.id}
              type="button"
              onClick={() => onPick(tx.merchant)}
              className="border-border bg-secondary text-foreground hover:border-foreground/30 inline-flex items-center gap-1 rounded-full border px-2.5 py-1 text-xs font-medium"
            >
              {c.name}
              {!c.verified && (
                <span className="border-warning/40 text-warning rounded border px-1 py-0 font-mono text-[8px] tracking-[0.6px]">
                  ?
                </span>
              )}
            </button>
          ))}
          <button
            type="button"
            onClick={() => onPick(tx.merchant)}
            className="border-border text-muted-foreground hover:text-foreground inline-flex items-center gap-1 rounded-full border border-dashed px-2.5 py-1 text-xs"
          >
            <Icon name="search" size={10} />
            Other…
          </button>
        </div>
      </div>
    );
  }

  // match.kind === 'none' — inline name input.
  return (
    <div className="mt-3 flex items-center gap-1.5">
      <span className="text-muted-foreground text-[11px]">Save as:</span>
      <input
        type="text"
        value={newName}
        onChange={(e) => onNewNameChange(e.target.value)}
        placeholder="Merchant name"
        aria-label="New merchant name"
        className="bg-secondary text-foreground placeholder:text-muted-foreground h-7 min-w-0 flex-1 rounded-md border-0 px-2.5 text-xs outline-none"
      />
    </div>
  );
}

// --- helpers ---

function defaultResolution(match: Match): MerchantResolution | null {
  if (match.kind === 'verified' || match.kind === 'unverified') {
    return { kind: 'existing', id: match.candidate.id, name: match.candidate.name };
  }
  if (match.kind === 'ambiguous') {
    // Pre-select the top candidate — but the user can still override. The
    // confirm button works because resolution is non-null. The chip is
    // clickable so they can switch.
    const top = match.candidates[0];
    if (top) return { kind: 'existing', id: top.id, name: top.name };
  }
  return null;
}

function canConfirm(match: Match, resolution: MerchantResolution | null, newName: string): boolean {
  if (match.kind === 'none') return newName.trim().length > 0;
  return resolution !== null;
}

function confirmLabel(match: Match, resolution: MerchantResolution | null): string {
  if (match.kind === 'unverified' && resolution?.kind === 'existing') return 'Confirm & verify';
  if (match.kind === 'none') return 'Confirm & create';
  return 'Confirm';
}

function resolutionLabel(r: MerchantResolution, raw: string): string {
  return r.kind === 'new' ? `saved as ${r.name}` : r.name === raw ? 'confirmed' : `linked to ${r.name}`;
}

function hashHue(s: string): number {
  return [...s].reduce((a, ch) => a + ch.charCodeAt(0), 0) % 360;
}
