'use client';

import { Icon } from './primitives';
import { Switch } from '@/components/ui/switch';

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
    <div className="border-border flex items-center gap-3.5 border-b py-3.5">
      <div className="bg-secondary text-secondary-foreground flex size-[30px] shrink-0 items-center justify-center rounded-full">
        <Icon name={item.icon} size={14} />
      </div>
      <div className="flex-1 text-sm">{item.label}</div>
      {item.toggle !== undefined ? (
        <Switch checked={item.toggle} onCheckedChange={item.onToggle ?? (() => {})} />
      ) : (
        <div className="text-muted-foreground flex items-center gap-1.5 font-mono text-xs">
          {item.value && <span>{item.value}</span>}
          <Icon name="chev" size={12} />
        </div>
      )}
    </div>
  );
}
