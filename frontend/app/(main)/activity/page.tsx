'use client';

import { useTweaks } from '@/components/TweaksContext';
import { Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton } from '@/components/MobileComponents';

export default function ActivityPage() {
  const { theme: th } = useTweaks();

  return (
    <MobilePage
      header={
        <ScreenHeader title="Activity" trailing={<IconButton icon="search"/>}/>
      }
    >
      <div style={{ padding: '40px 20px 120px', textAlign: 'center', color: th.muted }}>
        <div style={{ fontFamily: th.display, fontSize: 24, fontStyle: 'italic' }}>Activity log coming soon</div>
        <div style={{ fontSize: 13, marginTop: 8 }}>Full history of all account changes</div>
      </div>
    </MobilePage>
  );
}