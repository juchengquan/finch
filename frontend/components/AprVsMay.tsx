'use client';

import { useTweaks } from './TweaksContext';
import { fmtMoneyShort } from '@/lib/data';
import styles from './AprVsMay.module.css';

interface AprVsMayProps {
  data: {
    name: string;
    a: number;
    b: number;
    d: number;
  }[];
}

export function AprVsMay({ data }: AprVsMayProps) {
  const { theme: th } = useTweaks();

  return (
    <div>
      {data.map((c) => (
        <div key={c.name} className={styles.row}>
          <div className={styles.name}>{c.name}</div>
          <div className={styles.range}>
            {fmtMoneyShort(c.a, th.currency)} → {fmtMoneyShort(c.b, th.currency)}
          </div>
          <div className={styles.delta} style={{ color: c.d < 0 ? 'var(--pos)' : 'var(--neg)' }}>
            {c.d > 0 ? '+' : ''}{c.d}%
          </div>
        </div>
      ))}
    </div>
  );
}
