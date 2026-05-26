'use client';

import { ScreenHeader, MobilePage, IconButton } from '@/components/MobileComponents';
import { EmptyState } from '@/components/EmptyState';

export default function GoalsPage() {
  return (
    <MobilePage header={<ScreenHeader title="Goals" trailing={<IconButton icon="plus" aria-label="New goal" />} />}>
      <EmptyState title="Goals coming soon" body="Track savings targets and financial milestones" />
    </MobilePage>
  );
}
