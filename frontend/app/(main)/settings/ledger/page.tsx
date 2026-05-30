'use client';

import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { SearchButton } from '@/components/command-palette';
import { SettingsItem } from '@/components/SettingsItem';
import { SettingsTabs } from '@/components/settings-tabs';
import { LedgerSwitcher } from '@/components/ledger-switcher';

export default function LedgerSettingsPage() {
  return (
    <MobilePage>
      <ScreenHeader title="Settings" trailing={<SearchButton />} />

      <div className="px-5 pb-28">
        <SettingsTabs />

        <div className="text-muted-foreground pb-2 font-mono text-[10px] tracking-wider uppercase">
          Active ledger
        </div>
        <div className="md:hidden">
          <LedgerSwitcher />
        </div>
        <div className="text-muted-foreground hidden pt-1 text-xs md:block">
          Switch ledgers from the sidebar.
        </div>

        <div className="text-muted-foreground pt-6 pb-2 font-mono text-[10px] tracking-wider uppercase">
          This ledger
        </div>
        <SettingsItem item={{ label: 'Categories', value: '8 active', icon: 'tag' }} />
      </div>
    </MobilePage>
  );
}
