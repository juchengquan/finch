'use client';

import { useTweaks } from '@/components/TweaksContext';
import { Icon, MerchantGlyph } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton } from '@/components/MobileComponents';
import { SettingsItem } from '@/components/SettingsItem';

export default function SettingsPage() {
  const { theme: th } = useTweaks();
  const { setTweak, tweaks } = useTweaks();

  return (
    <MobilePage>
      <ScreenHeader title="Settings" trailing={<IconButton icon="search" aria-label="Search"/>}/>

      <div style={{ padding: '0 20px 22px', display: 'flex', alignItems: 'center', gap: 14 }}>
        <MerchantGlyph name="Alex Morgan" size={64} bg={th.accent} fg="#fff"/>
        <div style={{ flex: 1 }}>
          <div style={{ fontFamily: th.display, fontSize: 22, letterSpacing: -0.3 }}>Alex Morgan</div>
          <div style={{ fontSize: 12, color: th.muted }}>Personal plan</div>
        </div>
      </div>

      <div style={{ padding: '0 20px' }}>
        <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.2, color: th.muted, textTransform: 'uppercase', paddingBottom: 8 }}>PREFERENCES</div>
        <SettingsItem item={{ label: 'Default currency', value: th.currency, icon: 'wallet' }}/>
        <SettingsItem item={{ label: 'Categories', value: '8 active', icon: 'tag' }}/>
        <SettingsItem item={{ label: 'Notifications', toggle: true, icon: 'bell' }}/>

        <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.2, color: th.muted, textTransform: 'uppercase', paddingTop: 16, paddingBottom: 8 }}>THEME</div>
        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          {(['warm', 'noir', 'forest', 'indigo'] as const).map((pal) => (
            <button type="button" key={pal} aria-pressed={tweaks.palette === pal} onClick={() => setTweak('palette', pal)} style={{
              padding: '8px 16px', borderRadius: 12, border: `2px solid ${tweaks.palette === pal ? th.accent : th.line}`,
              background: tweaks.palette === pal ? `${th.accent}18` : 'transparent',
              color: th.ink, fontSize: 13, cursor: 'pointer', textTransform: 'capitalize', fontFamily: 'inherit',
            }}>{pal}</button>
          ))}
        </div>
      </div>
    </MobilePage>
  );
}