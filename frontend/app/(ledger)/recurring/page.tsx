'use client';

import { useTweaks } from '@/components/TweaksContext';
import { Icon, StackedBar } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
import { LEDGER } from '@/lib/data';
import styles from './recurring.module.css';

export default function RecurringPage() {
  const { theme: th } = useTweaks();
  const t = LEDGER.recurringTemplates[0];

  return (
    <MobilePage
      header={
        <ScreenHeader
          title="Recurring"
          trailing={<IconButton icon="dots"/>}
        />
      }
    >
      <div className={styles.page}>
        <div className={styles.head}>
          <SchemaChip label="recurring_templates"/>
          <div className={styles.headline}>
            <span className={styles.headlineLead}>Every 25th, you receive</span><br/>
            <span className={styles.headlineAmount}>S$5,800.00</span>
          </div>
          <div className={styles.sub}>
            from <b className={styles.subStrong}>Acme</b> — next on May 25 · awaits your confirmation
          </div>
        </div>

        <div className={styles.splitsHead}>
          <div className={styles.splitsTitle}>Splits</div>
          <SchemaChip label="recurring_splits"/>
        </div>
        <div className={styles.splitsNote}>
          Salary is split across accounts. Total must equal 100%.
        </div>

        <div className={styles.barCard}>
          <StackedBar
            slices={(t.splits || []).map((s, i) => ({ value: s.pct || 0, color: i === 0 ? th.accent : i === 1 ? th.warn : th.pos }))}
            width={310} height={12} radius={6}/>
          <div className={styles.barScale}>
            <span>0%</span><span>50%</span><span>100%</span>
          </div>
        </div>

        {(t.splits || []).map((s, i) => {
          const dot = i === 0 ? th.accent : i === 1 ? th.warn : th.pos;
          const amount = 5800 * s.pct / 100;
          return (
            <div key={i} className={styles.splitCard}>
              <div className={styles.splitRow}>
                <div className={styles.splitDot} style={{ background: dot }}/>
                <div className={styles.splitBody}>
                  <div className={styles.splitTop}>
                    <div className={styles.splitAccount}>{s.account}</div>
                    <div className={styles.splitAmount}>S${amount.toLocaleString(undefined, { maximumFractionDigits: 0 })}</div>
                  </div>
                  <div className={styles.splitMeta}>{s.label} · <span className={styles.splitMetaCode}>amount_pct = {s.pct}</span></div>
                </div>
              </div>
            </div>
          );
        })}

        <div className={styles.addRule}>
          <Icon name="plus" size={14}/>Add split rule
        </div>

        <div className={styles.saveWrap}>
          <div className={styles.save}>
            Save template
          </div>
        </div>
      </div>
    </MobilePage>
  );
}
