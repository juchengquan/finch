// frontend/components/ui/profile-chip.tsx — extracted from
// Extracted from the original `MobileComponents.tsx` (pre-PR-4; deleted in PR A); `MobilePage` now lives in `mobile-page.tsx`. The user "A" chip that
// links to /settings, shown in the sidebar and inside ScreenHeader's
// leading slot.
'use client';

import Link from 'next/link';
import { useTranslations } from 'next-intl';
import { cn } from '@/lib/utils';

export function ProfileChip({ className }: { className?: string }) {
  const tNav = useTranslations('nav');
  return (
    <Link
      href="/settings"
      aria-label={tNav('settings')}
      className={cn(
        'bg-primary text-primary-foreground flex size-9 items-center justify-center rounded-full font-serif text-base italic',
        className,
      )}
    >
      A
    </Link>
  );
}
