'use client';

import { useTweaks } from '@/components/TweaksContext';
import { BarChart, Card } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { MOCK, INSIGHTS, APR_VS_MAY } from '@/lib/data';
import { InsightCard } from '@/components/InsightCard';
import { AprVsMay } from '@/components/AprVsMay';
import styles from './insights.module.css';

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
      <div className={styles.header}>
        <PageHeader
          label="You're spending less"
          value={<span className={styles.bigPct}>↓ 8.4%</span>}
          sublabel={
            <span className={styles.subLabel}>
              than April. Mostly less <span className={styles.accent}>Shopping</span>.
            </span>
          }
        />
      </div>

      <div className={styles.body}>
        <Card style={{ marginBottom: 16 }}>
          <div className={styles.chartCardHeader}>
            <div className={styles.chartTitle}>Monthly spending</div>
            <div className={styles.chartRange}>LAST 12 MO</div>
          </div>
          <BarChart values={MOCK.monthly.map(m => m.v)} labels={MOCK.monthly.map(m => m.m[0])} width={310} height={120} color={th.muted} highlight={th.accent} muted={th.paperAlt}/>
        </Card>

        {INSIGHTS.map((ins) => (
          <InsightCard key={ins.title} insight={ins}/>
        ))}

        <div className={styles.section}>
          <div className={styles.sectionHeader}>
            <div className={styles.sectionTitle}>Apr vs May</div>
            <span className={styles.sectionMeta}>Top changes</span>
          </div>
          <AprVsMay data={APR_VS_MAY}/>
        </div>
      </div>
    </MobilePage>
  );
}