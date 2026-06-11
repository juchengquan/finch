// frontend/components/ui/screen-header.tsx
// The mobile-only fixed
// top header with a leading slot (back/profile), centered title, and
// trailing slot (search). z-40 keeps it under modal/dialog overlays
// (z-50). Button sizes are size-11 (44px) to meet WCAG 2.5.5 touch
// targets; desktop instances of SearchButton elsewhere keep the
// default 36px.
'use client';

import { useRouter } from 'next/navigation';
import { useTranslations } from 'next-intl';
import { ChevL } from '@/components/icons';
import { SearchButton } from '@/components/command-palette';
import { Button } from './button';
import { ProfileChip } from './profile-chip';

interface ScreenHeaderProps {
  title: string;
  back?: boolean;
  /** Where the back button navigates. Falls back to browser history when omitted. */
  backHref?: string;
  leading?: React.ReactNode;
  trailing?: React.ReactNode;
}

export function ScreenHeader({ title, back = false, backHref, leading, trailing }: ScreenHeaderProps) {
  const router = useRouter();
  const tShell = useTranslations('shell');
  return (
    <>
      {/* Locked to the top of the viewport (mobile only), like the bottom tab
          bar. z-40 keeps it under modal/sheet overlays (z-50).
          Button sizes are size-11 (44px) to meet WCAG 2.5.5 touch targets;
          desktop instances of SearchButton elsewhere keep the default 36px. */}
      <header className="bg-background fixed inset-x-0 top-0 z-40 md:hidden">
        <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-2 px-5 pt-[calc(1rem+env(safe-area-inset-top))] pb-4">
          <div className="flex min-h-11 items-center gap-2 justify-self-start">
            {leading ??
              (back ? (
                <Button
                  variant="outline"
                  size="icon"
                  className="size-11"
                  aria-label={tShell('goBack')}
                  onClick={() => (backHref ? router.push(backHref) : router.back())}
                >
                  <ChevL size={18} />
                </Button>
              ) : (
                <ProfileChip className="size-11" />
              ))}
          </div>
          <h1 className="text-foreground text-center font-serif text-lg italic tracking-tight">
            {title}
          </h1>
          <div className="flex min-h-11 items-center gap-2 justify-self-end">
            {trailing ?? <SearchButton />}
          </div>
        </div>
      </header>
      {/* Spacer: reserves the fixed header's height in the scroll flow so the
          page content starts below it. Mirrors the header's vertical sizing. */}
      <div aria-hidden className="px-5 pt-[calc(1rem+env(safe-area-inset-top))] pb-4 md:hidden">
        <div className="min-h-11" />
      </div>
    </>
  );
}
