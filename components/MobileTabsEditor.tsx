'use client';

import { Icon } from './primitives';
import { Button } from '@/components/ui/button';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { useMobileTabs } from '@/components/mobile-tabs-provider';

// Mobile-only editor for the bottom tab bar: each slot picks one section
// (sections already used elsewhere are disabled) and can be reordered with the
// up/down controls. Changes apply live — the bar updates immediately. The
// center "Add" button is fixed and not configurable here.
export function MobileTabsEditor() {
  const { tabIds, setTabIds, catalog } = useMobileTabs();

  const move = (index: number, dir: -1 | 1) => {
    const target = index + dir;
    if (target < 0 || target >= tabIds.length) return;
    const next = [...tabIds];
    [next[index], next[target]] = [next[target], next[index]];
    setTabIds(next);
  };

  const replace = (index: number, id: string) => {
    const next = [...tabIds];
    next[index] = id;
    setTabIds(next);
  };

  const used = new Set(tabIds);

  return (
    <div>
      {tabIds.map((id, i) => {
        const section = catalog.find((t) => t.id === id);
        return (
          <div key={`${id}-${i}`} className="border-border flex items-center gap-3 border-b py-3">
            <div className="bg-secondary text-secondary-foreground flex size-[30px] shrink-0 items-center justify-center rounded-full">
              <Icon name={section?.icon ?? 'wallet'} size={14} />
            </div>
            <Select value={id} onValueChange={(v) => replace(i, v)}>
              <SelectTrigger size="sm" className="flex-1">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {catalog.map((opt) => (
                  <SelectItem key={opt.id} value={opt.id} disabled={opt.id !== id && used.has(opt.id)}>
                    {opt.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <div className="flex shrink-0 items-center gap-1">
              <Button
                variant="outline"
                size="icon"
                className="size-8"
                aria-label={`Move ${section?.label ?? 'section'} up`}
                disabled={i === 0}
                onClick={() => move(i, -1)}
              >
                <Icon name="chev-u" size={14} />
              </Button>
              <Button
                variant="outline"
                size="icon"
                className="size-8"
                aria-label={`Move ${section?.label ?? 'section'} down`}
                disabled={i === tabIds.length - 1}
                onClick={() => move(i, 1)}
              >
                <Icon name="chev-d" size={14} />
              </Button>
            </div>
          </div>
        );
      })}
    </div>
  );
}
