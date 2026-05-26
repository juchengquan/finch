'use client';

import Link from 'next/link';
import { toast } from 'sonner';
import { Icon, Sparkline } from '@/components/primitives';
import { ScreenHeader, MobilePage, SchemaChip, IconButton } from '@/components/MobileComponents';
import { Button } from '@/components/ui/button';
import { LEDGER } from '@/lib/data';
import { cn } from '@/lib/utils';

const SOURCE_STYLE: Record<string, string> = {
  ECB: 'bg-success/10 text-success',
  Yahoo: 'bg-primary/10 text-primary',
  manual: 'bg-warning/10 text-warning',
};

export default function SystemPage() {
  const rates = LEDGER.exchangeRates;
  const currencies = [...new Set(rates.map((r) => r.currency))];
  const byCurrency = currencies.map((cur) => {
    const series = rates.filter((r) => r.currency === cur).slice().reverse();
    return { cur, latest: series[series.length - 1], values: series.map((s) => s.rate) };
  });

  return (
    <MobilePage
      header={<ScreenHeader title="System" trailing={<IconButton icon="sync" aria-label="Refresh" />} />}
    >
      <div className="px-5 pb-[120px]">
        <div className="mb-3 flex items-baseline justify-between px-1 pt-1">
          <div className="font-serif text-lg italic">Exchange rates</div>
          <SchemaChip label="exchange_rates" />
        </div>
        <div className="bg-card border-border overflow-hidden rounded-xl border">
          {byCurrency.map((row, i) => (
            <div key={row.cur} className={cn('flex items-center gap-3 p-3.5', i && 'border-border border-t')}>
              <div className="w-10 font-mono text-sm font-semibold">{row.cur}</div>
              <div className="flex-1">
                {row.values.length > 1 ? (
                  <Sparkline values={row.values} width={120} height={26} color="var(--primary)" />
                ) : (
                  <span className="text-muted-foreground text-[11px]">single point</span>
                )}
              </div>
              <span
                className={cn(
                  'rounded px-1.5 py-0.5 font-mono text-[9px] uppercase',
                  SOURCE_STYLE[row.latest.source] ?? 'bg-secondary text-muted-foreground',
                )}
              >
                {row.latest.source}
              </span>
              <div className="w-24 text-right font-mono text-[13px] tabular-nums">{row.latest.rate.toFixed(5)}</div>
            </div>
          ))}
        </div>
        <div className="mt-2.5 flex items-center justify-between px-1">
          <Link href="/fx" className="text-primary text-xs">
            See a locked FX transaction →
          </Link>
          <Button
            variant="outline"
            size="sm"
            onClick={() => toast.success('Rates refreshed', { description: 'ECB · just now' })}
          >
            <Icon name="sync" size={12} />
            Refresh now
          </Button>
        </div>

        <div className="mt-7 mb-3 flex items-baseline justify-between px-1">
          <div className="font-serif text-lg italic">Devices</div>
          <SchemaChip label="sync_log" />
        </div>
        <div className="bg-card border-border overflow-hidden rounded-xl border">
          {LEDGER.devices.map((d, i) => (
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
                  last sync {d.last} · last txn {d.txn}
                </div>
              </div>
            </div>
          ))}
        </div>
        <div className="mt-2.5 flex justify-end px-1">
          <Button
            variant="outline"
            size="sm"
            onClick={() => toast.success('Sync complete', { description: 'All devices up to date' })}
          >
            <Icon name="sync" size={12} />
            Sync now
          </Button>
        </div>
      </div>
    </MobilePage>
  );
}
