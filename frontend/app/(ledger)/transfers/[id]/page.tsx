'use client';

import { useParams } from 'next/navigation';
import Link from 'next/link';
import { Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { LEDGER, fmtNative } from '@/lib/data';
import { cn } from '@/lib/utils';

interface TransferGroup {
  id: string;
  date: string;
  amountBase: number;
  fromCurrency: string;
  toCurrency: string;
  exchangeRate: number;
  amountFrom?: number;
  amountTo?: number;
  fromAccount: string;
  fromLedger: string;
  toAccount: string;
  toLedger: string;
  notes: string;
}

export default function TransferDetailPage() {
  const params = useParams();
  const id = params.id as string;
  const groups = LEDGER.transferGroups as TransferGroup[];
  const tg = groups.find((t) => t.id === id) ?? groups[0];

  const fromAmount = tg.amountFrom ?? tg.amountBase;
  const toAmount = tg.amountTo ?? tg.amountBase;

  return (
    <MobilePage header={<ScreenHeader title="Transfer" back />}>
      <div className="px-5 pb-[120px]">
        <div className="mb-5 flex items-center gap-2 text-xs text-muted-foreground md:hidden">
          <Link href="/transfers" className="text-muted-foreground">
            Transfers
          </Link>
          <Icon name="chev" size={11} />
          <span className="font-mono text-foreground">{tg.id}</span>
        </div>

        <div className="px-1 pb-[22px] text-center">
          <div className="mt-1 font-serif text-[52px] tracking-[-1.8px] leading-none">
            {fmtNative(fromAmount, tg.fromCurrency)}
          </div>
          <div className="mt-1.5 font-serif text-[18px] italic text-secondary-foreground">
            → {fmtNative(toAmount, tg.toCurrency)} received
          </div>
          <div className="mt-3.5 inline-flex items-center gap-2 rounded-[14px] bg-secondary px-3 py-1.5 font-mono text-[10px] tracking-[0.6px] text-secondary-foreground">
            <Icon name="check" size={12} className="text-success" stroke={2}/>
            RATE LOCKED @ {tg.exchangeRate} · {tg.date}
          </div>
        </div>

        <div className="mb-3 rounded-[14px] border border-border bg-card">
          <div className="flex items-center gap-3 border-b border-dashed border-border p-4">
            <div className="flex h-8 w-8 items-center justify-center rounded-[16px] bg-destructive/10 text-destructive">
              <Icon name="arrow-u" size={16} stroke={2}/>
            </div>
            <div className="flex-1">
              <div className="font-mono text-[9px] tracking-[1px] text-muted-foreground">FROM · {tg.fromLedger.toUpperCase()} LEDGER</div>
              <div className="mt-0.5 text-sm font-medium">{tg.fromAccount}</div>
            </div>
            <div className="font-sans text-base font-medium tabular-nums text-destructive">{fmtNative(-fromAmount, tg.fromCurrency)}</div>
          </div>
          <div className="flex items-center gap-3 p-4">
            <div className="flex h-8 w-8 items-center justify-center rounded-[16px] bg-success/10 text-success">
              <Icon name="arrow-d" size={16} stroke={2}/>
            </div>
            <div className="flex-1">
              <div className="font-mono text-[9px] tracking-[1px] text-muted-foreground">TO · {tg.toLedger.toUpperCase()} LEDGER</div>
              <div className="mt-0.5 text-sm font-medium">{tg.toAccount}</div>
            </div>
            <div className="font-sans text-base font-medium tabular-nums text-success">{fmtNative(toAmount, tg.toCurrency, { signed: true })}</div>
          </div>
        </div>

        <div className="rounded-[14px] border border-border bg-card px-4 py-1">
          {[
            ['transfer_group_id', tg.id],
            ['amount_base',       `${fmtNative(tg.amountBase, tg.fromCurrency)} (locked)`],
            ['exchange_rate',     `${tg.exchangeRate} ${tg.fromCurrency}→${tg.toCurrency}`],
            ['from_currency',     tg.fromCurrency],
            ['to_currency',       tg.toCurrency],
            ['notes',             tg.notes],
          ].map((r, i) => (
            <div key={r[0]} className={cn('flex items-center justify-between py-3 text-[13px]', i && 'border-t border-border')}>
              <span className="font-mono text-[11px] tracking-[0.4px] text-muted-foreground">{r[0]}</span>
              <span className="text-right">{r[1]}</span>
            </div>
          ))}
        </div>

        <div className="mt-3.5 px-1 text-[11px] leading-relaxed text-muted-foreground">
          The exchange rate is locked at import time. Both transactions share <span className="font-mono text-secondary-foreground">amount_base</span> so reports across ledgers stay consistent.
        </div>
      </div>
    </MobilePage>
  );
}
