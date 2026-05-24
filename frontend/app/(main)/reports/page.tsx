'use client';

import { useTweaks } from '@/components/TweaksContext';
import { Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton } from '@/components/MobileComponents';

export default function ReportsPage() {
  const { theme: th } = useTweaks();

  return (
    <MobilePage
      header={
        <ScreenHeader title="Reports" trailing={<IconButton icon="doc"/>}/>
      }
    >
      <div style={{ padding: '40px 20px 120px', textAlign: 'center', color: th.muted }}>
        <div style={{ fontFamily: th.display, fontSize: 24, fontStyle: 'italic' }}>Reports coming soon</div>
        <div style={{ fontSize: 13, marginTop: 8 }}>Export and analyze your spending patterns</div>
      </div>
    </MobilePage>
  );
}