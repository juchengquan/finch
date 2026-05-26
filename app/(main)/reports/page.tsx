'use client';

import { ScreenHeader, MobilePage, IconButton } from '@/components/MobileComponents';
import { EmptyState } from '@/components/EmptyState';

export default function ReportsPage() {
  return (
    <MobilePage header={<ScreenHeader title="Reports" trailing={<IconButton icon="doc" aria-label="Export" />} />}>
      <EmptyState title="Reports coming soon" body="Export and analyze your spending patterns" />
    </MobilePage>
  );
}
