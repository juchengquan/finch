'use client';

import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { SearchButton } from '@/components/command-palette';
import { SettingsTabs } from '@/components/settings-tabs';
import { DevicesList } from '@/components/devices-list';

export default function DevicesSettingsPage() {
  return (
    <MobilePage>
      <ScreenHeader title="Settings" trailing={<SearchButton />} />

      <div className="px-5 pb-28">
        <SettingsTabs />

        <div className="text-muted-foreground pb-2 font-mono text-[10px] tracking-wider uppercase">
          Devices
        </div>
        <DevicesList />
        <div className="text-muted-foreground pt-2 text-xs">
          Every device that has synced this ledger. Sourced from the sync log.
        </div>
      </div>
    </MobilePage>
  );
}
