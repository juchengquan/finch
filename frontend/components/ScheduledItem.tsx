'use client';

import { useTweaks } from './TweaksContext';
import { Money } from './primitives';
import styles from './ScheduledItem.module.css';

interface ScheduledItemProps {
  item: {
    day: number;
    month: string;
    label: string;
    amount: number;
    type: string;
    color: string;
  };
}

export function ScheduledItem({ item }: ScheduledItemProps) {
  const { theme: th } = useTweaks();

  return (
    <div className={styles.row}>
      <div className={styles.date}>
        <div className={styles.month}>{item.month}</div>
        <div className={styles.day}>{item.day}</div>
      </div>
      <div className={styles.body}>
        <div className={styles.label}>{item.label}</div>
        <div className={styles.type}>
          <span className={styles.dot} style={{ background: item.color }} />
          {item.type}
        </div>
      </div>
      <Money
        value={item.amount}
        currency={th.currency}
        style={{ fontSize: 14, fontWeight: 500, color: item.amount > 0 ? 'var(--pos)' : 'var(--ink)' }}
      />
    </div>
  );
}
