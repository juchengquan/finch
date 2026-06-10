// frontend/components/MobileShell.tsx — the mobile bottom tab bar.
// Extracted from PageShell.tsx (the mobile portion of the original
// component). The 88px-tall bottom bar (safe-area-inset-aware
// padding) includes a special "pinned" circular add button that
// opens the add-expense dialog instead of navigating. This tree is
// only rendered on viewports < 768px (gated by the PageShell
// dispatcher, which uses useIsDesktop).
//
// Note: the `openAddExpense` import will be moved from
// `./add-expense-sheet` to `./add-expense-dialog` in Task 2 of this
// PR (the sheet→dialog rename). Leave the import path as-is for now.

'use client';

import Link from 'next/link';
import { useTranslations } from 'next-intl';

import { Calendar, Chart, Clock, Plus, Target, Wallet } from '@/components/icons';
import { useAddExpense } from '@/components/add-expense-dialog';
import { cn } from '@/lib/utils';
import type { PageShellProps, Tab } from './shell-types';

// Tab.icon is a string short-name; resolve it to the typed lucide component
// so the renderTab helper can stay declarative. The fallback (Plus) mirrors
// the old shim's behaviour for unknown names — pages that omit the icon in
// a pinned tab land on the add glyph. Only the icons actually reachable in
// the mobile bar (per the catalog in mobile-tabs.ts + the pinned "add" tab)
// are listed; unknown ids fall through to Plus.
const TAB_ICON: Record<string, typeof Plus> = {
  wallet: Wallet,
  target: Target,
  calendar: Calendar,
  chart: Chart,
  clock: Clock,
  plus: Plus,
};

export function MobileShell({
  children,
  tabs = [],
  mobileTabs,
  activeTab,
  headerTitle: _headerTitle,
}: PageShellProps) {
  const { openAddExpense } = useAddExpense();
  const tabBarTabs = mobileTabs ?? tabs;
  const tShell = useTranslations('shell');

  return (
    <div className="bg-background text-foreground flex h-[100dvh] overflow-hidden font-sans">
      <main className="flex min-w-0 flex-1 flex-col">
        <div className="min-h-0 flex-1 overflow-y-auto pb-24 [overscroll-behavior:contain]">
          {children}
        </div>
      </main>
      {tabBarTabs.length > 0 && (
        <nav
          aria-label={tShell('primaryNav')}
          className="border-border bg-background fixed inset-x-0 bottom-0 z-50 flex h-[88px] items-start justify-around border-t px-2 pt-3 pb-[calc(0.75rem+env(safe-area-inset-bottom))] md:hidden"
        >
          {tabBarTabs.map((tab: Tab) => {
            const tabClass = cn(
              'flex min-w-[56px] flex-col items-center gap-1',
              tab.id === activeTab ? 'text-foreground' : 'text-muted-foreground',
            );
            // The pinned (+) tab opens the add-expense dialog instead of navigating.
            if (tab.pinned) {
              const PinnedIcon = TAB_ICON[tab.icon ?? 'plus'] ?? Plus;
              return (
                <button key={tab.id} type="button" aria-label={tab.label} onClick={openAddExpense} className={tabClass}>
                  <span className="bg-primary text-primary-foreground flex size-11 items-center justify-center rounded-full shadow-lg">
                    <PinnedIcon size={22} strokeWidth={2.5} />
                  </span>
                </button>
              );
            }
            const TabBarIcon = TAB_ICON[tab.icon] ?? Plus;
            return (
              <Link key={tab.id} href={tab.path ?? `/${tab.id}`} aria-label={tab.label} className={tabClass}>
                <TabBarIcon size={22} />
                <span className={cn('text-[10px]', tab.id === activeTab && 'font-semibold')}>
                  {tab.label}
                </span>
              </Link>
            );
          })}
        </nav>
      )}
    </div>
  );
}
