'use client';

import { useTweaks } from './TweaksContext';
import { Icon } from './primitives';
import styles from './InsightCard.module.css';

interface InsightCardProps {
  insight: {
    tone: 'pos' | 'warn' | 'neut';
    icon: string;
    title: string;
    body: string;
  };
}

export function InsightCard({ insight }: InsightCardProps) {
  const { theme: th } = useTweaks();
  const c = insight.tone === 'pos' ? th.pos : insight.tone === 'warn' ? th.warn : th.accent;

  return (
    <div className={styles.card}>
      <div className={styles.icon} style={{ background: `${c}1a`, color: c }}>
        <Icon name={insight.icon} size={16} />
      </div>
      <div className={styles.content}>
        <div className={styles.title}>{insight.title}</div>
        <div className={styles.body}>{insight.body}</div>
      </div>
    </div>
  );
}
