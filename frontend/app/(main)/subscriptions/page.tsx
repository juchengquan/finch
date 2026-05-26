'use client';

import { Money, MerchantGlyph } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { MOCK } from '@/lib/data';

export default function SubscriptionsPage() {
  const subs = MOCK.subscriptions;
  const monthly = subs.reduce((s, x) => s + x.amount, 0);

  return (
    <MobilePage
      header={
        <ScreenHeader title="Subscriptions" trailing={<IconButton icon="plus" aria-label="Add subscription" />} />
      }
    >
      <div className="px-5 pb-[22px]">
        <PageHeader
          label="Monthly subscriptions"
          value={<Money value={monthly} mono={false} />}
          sublabel={
            <>
              <Money value={monthly * 12} /> per year · {subs.length} active
            </>
          }
        />
      </div>

      <div className="flex flex-col gap-2.5 px-5 pb-[120px]">
        {subs.map((s) => (
          <div key={s.id} className="bg-card border-border flex items-center gap-3.5 rounded-xl border p-3.5">
            <MerchantGlyph name={s.name} hue={s.logoHue} size={40} />
            <div className="min-w-0 flex-1">
              <div className="text-sm font-medium">{s.name}</div>
              <div className="text-muted-foreground mt-0.5 text-xs capitalize">
                {s.cadence} · next {s.next}
              </div>
            </div>
            <div className="text-right">
              <Money value={s.amount} className="text-sm font-medium" />
              <div className="text-muted-foreground text-[11px]">
                <Money value={s.amount * 12} />
                /yr
              </div>
            </div>
          </div>
        ))}
      </div>
    </MobilePage>
  );
}
