'use client';

import Link from 'next/link';
import { Icon, MerchantGlyph, Sparkline } from '@/components/primitives';
import { ScreenHeader, MobilePage, SchemaChip } from '@/components/MobileComponents';
import { LEDGER, fmtNative } from '@/lib/data';
import { cn } from '@/lib/utils';

export default function FxTransactionPage() {
  const fx = LEDGER.fxTx;
  const series = LEDGER.exchangeRates
    .filter((r) => r.currency === fx.currency)
    .slice()
    .reverse()
    .map((r) => r.rate);

  const rows: [string, string][] = [
    ['exchange_rate', `${fx.exchangeRate} ${fx.currency}→SGD`],
    ['rate_date', fx.rateDate],
    ['amount (original)', fmtNative(fx.amount, fx.currency)],
    ['amount_base (locked)', fmtNative(fx.amountBase, 'SGD')],
    ['account', fx.account],
    ['ledger', fx.ledger],
    ['category', fx.category],
    ['status', fx.status],
    ['note', fx.note],
  ];

  return (
    <MobilePage header={<ScreenHeader back title="FX transaction" />}>
      <div className="px-5 pb-[120px]">
        <div className="text-muted-foreground mb-5 flex items-center gap-2 text-xs">
          <Link href="/system" className="text-muted-foreground">
            System
          </Link>
          <Icon name="chev" size={11} />
          <span className="text-foreground">FX transaction</span>
        </div>

        <div className="px-1 pb-6 text-center">
          <div className="flex justify-center">
            <MerchantGlyph name={fx.merchant} size={56} hue={12} />
          </div>
          <div className="mt-3 text-sm font-medium">{fx.merchant}</div>
          <div className="text-muted-foreground text-[11px]">
            {fx.date} · {fx.time} · {fx.account}
          </div>
        </div>

        <div className="mb-3 grid grid-cols-2 gap-3">
          <div className="bg-card border-border rounded-[14px] border p-4">
            <div className="text-muted-foreground font-mono text-[9px] tracking-[1px]">ORIGINAL · {fx.currency}</div>
            <div className="mt-1 font-serif text-2xl">{fmtNative(Math.abs(fx.amount), fx.currency)}</div>
          </div>
          <div className="bg-card border-border rounded-[14px] border p-4">
            <div className="text-muted-foreground font-mono text-[9px] tracking-[1px]">BASE · SGD (LOCKED)</div>
            <div className="mt-1 font-serif text-2xl">{fmtNative(Math.abs(fx.amountBase), 'SGD')}</div>
          </div>
        </div>

        <div className="bg-secondary text-secondary-foreground mb-4 inline-flex items-center gap-2 rounded-[14px] px-3 py-1.5 font-mono text-[10px] tracking-[0.6px]">
          <Icon name="check" size={12} className="text-success" stroke={2} />
          RATE LOCKED @ {fx.exchangeRate} · {fx.rateDate}
        </div>

        <div className="border-border bg-card rounded-[14px] border px-4 py-1">
          {rows.map(([l, v], i) => (
            <div
              key={l}
              className={cn('flex items-center justify-between gap-3 py-3 text-[13px]', i && 'border-border border-t')}
            >
              <span className="text-muted-foreground font-mono text-[11px] tracking-[0.4px]">{l}</span>
              <span className="text-right">{v}</span>
            </div>
          ))}
        </div>

        <div className="border-border bg-card mt-4 rounded-[14px] border p-4">
          <div className="mb-2 flex items-baseline justify-between">
            <div className="text-[13px] font-semibold">
              {fx.currency} → SGD <span className="text-muted-foreground font-normal">· last {series.length} days</span>
            </div>
            <SchemaChip label="exchange_rates" />
          </div>
          <Sparkline values={series} width={300} height={48} color="var(--primary)" />
          <div className="text-muted-foreground mt-2 text-[11px] leading-relaxed">
            Informational only — the base amount is locked at import, not re-derived from today&rsquo;s rate.
          </div>
        </div>
      </div>
    </MobilePage>
  );
}
