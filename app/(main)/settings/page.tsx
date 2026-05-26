'use client';

import { Icon, MerchantGlyph } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton } from '@/components/MobileComponents';
import { SettingsItem } from '@/components/SettingsItem';
import { ThemeToggle } from '@/components/theme-toggle';
import { useCurrency, type Currency } from '@/components/currency-provider';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

const CURRENCIES: Currency[] = ['USD', 'EUR', 'GBP', 'JPY'];

function Row({ icon, label, children }: { icon: string; label: string; children: React.ReactNode }) {
  return (
    <div className="border-border flex items-center gap-3.5 border-b py-3.5">
      <div className="bg-secondary text-secondary-foreground flex size-[30px] shrink-0 items-center justify-center rounded-full">
        <Icon name={icon} size={14} />
      </div>
      <div className="flex-1 text-sm">{label}</div>
      {children}
    </div>
  );
}

export default function SettingsPage() {
  const { currency, setCurrency } = useCurrency();

  return (
    <MobilePage>
      <ScreenHeader title="Settings" trailing={<IconButton icon="search" aria-label="Search" />} />

      <div className="flex items-center gap-3.5 px-5 pb-[22px]">
        <MerchantGlyph name="Alex Morgan" size={64} bg="var(--primary)" fg="var(--primary-foreground)" />
        <div className="flex-1">
          <div className="font-serif text-[22px] -tracking-[0.3px]">Alex Morgan</div>
          <div className="text-muted-foreground text-xs">Personal plan</div>
        </div>
      </div>

      <div className="px-5 pb-28">
        <div className="text-muted-foreground pb-2 font-mono text-[10px] tracking-wider uppercase">
          Preferences
        </div>
        <SettingsItem item={{ label: 'Categories', value: '8 active', icon: 'tag' }} />
        <SettingsItem item={{ label: 'Notifications', toggle: true, icon: 'bell' }} />

        <div className="text-muted-foreground pt-6 pb-2 font-mono text-[10px] tracking-wider uppercase">
          Appearance
        </div>
        <Row icon="sparkle" label="Theme">
          <ThemeToggle />
        </Row>
        <Row icon="wallet" label="Display currency">
          <Select value={currency} onValueChange={(v) => setCurrency(v as Currency)}>
            <SelectTrigger size="sm" className="w-24">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {CURRENCIES.map((c) => (
                <SelectItem key={c} value={c}>
                  {c}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </Row>
      </div>
    </MobilePage>
  );
}
