'use client';

import { useTweaks } from '@/components/TweaksContext';
import { MerchantGlyph } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton } from '@/components/MobileComponents';
import { SettingsItem } from '@/components/SettingsItem';
import { FinchToggleGroup, FinchToggleGroupItem } from '@/components/RadixWrappers';
import { PALETTES, FONT_PAIRS, DENSITY, DEFAULT_TWEAKS } from '@/lib/theme';
import styles from './settings.module.css';

const CURRENCIES = ['USD', 'EUR', 'GBP', 'JPY'];

type TweakKey = keyof typeof DEFAULT_TWEAKS;

function TweakGroup({
  label,
  tweakKey,
  options,
}: {
  label: string;
  tweakKey: TweakKey;
  options: { value: string; label: string }[];
}) {
  const { tweaks, setTweak } = useTweaks();
  return (
    <>
      <div className={styles.sectionLabel}>{label}</div>
      <FinchToggleGroup
        value={tweaks[tweakKey]}
        onValueChange={(val) => {
          if (val) setTweak(tweakKey, val);
        }}
      >
        {options.map((opt) => (
          <FinchToggleGroupItem key={opt.value} value={opt.value}>
            {opt.label}
          </FinchToggleGroupItem>
        ))}
      </FinchToggleGroup>
    </>
  );
}

export default function SettingsPage() {
  const { theme: th } = useTweaks();

  return (
    <MobilePage>
      <ScreenHeader title="Settings" trailing={<IconButton icon="search" aria-label="Search" />} />

      <div className={styles.profile}>
        <MerchantGlyph name="Alex Morgan" size={64} bg={th.accent} fg="#fff" />
        <div className={styles.profileInfo}>
          <div className={styles.profileName}>Alex Morgan</div>
          <div className={styles.profilePlan}>Personal plan</div>
        </div>
      </div>

      <div className={styles.body}>
        <div className={styles.sectionLabel}>Preferences</div>
        <SettingsItem item={{ label: 'Default currency', value: th.currency, icon: 'wallet' }} />
        <SettingsItem item={{ label: 'Categories', value: '8 active', icon: 'tag' }} />
        <SettingsItem item={{ label: 'Notifications', toggle: true, icon: 'bell' }} />

        <TweakGroup
          label="Theme"
          tweakKey="palette"
          options={Object.entries(PALETTES).map(([value, p]) => ({ value, label: p.name }))}
        />
        <TweakGroup
          label="Typeface"
          tweakKey="fonts"
          options={Object.entries(FONT_PAIRS).map(([value, f]) => ({ value, label: f.name }))}
        />
        <TweakGroup
          label="Density"
          tweakKey="density"
          options={Object.keys(DENSITY).map((value) => ({ value, label: value }))}
        />
        <TweakGroup
          label="Currency"
          tweakKey="currency"
          options={CURRENCIES.map((value) => ({ value, label: value }))}
        />
      </div>
    </MobilePage>
  );
}
