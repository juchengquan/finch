'use client';

import { useTweaks } from '@/components/TweaksContext';
import { Money } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { SCHEDULED_ITEMS } from '@/lib/data';
import { ScheduledItem } from '@/components/ScheduledItem';
import styles from './scheduled.module.css';

export default function ScheduledPage() {
  const { theme: th } = useTweaks();

  const totalOutgoing = SCHEDULED_ITEMS.filter(i => i.amount < 0).reduce((s, i) => s + i.amount, 0);
  const totalIncoming = SCHEDULED_ITEMS.filter(i => i.amount > 0).reduce((s, i) => s + i.amount, 0);
  const netTotal = totalIncoming + totalOutgoing;

  return (
    <MobilePage
      header={
        <ScreenHeader
          title="Scheduled"
          trailing={<IconButton icon="search"/>}
        />
      }
    >
      <div className={styles.header}>
        <PageHeader
          label="Next 30 days"
          value={<Money value={netTotal} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>}
          sublabel={
            <span className={styles.incoming}>+<Money value={totalIncoming} currency={th.currency}/> incoming</span>
          }
        />
      </div>

      <div className={styles.body}>
        {SCHEDULED_ITEMS.map((item, i) => (
          <ScheduledItem key={i} item={item}/>
        ))}
      </div>
    </MobilePage>
  );
}