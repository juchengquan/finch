'use client';

import { useTweaks } from '@/components/TweaksContext';
import { Card, Ring } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { MOCK, fmtMoneyShort } from '@/lib/data';
import { CategoryRow } from '@/components/CategoryRow';
import styles from './budgets.module.css';

export default function BudgetsPage() {
  const { theme: th } = useTweaks();
  const totalSpent = MOCK.categories.reduce((s, c) => s + c.spent, 0);
  const totalBudget = MOCK.categories.reduce((s, c) => s + c.budget, 0);
  const pct = Math.round((totalSpent / totalBudget) * 100);

  return (
    <MobilePage
      header={
        <ScreenHeader
          title="Budgets"
          trailing={<IconButton icon="search"/>}
        />
      }
    >
      <div className={styles.header}>
        <PageHeader
          label="Spent of budget"
          value={<Ring value={totalSpent} max={totalBudget} size={120} stroke={10} color={th.accent} track={th.paperAlt}>
            <div className={styles.ringContent}>
              <div className={styles.ringPct}>{pct}%</div>
              <div className={styles.ringUsed}>USED</div>
            </div>
          </Ring>}
          sublabel={<>of <span className={styles.subMono}>{fmtMoneyShort(totalBudget, th.currency)}</span></>}
          trend={{ text: 'On track for May', icon: 'check', color: th.pos }}
        />
      </div>

      <div className={styles.body}>
        <Card>
          <div className={styles.cardHeader}>
            <div className={styles.cardTitle}>Categories</div>
            <span className={styles.cardMeta}>SPENT / BUDGET</span>
          </div>
          {MOCK.categories.map((c) => (
            <CategoryRow key={c.id} category={c}/>
          ))}
        </Card>
      </div>
    </MobilePage>
  );
}