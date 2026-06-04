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
              className="hover:bg-sidebar-accent flex min-w-0 flex-1 items-center gap-2.5 rounded-l-lg py-1.5 pl-2.5 text-left transition-colors"
            >
              <span
                className="size-2.5 shrink-0 rounded-full"
                style={{ background: active.color }}
              />
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
              'hover:bg-sidebar-accent flex w-full items-center rounded-md px-2.5 py-2 transition-colors',
              className,
            )}
          >
            <span className="flex size-4 items-center justify-center">
              <span className="size-2.5 rounded-full" style={{ background: active.color }} />
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
