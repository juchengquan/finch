'use client';

import { ScreenHeader, MobilePage, IconButton } from '@/components/MobileComponents';
import { EmptyState } from '@/components/EmptyState';

export default function ActivityPage() {
  return (
    <MobilePage header={<ScreenHeader title="Activity" trailing={<IconButton icon="search" aria-label="Search" />} />}>
      <EmptyState title="Activity log coming soon" body="Full history of all account changes" />
    </MobilePage>
  );
}
