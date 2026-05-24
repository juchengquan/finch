'use client';

import { useTweaks } from './TweaksContext';
import { Icon } from './primitives';

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
    <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '14px 0', borderBottom: `1px solid ${th.line}` }}>
      <div style={{ width: 30, height: 30, borderRadius: 15, background: th.paperAlt, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink2 }}>
        <Icon name={item.icon} size={14}/>
      </div>
      <div style={{ flex: 1, fontSize: 14 }}>{item.label}</div>
      {item.toggle !== undefined && (
        <label style={{ position: 'relative', display: 'flex', alignItems: 'center', cursor: 'pointer', margin: 0 }}>
          <input type="checkbox" checked={item.toggle} onChange={(e) => item.onToggle?.(e.target.checked)} style={{ opacity: 0, position: 'absolute', width: 0, height: 0 }}/>
          <div style={{ width: 38, height: 22, borderRadius: 11, background: item.toggle ? th.accent : th.paperAlt, position: 'relative', flexShrink: 0, transition: 'background 0.2s' }}>
            <div style={{ position: 'absolute', top: 2, [item.toggle ? 'right' : 'left']: 2, width: 18, height: 18, borderRadius: 9, background: '#fff', boxShadow: '0 1px 2px rgba(0,0,0,0.15)', transition: 'right 0.2s, left 0.2s' }}/>
          </div>
        </label>
      )}
      {!item.toggle && item.value && <Icon name="chev" size={12} style={{ color: th.muted }}/>}
      {!item.toggle && !item.value && <span style={{ fontFamily: th.mono, fontSize: 11, color: th.muted }}>{item.value}</span>}
    </div>
  );
}