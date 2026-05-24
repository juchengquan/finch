'use client';

import { useTweaks } from '@/components/TweaksContext';
import { Icon, MerchantGlyph } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton } from '@/components/MobileComponents';
import { SettingsItem } from '@/components/SettingsItem';
import { FinchToggleGroup, FinchToggleGroupItem } from '@/components/RadixWrappers';

const PALETTES = ['warm', 'noir', 'forest', 'indigo'] as const;

export default function SettingsPage() {
  const { theme: th } = useTweaks();
  const { setTweak, tweaks } = useTweaks();

  return (
    <MobilePage>
      <ScreenHeader title="Settings" trailing={<IconButton icon="search" aria-label="Search"/>}/>

      <div style={{ padding: '0 20px 22px', display: 'flex', alignItems: 'center', gap: 14 }}>
        <MerchantGlyph name="Alex Morgan" size={64} bg={th.accent} fg="#fff"/>
        <div style={{ flex: 1 }}>
          <div style={{ fontFamily: 'var(--font-display)', fontSize: 22, letterSpacing: -0.3 }}>Alex Morgan</div>
          <div style={{ fontSize: 12, color: 'var(--muted)' }}>Personal plan</div>
        </div>
      </div>

      <div style={{ padding: '0 20px' }}>
        <div style={{ fontFamily: 'var(--font-mono)', fontSize: 10, letterSpacing: 1.2, color: 'var(--muted)', textTransform: 'uppercase', paddingBottom: 8 }}>PREFERENCES</div>
        <SettingsItem item={{ label: 'Default currency', value: th.currency, icon: 'wallet' }}/>
        <SettingsItem item={{ label: 'Categories', value: '8 active', icon: 'tag' }}/>
        <SettingsItem item={{ label: 'Notifications', toggle: true, icon: 'bell' }}/>

        <div style={{ fontFamily: 'var(--font-mono)', fontSize: 10, letterSpacing: 1.2, color: 'var(--muted)', textTransform: 'uppercase', paddingTop: 16, paddingBottom: 8 }}>THEME</div>
        <FinchToggleGroup
          value={tweaks.palette}
          onValueChange={(val) => { if (val) setTweak('palette', val as typeof tweaks.palette); }}
        >
          {PALETTES.map((pal) => (
            <FinchToggleGroupItem key={pal} value={pal} className="paletteButton">
              {pal}
            </FinchToggleGroupItem>
          ))}
        </FinchToggleGroup>
      </div>
    </MobilePage>
  );
}