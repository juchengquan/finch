'use client';

import { useTweaks } from '@/components/TweaksContext';
import { Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton } from '@/components/MobileComponents';

export default function GoalsPage() {
  const { theme: th } = useTweaks();

  return (
    <MobilePage
      header={
        <ScreenHeader title="Goals" trailing={<IconButton icon="plus"/>}/>
      }
    >
      <div style={{ padding: '40px 20px 120px', textAlign: 'center', color: th.muted }}>
        <div style={{ fontFamily: th.display, fontSize: 24, fontStyle: 'italic' }}>Goals coming soon</div>
        <div style={{ fontSize: 13, marginTop: 8 }}>Track savings targets and financial milestones</div>
      </div>
    </MobilePage>
  );
}