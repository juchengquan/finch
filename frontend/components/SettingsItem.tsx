'use client';

import { Icon } from './primitives';
import { FinchToggle } from './RadixWrappers';
import styles from './SettingsItem.module.css';

interface SettingsItemProps {
  item: {
    label: string;
    value?: string;
    icon: string;
    toggle?: boolean;
    onToggle?: (val: boolean) => void;
  };
}

export function SettingsItem({ item }: SettingsItemProps) {
  return (
    <div className={styles.row}>
      <div className={styles.icon}>
        <Icon name={item.icon} size={14} />
      </div>
      <div className={styles.label}>{item.label}</div>
      {item.toggle !== undefined ? (
        <FinchToggle pressed={item.toggle} onPressedChange={item.onToggle ?? (() => {})} size="medium" />
      ) : (
        <div className={styles.value}>
          {item.value && <span>{item.value}</span>}
          <Icon name="chev" size={12} style={{ color: 'var(--muted)' }} />
        </div>
      )}
    </div>
  );
}
