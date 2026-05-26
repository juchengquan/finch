'use client';

import { useState } from 'react';
import { Check } from 'lucide-react';
import { useLedger } from '@/components/ledger-provider';
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet';
import { cn } from '@/lib/utils';

export function LedgerSwitcher({ className }: { className?: string }) {
  const { ledgers, active, activeId, setActiveId } = useLedger();
  const [open, setOpen] = useState(false);

  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger asChild>
        <button
          type="button"
          className={cn(
            'border-border hover:bg-accent flex w-full items-center gap-2.5 rounded-lg border px-2.5 py-2 text-left transition-colors',
            className,
          )}
        >
          <span className="size-2.5 shrink-0 rounded-full" style={{ background: active.color }} />
          <span className="min-w-0 flex-1">
            <span className="block truncate text-[13px] font-medium">{active.name}</span>
            <span className="text-muted-foreground block font-mono text-[10px]">{active.base}</span>
          </span>
        </button>
      </SheetTrigger>
      <SheetContent side="bottom" className="rounded-t-2xl pb-8">
        <SheetHeader>
          <SheetTitle className="font-serif text-xl italic">Ledgers</SheetTitle>
          <SheetDescription>Each ledger is an isolated book with its own base currency.</SheetDescription>
        </SheetHeader>
        <div className="flex flex-col gap-1.5 px-4">
          {ledgers.map((l) => (
            <button
              key={l.id}
              type="button"
              onClick={() => {
                setActiveId(l.id);
                setOpen(false);
              }}
              className={cn(
                'flex items-center gap-3 rounded-xl border p-3 text-left transition-colors',
                l.id === activeId ? 'border-primary bg-accent' : 'border-border hover:bg-accent',
              )}
            >
              <span className="mt-0.5 size-3 shrink-0 rounded-full" style={{ background: l.color }} />
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2 text-sm font-medium">
                  {l.name}
                  <span className="text-muted-foreground font-mono text-[10px]">{l.base}</span>
                </div>
                <div className="text-muted-foreground truncate text-xs">{l.tagline}</div>
              </div>
              {l.id === activeId && <Check className="text-primary size-4 shrink-0" />}
            </button>
          ))}
        </div>
      </SheetContent>
    </Sheet>
  );
}
