'use client';

import { BarChart } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { MOCK, INSIGHTS, APR_VS_MAY } from '@/lib/data';
import { InsightCard } from '@/components/InsightCard';
import { AprVsMay } from '@/components/AprVsMay';

export default function InsightsPage() {
  return (
    <MobilePage
      header={
        <ScreenHeader
          title="Insights"
          trailing={<IconButton icon="search"/>}
        />
      }
    >
      <div className="px-5 pb-[22px]">
        <PageHeader
          label="You're spending less"
          value={<span className="font-serif text-[60px] leading-none -tracking-[2px]">↓ 8.4%</span>}
          sublabel={
            <span className="text-secondary-foreground font-serif text-base italic">
              than April. Mostly less <span className="text-primary">Shopping</span>.
            </span>
          }
        />
      </div>

      <div className="px-5 pb-[120px]">
        <div className="bg-card border-border mb-4 rounded-xl border p-3.5">
          <div className="mb-3 flex items-baseline justify-between">
            <div className="text-[13px] font-semibold">Monthly spending</div>
            <div className="text-muted-foreground font-mono text-[10px] tracking-[0.8px]">LAST 12 MO</div>
          </div>
          <BarChart values={MOCK.monthly.map(m => m.v)} labels={MOCK.monthly.map(m => m.m[0])} width={310} height={120} color="var(--muted-foreground)" highlight="var(--primary)" muted="var(--secondary)"/>
        </div>

        {INSIGHTS.map((ins) => (
          <InsightCard key={ins.title} insight={ins}/>
        ))}

        <div className="mt-[22px]">
          <div className="mb-2.5 flex items-baseline justify-between">
            <div className="font-serif text-lg italic">Apr vs May</div>
            <span className="text-muted-foreground text-[11px]">Top changes</span>
          </div>
          <AprVsMay data={APR_VS_MAY}/>
        </div>
      </div>
    </MobilePage>
  );
}
