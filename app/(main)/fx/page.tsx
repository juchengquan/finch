'use client';

import Link from 'next/link';
import { Icon, MerchantGlyph, Sparkline } from '@/components/primitives';
import { ScreenHeader, MobilePage, SchemaChip } from '@/components/MobileComponents';
import { acctById, catById, fmtNative } from '@/lib/data';
import { LEDGERS } from '@/components/ledger-provider';
import { useFinanceStore } from '@/lib/store';
import { cn } from '@/lib/utils';

export default function FxTransactionPage() {
  const allTxns = useFinanceStore((s) => s.transactions);
  const rates = useFinanceStore((s) => s.exchangeRates);

  // The most recent foreign-currency transaction (native currency ≠ ledger base).
  const baseOf = (ledgerId: string) => LEDGERS.find((l) => l.id === ledgerId)?.base ?? 'USD';
  const fx = allTxns.find(
    (t) => t.currency && t.nativeAmount != null && t.currency !== baseOf(t.ledgerId ?? 'personal'),
  );

  if (!fx) {
    return (
      <MobilePage header={<ScreenHeader back backHref="/settings/ledger" title="FX transaction" />}>
        <div className="text-muted-foreground px-5 pt-16 text-center text-sm">
          No foreign-currency transactions yet.
        </div>
      </MobilePage>
    );
  }

  const base = baseOf(fx.ledgerId ?? 'personal');
  const native = fx.nativeAmount!;
  const rate = native !== 0 ? fx.amount / native : 1;
  const series = rates
    .filter((r) => r.currency === fx.currency)
    .slice()
    .sort((a, b) => (a.date < b.date ? -1 : 1))
    .map((r) => r.rate);

  const rows: [string, string][] = [
    ['exchange_rate', `${rate.toFixed(6)} ${fx.currency}→${base}`],
    ['rate_date', fx.date],
    ['amount (original)', fmtNative(native, fx.currency!)],
    ['amount_base (locked)', fmtNative(fx.amount, base)],
    ['account', acctById(fx.account).name],
    ['category', catById(fx.category).name],
    ['status', fx.pending ? 'pending' : 'confirmed'],
    ['note', fx.note || '—'],
  ];

  return (
    <MobilePage header={<ScreenHeader back backHref="/settings/ledger" title="FX transaction" />}>
      <div className="px-5 pb-[120px]">
        <div className="text-muted-foreground mb-5 flex items-center gap-2 text-xs">
          <Link href="/settings/ledger" className="text-muted-foreground">
            Exchange rates
          </Link>
          <Icon name="chev" size={11} />
          <span className="text-foreground">FX transaction</span>
        </div>

        <div className="px-1 pb-6 text-center">
          <div className="flex justify-center">
            <MerchantGlyph name={fx.merchant} size={56} color="#d16b7a" />
          </div>
          <div className="mt-3 text-sm font-medium">{fx.merchant}</div>
          <div className="text-muted-foreground text-[11px]">
            {fx.date} · {fx.time} · {acctById(fx.account).name}
          </div>
        </div>

        <div className="mb-3 grid grid-cols-2 gap-3">
          <div className="bg-card border-border rounded-[14px] border p-4">
            <div className="text-muted-foreground font-mono text-[9px] tracking-[1px]">ORIGINAL · {fx.currency}</div>
            <div className="mt-1 font-serif text-2xl">{fmtNative(Math.abs(native), fx.currency!)}</div>
          </div>
          <div className="bg-card border-border rounded-[14px] border p-4">
            <div className="text-muted-foreground font-mono text-[9px] tracking-[1px]">BASE · {base} (LOCKED)</div>
            <div className="mt-1 font-serif text-2xl">{fmtNative(Math.abs(fx.amount), base)}</div>
          </div>
        </div>

        <div className="bg-secondary text-secondary-foreground mb-4 inline-flex items-center gap-2 rounded-[14px] px-3 py-1.5 font-mono text-[10px] tracking-[0.6px]">
          <Icon name="check" size={12} className="text-success" stroke={2} />
          RATE LOCKED @ {rate.toFixed(6)} · {fx.date}
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

        {series.length > 1 && (
          <div className="border-border bg-card mt-4 rounded-[14px] border p-4">
            <div className="mb-2 flex items-baseline justify-between">
              <div className="text-[13px] font-semibold">
                {fx.currency} → USD <span className="text-muted-foreground font-normal">· last {series.length} days</span>
              </div>
              <SchemaChip label="exchange_rates" />
            </div>
            <Sparkline values={series} width={300} height={48} color="var(--primary)" />
            <div className="text-muted-foreground mt-2 text-[11px] leading-relaxed">
              Informational only — the base amount is locked at import, not re-derived from today&rsquo;s rate.
            </div>
          </div>
        )}
      </div>
    </MobilePage>
  );
}
