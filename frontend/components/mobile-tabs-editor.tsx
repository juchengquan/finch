'use client';

import { useTranslations } from 'next-intl';
import { Calendar, Chart, ChevD, ChevU, Clock, Target, Wallet } from '@/components/icons';
import { Button } from '@/components/ui/button';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { useMobileTabs } from '@/components/mobile-tabs';

// Mobile-only editor for the bottom tab bar: each slot picks one section
// (sections already used elsewhere are disabled) and can be reordered with the
// up/down controls. Changes apply live — the bar updates immediately. The
// center "Add" button is fixed and not configurable here.

const SECTION_ICONS: Record<string, typeof Wallet> = {
  wallet: Wallet,
  target: Target,
  calendar: Calendar,
  chart: Chart,
  clock: Clock,
};

export function MobileTabsEditor() {
  const { tabIds, setTabIds, catalog } = useMobileTabs();
  const t = useTranslations('mobileTabsEditor');

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
        // The catalog exposes a string icon name (see MAIN_TAB_SEEDS in
        // mobile-tabs.ts). Resolve to the typed lucide component so the
        // editor can keep rendering whatever section is being edited.
        const SectionIcon = SECTION_ICONS[section?.icon ?? ''] ?? Wallet;
        return (
          <div key={`${id}-${i}`} className="border-border flex items-center gap-3 border-b py-3">
            <div className="bg-secondary text-secondary-foreground flex size-[30px] shrink-0 items-center justify-center rounded-full">
              <SectionIcon size={14} />
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
                aria-label={t('moveUpAria', { section: section?.label ?? t('sectionFallback') })}
                disabled={i === 0}
                onClick={() => move(i, -1)}
              >
                <ChevU size={14} />
              </Button>
              <Button
                variant="outline"
                size="icon"
                className="size-8"
                aria-label={t('moveDownAria', { section: section?.label ?? t('sectionFallback') })}
                disabled={i === tabIds.length - 1}
                onClick={() => move(i, 1)}
              >
                <ChevD size={14} />
              </Button>
            </div>
          </div>
        );
      })}
    </div>
  );
}
