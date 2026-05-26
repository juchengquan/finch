'use client';

import { ScreenHeader, MobilePage, IconButton } from '@/components/MobileComponents';
import { EmptyState } from '@/components/EmptyState';

export default function SubscriptionsPage() {
  return (
    <MobilePage header={<ScreenHeader title="Subscriptions" trailing={<IconButton icon="plus" aria-label="Add subscription" />} />}>
      <EmptyState title="Subscriptions coming soon" body="Monitor recurring charges across all accounts" />
    </MobilePage>
  );
}
