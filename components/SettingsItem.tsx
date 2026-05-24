'use client';

import { useTweaks } from './TweaksContext';
import { Icon } from './primitives';
import { FinchToggle } from './RadixWrappers';

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
  const { theme: th } = useTweaks();

  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '14px 0', borderBottom: `1px solid var(--line)` }}>
      <div style={{ width: 30, height: 30, borderRadius: 15, background: 'var(--paper-alt)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--ink2)' }}>
        <Icon name={item.icon} size={14}/>
      </div>
      <div style={{ flex: 1, fontSize: 14 }}>{item.label}</div>
      {item.toggle !== undefined && (
        <FinchToggle
          pressed={item.toggle}
          onPressedChange={item.onToggle ?? (() => {})}
          size="medium"
        />
      )}
      {!item.toggle && item.value && <Icon name="chev" size={12} style={{ color: 'var(--muted)' }}/>}
      {!item.toggle && !item.value && <span style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--muted)' }}>{item.value}</span>}
    </div>
  );
}