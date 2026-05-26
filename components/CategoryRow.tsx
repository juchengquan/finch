'use client';

import { useTweaks } from './TweaksContext';
import { Icon } from './primitives';
import { fmtMoneyShort } from '@/lib/data';
import styles from './CategoryRow.module.css';

interface CategoryRowProps {
  category: {
    id: string;
    name: string;
    icon: string;
    hue: number;
    spent: number;
    budget: number;
  };
}

export function CategoryRow({ category }: CategoryRowProps) {
  const { theme: th } = useTweaks();
  const cpct = (category.spent / category.budget) * 100;
  const over = cpct > 100;
  const remaining = category.budget - category.spent;

  return (
    <div className={styles.row}>
      <div className={styles.icon} style={{ background: `oklch(0.92 0.04 ${category.hue})` }}>
        <Icon name={category.icon} size={18} />
      </div>
      <div className={styles.body}>
        <div className={styles.titleRow}>
          <div className={styles.name}>{category.name}</div>
          <div className={styles.amounts} style={{ color: over ? 'var(--neg)' : 'var(--ink)' }}>
            {fmtMoneyShort(category.spent, th.currency)} / {fmtMoneyShort(category.budget, th.currency)}
          </div>
        </div>
        <div className={styles.track}>
          <div
            className={styles.fill}
            style={{ width: `${Math.min(cpct, 100)}%`, background: over ? 'var(--neg)' : 'var(--accent)' }}
          />
        </div>
        <div className={styles.note} style={{ color: over ? 'var(--neg)' : 'var(--muted)' }}>
          {over ? `${fmtMoneyShort(-remaining, th.currency)} over` : `${fmtMoneyShort(remaining, th.currency)} left`}
        </div>
      </div>
    </div>
  );
}
