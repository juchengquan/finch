'use client';

import { LEDGER } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { cn } from '@/lib/utils';

/**
 * The devices/sync list: every device that has synced this ledger, with its
 * last-sync and last-transaction timestamps. Read-only; sourced from sync_log.
 */
export function DevicesList() {
  const storeDevices = useFinanceStore((s) => s.devices);
  const devices = storeDevices.length
    ? storeDevices
    : LEDGER.devices.map((d) => ({ id: d.id, name: d.name, lastSync: d.last, lastTxn: d.txn, current: !!d.current }));

  return (
    <div className="bg-card border-border overflow-hidden rounded-xl border">
      {devices.map((d, i) => (
        <div key={d.id} className={cn('flex items-center gap-3 p-3.5', i && 'border-border border-t')}>
          <div className="bg-secondary text-secondary-foreground flex size-9 shrink-0 items-center justify-center rounded-full font-mono text-xs font-semibold">
            {d.name.charAt(0)}
          </div>
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2 text-sm font-medium">
              {d.name}
              {d.current ? (
                <span className="bg-primary/10 text-primary rounded px-1.5 py-0.5 font-mono text-[9px] uppercase">
                  This device
                </span>
              ) : null}
            </div>
            <div className="text-muted-foreground mt-0.5 text-[11px]">
              last sync {d.lastSync} · last txn {d.lastTxn}
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}
