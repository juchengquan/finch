'use client';

import { useMemo, useState } from 'react';
import Link from 'next/link';
import { useTranslations } from 'next-intl';
import { Icon, Sparkline } from '@/components/primitives';
import { useFinanceStore } from '@/lib/store';
import { fmtNative } from '@/lib/data';
import { accountForecast, type ForecastEvent } from '@/lib/select';
import type { AccountRow } from '@/lib/db/domain/accounts/types';
import { cn } from '@/lib/utils';

const today = () => new Date().toISOString().slice(0, 10);
const HORIZONS = [30, 60, 90] as const;
type Horizon = (typeof HORIZONS)[number];

/** Cashflow forecast panel: projects the account's balance forward based on
 *  scheduled templates that touch it (income, expense, transfer legs). Shows
 *  a sparkline, a trough callout if the balance dips below today's, and the
 *  upcoming event list. Pure derived view — no mutations. */
export function AccountForecast({ account }: { account: AccountRow }) {
  const scheduled = useFinanceStore((s) => s.scheduled);
  const [horizon, setHorizon] = useState<Horizon>(30);
  const t = useTranslations('accountForecast');

  const forecast = useMemo(
    () => accountForecast(account, scheduled, today(), horizon),
    [account, scheduled, horizon],
  );

  const willDip = forecast.trough.balance < forecast.startingBalance;
  const balanceSeries = forecast.series.map((s) => s.balance);

  return (
    <div className="bg-card border-border overflow-hidden rounded-[14px] border">
      <div className="border-border flex items-center justify-between border-b px-[18px] py-3.5">
        <div className="text-sm font-semibold">{t('title')}</div>
        <div role="tablist" aria-label={t('horizonAria')} className="bg-secondary inline-flex rounded-full p-0.5 text-[11px]">
          {HORIZONS.map((h) => (
            <button
              key={h}
              type="button"
              role="tab"
              aria-selected={horizon === h}
              onClick={() => setHorizon(h)}
              className={cn(
                'rounded-full px-2.5 py-0.5 transition-colors',
                horizon === h ? 'bg-background text-foreground shadow-sm' : 'text-muted-foreground',
              )}
            >
              {t('horizonLabel', { days: h })}
            </button>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-3 gap-3 px-[18px] py-3.5 text-[12px]">
        <Stat label={t('today')} value={fmtNative(forecast.startingBalance, forecast.currency)} />
        <Stat
          label={t('inDays', { days: horizon })}
          value={fmtNative(forecast.endingBalance, forecast.currency)}
          accent={forecast.endingBalance >= forecast.startingBalance ? 'success' : 'destructive'}
        />
        <Stat
          label={t('lowPoint')}
          value={fmtNative(forecast.trough.balance, forecast.currency)}
          sub={willDip ? forecast.trough.date.slice(5).replace('-', '/') : '—'}
          accent={forecast.trough.balance < 0 ? 'destructive' : willDip ? 'warning' : undefined}
        />
      </div>

      {forecast.series.length > 2 && (
        <div className="px-[18px] pb-3.5">
          <Sparkline
            values={balanceSeries}
            width={320}
            height={48}
            color="var(--color-primary)"
            fillOpacity={0.12}
          />
        </div>
      )}

      {forecast.events.length === 0 ? (
        <div className="border-border border-t px-[18px] py-4 text-center">
          <div className="text-muted-foreground text-[12px]">
            {t('noEvents', { days: horizon })}
          </div>
          <div className="text-muted-foreground/70 mt-1 text-[11px]">
            {t.rich('addTemplate', {
              link: (chunks) => <Link href="/scheduled" className="underline">{chunks}</Link>,
            })}
          </div>
        </div>
      ) : (
        <div className="border-border border-t">
          <div className="text-muted-foreground border-border bg-secondary/30 border-b px-[18px] py-2 font-mono text-[10px] tracking-[1.2px]">
            {t('upcoming', { count: forecast.events.length })}
          </div>
          {forecast.events.slice(0, 8).map((e, i) => (
            <EventRow key={`${e.templateId}-${e.date}-${i}`} event={e} currency={forecast.currency} />
          ))}
          {forecast.events.length > 8 && (
            <div className="text-muted-foreground border-border border-t px-[18px] py-2 text-center text-[11px]">
              {t('moreInHorizon', { count: forecast.events.length - 8, days: horizon })}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function Stat({
  label,
  value,
  sub,
  accent,
}: {
  label: string;
  value: string;
  sub?: string;
  accent?: 'success' | 'destructive' | 'warning';
}) {
  return (
    <div>
      <div className="text-muted-foreground font-mono text-[10px] tracking-[1.2px] uppercase">{label}</div>
      <div
        className={cn(
          'mt-0.5 font-mono font-semibold tabular-nums',
          accent === 'success' && 'text-success',
          accent === 'destructive' && 'text-destructive',
          accent === 'warning' && 'text-warning',
        )}
      >
        {value}
      </div>
      {sub && <div className="text-muted-foreground mt-0.5 text-[10px]">{sub}</div>}
    </div>
  );
}

function EventRow({ event, currency }: { event: ForecastEvent; currency: string }) {
  const inflow = event.amount > 0;
  return (
    <div className="border-border flex items-center gap-3 border-t px-[18px] py-2.5">
      <div className="w-12 shrink-0 text-center">
        <div className="text-muted-foreground font-mono text-[9px] tracking-wide uppercase">
          {event.date.slice(5, 7)}/{event.date.slice(8, 10)}
        </div>
      </div>
      <div className="min-w-0 flex-1">
        <div className="truncate text-[12px]">{event.description}</div>
      </div>
      <div
        className={cn(
          'shrink-0 font-mono text-[12px] font-semibold tabular-nums',
          inflow ? 'text-success' : 'text-foreground',
        )}
      >
        {inflow ? '+' : ''}{fmtNative(event.amount, currency)}
      </div>
      <Icon name={inflow ? 'arrow-r' : 'arrow-r'} size={12} />
    </div>
  );
}
