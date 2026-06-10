'use client';

import { useParams } from 'next/navigation';
import Link from 'next/link';
import { useTranslations } from 'next-intl';
import { ArrowD, ArrowU, Chev, Check } from '@/components/icons';
import { MobilePage } from '@/components/MobileComponents';
import { ScreenHeader } from '@/components/ui/screen-header';
import { fmtNative } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { selectTransfers } from '@/lib/select';
import { useLedger } from '@/components/ledger-provider';
import { useMoney } from '@/components/use-money';
import { cn } from '@/lib/utils';

export default function TransferDetailPage() {
  const params = useParams();
  const id = params.id as string;
  const { active, activeId } = useLedger();
  const { base } = useMoney();
  const t = useTranslations('transfers.detail');
  const tNav = useTranslations('nav');
  const allTxns = useFinanceStore((s) => s.transactions);
  const accountRows = useFinanceStore((s) => s.accounts);

  const tf = selectTransfers(allTxns, accountRows, activeId).find((tr) => tr.id === id);

  if (!tf) {
    return (
      <MobilePage header={<ScreenHeader title={t('title')} back backHref="/transfers" />}>
        <div className="text-muted-foreground px-5 pt-16 text-center text-sm">{t('notFound')}</div>
      </MobilePage>
    );
  }

  const fromAmount = tf.amount; // native, sent
  const toAmount = tf.toAmount; // native, received
  const crossCurrency = tf.fromCurrency !== tf.toCurrency;
  // The locked rate is implied by the two legs (createTransfer stores it as
  // toAmount/fromAmount; same-currency ⇒ 1).
  const rate = crossCurrency && fromAmount ? Math.round((toAmount / fromAmount) * 1e6) / 1e6 : 1;
  // `amount_base` is the ledger-base figure both legs share. The store keeps each
  // leg's base in `amount` (native lives in `nativeAmount`), so read it off the
  // out-leg of this group.
  const fromLeg = allTxns.find((tx) => tx.transferGroupId === id && tx.amount < 0);
  const amountBase = fromLeg ? Math.abs(fromLeg.amount) : fromAmount;
  const ledgerLabel = active.name.toUpperCase();
  const whenStr = `${tf.date}${tf.time ? ` · ${tf.time}` : ''}`;

  return (
    <MobilePage header={<ScreenHeader title={t('title')} back backHref="/transfers" />}>
      <div className="px-5 pb-[120px]">
        <div className="mb-5 flex items-center gap-2 text-xs text-muted-foreground md:hidden">
          <Link href="/transfers" className="text-muted-foreground">
            {tNav('transfers')}
          </Link>
          <Chev size={11} />
          <span className="font-mono text-foreground">{tf.id}</span>
        </div>

        <div className="px-1 pb-[22px] text-center">
          <div className="mt-1 font-serif text-[52px] tracking-[-1.8px] leading-none">
            {fmtNative(fromAmount, tf.fromCurrency)}
          </div>
          <div className="mt-1.5 font-serif text-[18px] italic text-secondary-foreground">
            {t('received', { amount: fmtNative(toAmount, tf.toCurrency) })}
          </div>
          <div className="mt-3.5 inline-flex items-center gap-2 rounded-[14px] bg-secondary px-3 py-1.5 font-mono text-[10px] tracking-[0.6px] text-secondary-foreground">
            <Check size={12} className="text-success" strokeWidth={2} />
            {crossCurrency ? t('rateLocked', { rate, when: whenStr }) : t('posted', { when: whenStr })}
          </div>
        </div>

        <div className="mb-3 rounded-[14px] border border-border bg-card">
          <div className="flex items-center gap-3 border-b border-dashed border-border p-4">
            <div className="flex h-8 w-8 items-center justify-center rounded-[16px] bg-destructive/10 text-destructive">
              <ArrowU size={16} strokeWidth={2} />
            </div>
            <div className="flex-1">
              <div className="font-mono text-[9px] tracking-[1px] text-muted-foreground">{t('fromLine', { ledger: ledgerLabel })}</div>
              <div className="mt-0.5 text-sm font-medium">{tf.fromName ?? '—'}</div>
            </div>
            <div className="font-sans text-base font-medium tabular-nums text-destructive">{fmtNative(-fromAmount, tf.fromCurrency)}</div>
          </div>
          <div className="flex items-center gap-3 p-4">
            <div className="flex h-8 w-8 items-center justify-center rounded-[16px] bg-success/10 text-success">
              <ArrowD size={16} strokeWidth={2} />
            </div>
            <div className="flex-1">
              <div className="font-mono text-[9px] tracking-[1px] text-muted-foreground">{t('toLine', { ledger: ledgerLabel })}</div>
              <div className="mt-0.5 text-sm font-medium">{tf.toName ?? '—'}</div>
            </div>
            <div className="font-sans text-base font-medium tabular-nums text-success">{fmtNative(toAmount, tf.toCurrency, { signed: true })}</div>
          </div>
        </div>

        <div className="rounded-[14px] border border-border bg-card px-4 py-1">
          {[
            ['transfer_group_id', tf.id],
            ['amount_base',       t('amountBaseLocked', { amount: fmtNative(amountBase, base) })],
            ['exchange_rate',     crossCurrency ? t('rateField', { rate, from: tf.fromCurrency, to: tf.toCurrency }) : t('sameCurrency')],
            ['from_currency',     tf.fromCurrency],
            ['to_currency',       tf.toCurrency],
            ['time',              tf.time ?? '—'],
            ['notes',             tf.note || '—'],
          ].map((r, i) => (
            <div key={r[0]} className={cn('flex items-center justify-between py-3 text-[13px]', i && 'border-t border-border')}>
              <span className="font-mono text-[11px] tracking-[0.4px] text-muted-foreground">{r[0]}</span>
              <span className="text-right">{r[1]}</span>
            </div>
          ))}
        </div>

        <div className="mt-3.5 px-1 text-[11px] leading-relaxed text-muted-foreground">
          {t('explainer')}
        </div>
      </div>
    </MobilePage>
  );
}
