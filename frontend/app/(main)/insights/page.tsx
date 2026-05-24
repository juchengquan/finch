'use client';

import { useTweaks } from '@/components/TweaksContext';
import { BarChart, Card } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { MOCK, INSIGHTS, APR_VS_MAY } from '@/lib/data';
import { InsightCard } from '@/components/InsightCard';
import { AprVsMay } from '@/components/AprVsMay';

export default function InsightsPage() {
  const { theme: th } = useTweaks();

  return (
    <MobilePage
      header={
        <ScreenHeader
          title="Insights"
          trailing={<IconButton icon="search"/>}
        />
      }
    >
      <div style={{ padding: '0 20px 22px' }}>
        <PageHeader
          label="You're spending less"
          value={<span style={{ fontFamily: th.display, fontSize: 60, letterSpacing: -2, lineHeight: 1 }}>↓ 8.4%</span>}
          sublabel={
            <span style={{ fontFamily: th.display, fontStyle: 'italic', fontSize: 16, color: th.ink2 }}>
              than April. Mostly less <span style={{ color: th.accent }}>Shopping</span>.
            </span>
          }
        />
      </div>

      <div style={{ padding: '0 20px 120px' }}>
        <Card style={{ marginBottom: 16 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 12 }}>
            <div style={{ fontSize: 13, fontWeight: 600 }}>Monthly spending</div>
            <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.8 }}>LAST 12 MO</div>
          </div>
          <BarChart values={MOCK.monthly.map(m => m.v)} labels={MOCK.monthly.map(m => m.m[0])} width={310} height={120} color={th.muted} highlight={th.accent} muted={th.paperAlt}/>
        </Card>

        {INSIGHTS.map((ins) => (
          <InsightCard key={ins.title} insight={ins}/>
        ))}

        <div style={{ marginTop: 22 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 10 }}>
            <div style={{ fontFamily: th.display, fontSize: 18, fontStyle: 'italic' }}>Apr vs May</div>
            <span style={{ fontSize: 11, color: th.muted }}>Top changes</span>
          </div>
          <AprVsMay data={APR_VS_MAY}/>
        </div>
      </div>
    </MobilePage>
  );
}