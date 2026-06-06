'use client';

import Link from 'next/link';
import { Check } from 'lucide-react';
import { Icon } from '@/components/primitives';
import { useLedger } from '@/components/ledger-provider';
import { useCurrency } from '@/components/currency-provider';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { cn } from '@/lib/utils';

export function LedgerSwitcher({
  sidebarOpen = true,
  className,
}: {
  sidebarOpen?: boolean;
  className?: string;
}) {
  const { ledgers, active, activeId, setActiveId } = useLedger();
  // The active chip shows the display currency (what amounts are shown in); the
  // dropdown list shows each ledger's own base currency.
  const { currency } = useCurrency();

  return (
    <DropdownMenu>
      {sidebarOpen ? (
        <div
          className={cn(
            'border-sidebar-border flex items-center gap-0.5 rounded-lg border pr-1',
            className,
          )}
        >
          <DropdownMenuTrigger asChild>
            <button
              type="button"
              aria-label="Switch ledger"
              // pl-[9px] = the usual 10px inset minus the chip's 1px border, so the
              // dot rides the same icon column (x=30) as the collapsed state and
              // the nav icons — no shift when the sidebar toggles.
              className="hover:bg-sidebar-accent flex min-w-0 flex-1 items-center gap-2.5 rounded-l-lg py-1.5 pl-[9px] text-left transition-colors"
            >
              <span className="flex size-4 shrink-0 items-center justify-center">
                <span
                  className="size-2.5 rounded-full"
                  style={{ background: active.color }}
                />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block truncate text-[13px] font-medium">{active.name}</span>
                <span className="text-muted-foreground block font-mono text-[10px]">
                  {currency}
                </span>
              </span>
              <Icon
                name="swap"
                size={14}
                className="text-muted-foreground mr-0.5 shrink-0"
              />
            </button>
          </DropdownMenuTrigger>
          <Link
            href="/settings/ledger"
            aria-label="Ledger settings"
            title="Ledger settings"
            className="text-muted-foreground hover:bg-sidebar-accent hover:text-foreground flex size-7 shrink-0 items-center justify-center rounded-md transition-colors"
          >
            <Icon name="cog" size={15} />
          </Link>
        </div>
      ) : (
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            aria-label="Switch ledger"
            title={active.name}
            className={cn(
              // border-transparent + pl-[9px] mirror the expanded chip's border
              // geometry so the dot stays on the icon column (x=30).
              'hover:bg-sidebar-accent flex w-full items-center rounded-md border border-transparent py-1.5 pr-2.5 pl-[9px] transition-colors',
              className,
            )}
          >
            {/* shrink-0: the collapsed content box is narrower than 16px (the
                aside's right border eats 1px of w-[60px]), so without it this
                box shrinks and the dot lands at x=29.5 instead of 30. */}
            <span className="flex size-4 shrink-0 items-center justify-center">
              <span className="size-2.5 rounded-full" style={{ background: active.color }} />
            </span>
            {/* Invisible zero-width replica of the expanded chip's two text lines:
                keeps this trigger exactly as tall as the chip, so the dot doesn't
                sink when the sidebar collapses (the footer is bottom-anchored). */}
            <span aria-hidden className="invisible w-0">
              <span className="block text-[13px] font-medium">{active.name}</span>
              <span className="block font-mono text-[10px]">{currency}</span>
            </span>
          </button>
        </DropdownMenuTrigger>
      )}
      <DropdownMenuContent side="top" align="start" className="w-64">
        <DropdownMenuLabel className="font-serif text-base italic">Ledgers</DropdownMenuLabel>
        <DropdownMenuSeparator />
        {ledgers.map((l) => (
          <DropdownMenuItem
            key={l.id}
            onSelect={() => setActiveId(l.id)}
            className="items-start gap-2.5 py-2"
          >
            <span
              className="mt-1 size-2.5 shrink-0 rounded-full"
              style={{ background: l.color }}
            />
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2 text-[13px] font-medium">
                <span className="truncate">{l.name}</span>
                <span className="text-muted-foreground font-mono text-[10px]">{l.base}</span>
              </div>
              <div className="text-muted-foreground truncate text-xs">{l.tagline}</div>
            </div>
            {l.id === activeId && <Check className="text-primary mt-0.5 size-4 shrink-0" />}
          </DropdownMenuItem>
        ))}
        <DropdownMenuSeparator />
        <DropdownMenuItem
          onSelect={() => {
            // TODO: open create-ledger flow (function to be wired later)
          }}
          className="text-muted-foreground gap-2.5 py-2"
        >
          <Icon name="plus" size={16} className="shrink-0" />
          <span className="text-[13px] font-medium">New ledger</span>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
