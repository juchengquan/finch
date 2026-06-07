'use client';

import { ReactNode } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useTranslations } from 'next-intl';

import { Icon } from './primitives';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { useAddExpense } from '@/components/add-expense-sheet';
import { SearchButton } from '@/components/command-palette';
import { acctById } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { cn } from '@/lib/utils';

interface Tab {
  id: string;
  icon: string;
  label: string;
  path?: string;
  pinned?: boolean;
  warnDot?: boolean;
}

// A labeled group of nav links rendered under the primary tabs in the desktop
// sidebar (e.g. the "Ledger" admin sections).
interface NavGroup {
  label: string;
  tabs: Tab[];
}

interface Brand {
  glyph?: string;
  label: string;
  toggleable?: boolean;
}

// Detail routes (`/<section>/<id>`) that show a breadcrumb in the desktop
// header. The label is looked up from `nav.<section>`; `name` resolves the
// detail row's display string (live store row when available).
const BREADCRUMB_SECTIONS: Record<string, { navKey: string; name: (id: string) => string }> = {
  accounts: { navKey: 'accounts', name: (id) => acctById(id).name || id },
  budgets: { navKey: 'budgets', name: (id) => id },
  transfers: { navKey: 'transfers', name: (id) => id },
  scheduled: { navKey: 'scheduled', name: (id) => id },
};

// Header titles for top-level routes that aren't represented in the nav, so
// they still get a name. Maps a path segment to the catalog key under
// `shell` (free text title) or `nav` (one of the nav labels).
const EXTRA_TITLES: Record<string, { ns: 'shell' | 'nav'; key: string }> = {
  add: { ns: 'shell', key: 'addExpense' },
  settings: { ns: 'nav', key: 'settings' },
};

interface PageShellProps {
  children: ReactNode;
  tabs?: Tab[];
  navGroups?: NavGroup[];
  mobileTabs?: Tab[];
  activeTab?: string;
  brand?: Brand;
  user?: { name: string; label: string };
  sidebarOpen?: boolean;
  onSidebarToggle?: () => void;
  headerTitle?: string;
  showAdd?: boolean;
  sidebarFooter?: ReactNode;
}

export function PageShell({
  children,
  tabs = [],
  navGroups = [],
  mobileTabs,
  activeTab,
  brand,
  user,
  sidebarOpen = true,
  onSidebarToggle,
  headerTitle,
  showAdd = false,
  sidebarFooter,
}: PageShellProps) {
  const pathname = usePathname();
  const { openAddExpense } = useAddExpense();
  const accounts = useFinanceStore((s) => s.accounts);
  const budgets = useFinanceStore((s) => s.budgets);
  const tabBarTabs = mobileTabs ?? tabs;
  const tNav = useTranslations('nav');
  const tShell = useTranslations('shell');

  const segments = pathname.split('/').filter(Boolean);
  const section = BREADCRUMB_SECTIONS[segments[0]];
  // Resolve the detail row's display name from the live store first (so a
  // renamed account / budget reflects immediately); fall back to the static
  // BREADCRUMB_SECTIONS.name() — used for routes whose detail page derives
  // its title some other way (transfers, scheduled), or when the id doesn't
  // match a row (e.g. mid-route during deletion).
  const liveCurrent = (() => {
    if (!segments[1]) return null;
    if (segments[0] === 'accounts') return accounts.find((a) => a.id === segments[1])?.name ?? null;
    if (segments[0] === 'budgets') return budgets.find((b) => b.id === segments[1])?.name ?? null;
    return null;
  })();
  const crumb =
    section && segments[1]
      ? {
          label: tNav(section.navKey),
          parent: `/${segments[0]}`,
          current: liveCurrent || section.name(segments[1]),
        }
      : null;

  const isActivePath = (path?: string) => {
    if (!path) return false;
    if (path === '/accounts') return pathname === '/accounts' || pathname === '/';
    return pathname === path || pathname.startsWith(`${path}/`);
  };

  // Title shown in the desktop header for top-level (non-detail) routes: the
  // matching nav item's label, an explicit name for off-nav routes, else the
  // group default passed via `headerTitle`.
  const extraTitle = EXTRA_TITLES[segments[0]];
  const pageTitle =
    [...tabs, ...navGroups.flatMap((g) => g.tabs)].find((item) => isActivePath(item.path))?.label ??
    (extraTitle ? (extraTitle.ns === 'shell' ? tShell(extraTitle.key) : tNav(extraTitle.key)) : undefined) ??
    headerTitle;

  const renderTab = (tab: Tab) => (
    <Link
      key={tab.id}
      href={tab.path ?? '/'}
      title={tab.label}
      className={cn(
        // Fixed h-9 (not py): icon-only rows would otherwise be ~3.5px shorter
        // than text rows, so icons creep upward cumulatively when collapsing.
        'flex h-9 items-center gap-3 rounded-md px-2.5 text-[13px] transition-colors',
        isActivePath(tab.path)
          ? 'bg-sidebar-primary text-sidebar-primary-foreground font-medium'
          : 'text-sidebar-foreground/80 hover:bg-sidebar-accent hover:text-sidebar-foreground',
      )}
    >
      <span className="relative flex h-4 shrink-0 items-center">
        <Icon name={tab.icon} size={16} />
        {tab.warnDot && !isActivePath(tab.path) && (
          <span className="bg-warning absolute -top-0.5 -right-0.5 size-2 rounded-full" />
        )}
      </span>
      {sidebarOpen && <span className="whitespace-nowrap">{tab.label}</span>}
    </Link>
  );

  return (
    <div className="bg-background text-foreground flex h-[100dvh] overflow-hidden font-sans">
      <aside
        aria-label={tShell('primaryNav')}
        className={cn(
          'bg-sidebar text-sidebar-foreground border-sidebar-border hidden h-[100dvh] shrink-0 flex-col gap-1 overflow-hidden border-r px-3 py-5 transition-[width] duration-200 md:flex',
          sidebarOpen ? 'w-[220px]' : 'w-[60px]',
        )}
      >
        <div className="border-sidebar-border mb-3 border-b pb-[18px]">
          {brand?.toggleable ? (
            <button
              type="button"
              aria-label={sidebarOpen ? tShell('collapseSidebar') : tShell('expandSidebar')}
              aria-expanded={sidebarOpen}
              onClick={onSidebarToggle}
              className="text-sidebar-foreground/80 hover:bg-sidebar-accent hover:text-sidebar-foreground flex w-full items-center gap-3 rounded-md px-2.5 py-2 transition-colors"
            >
              <span className="flex h-7 shrink-0 items-center">
                <Icon name={sidebarOpen ? 'menu' : 'arrow-r'} size={16} />
              </span>
              {sidebarOpen && (
                <span className="font-serif text-lg italic tracking-tight whitespace-nowrap">
                  {brand?.label ?? tShell('brand')}
                </span>
              )}
            </button>
          ) : (
            <div className="flex items-center gap-2.5 px-2">
              <div className="bg-foreground text-background flex size-7 shrink-0 items-center justify-center rounded-full font-serif font-medium italic">
                {brand?.glyph ?? brand?.label?.charAt(0) ?? 'F'}
              </div>
              {sidebarOpen && (
                <span className="font-serif text-lg italic tracking-tight whitespace-nowrap">
                  {brand?.label ?? tShell('brand')}
                </span>
              )}
            </div>
          )}
        </div>

        {/* overflow-x-hidden: overflow-y alone computes overflow-x to 'auto', which
            flashes a horizontal scrollbar while the width transition runs with the
            full-width (whitespace-nowrap) labels already rendered. */}
        <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-x-hidden overflow-y-auto">
          {tabs.length > 0 && <nav className="flex flex-col gap-1">{tabs.map(renderTab)}</nav>}

          {navGroups.map((group) => (
            <nav key={group.label} className="flex flex-col gap-1">
              {/* Fixed-height in both states (label ↔ hairline) so the group's
                  icons don't jump vertically when the label unmounts. */}
              <div className="text-muted-foreground flex h-[19px] items-center px-2.5 pb-1 text-[10px] font-medium tracking-[0.08em] uppercase">
                {sidebarOpen ? (
                  group.label
                ) : (
                  <span aria-hidden className="bg-sidebar-border h-px w-4" />
                )}
              </div>
              {group.tabs.map(renderTab)}
            </nav>
          ))}
        </div>

        {sidebarFooter && <div className="mt-1">{sidebarFooter}</div>}

        {user && (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <button
                type="button"
                aria-label={tShell('accountMenu')}
                title={sidebarOpen ? undefined : user.name}
                // Left-anchored in both states (no justify-center): the aside's
                // right border makes the collapsed content box 35px, so centered
                // content lands at x=29.5 — off the icon column by half a pixel.
                className="border-sidebar-border hover:bg-sidebar-accent mt-1 flex w-full items-center gap-2.5 border-t px-2.5 py-2 text-left transition-colors"
              >
                {/* w-4 wrapper: centers the 28px avatar on the 16px icon column
                    (x=30) so it doesn't shift when the sidebar collapses. */}
                <span className="flex w-4 shrink-0 justify-center">
                  <div className="bg-primary text-primary-foreground flex size-7 shrink-0 items-center justify-center rounded-full font-serif text-sm italic">
                    {user.name.charAt(0)}
                  </div>
                </span>
                {sidebarOpen && (
                  <>
                    <div className="min-w-0 flex-1 text-xs leading-tight">
                      <div className="text-foreground truncate font-medium">{user.name}</div>
                      <div className="text-muted-foreground text-[11px]">{user.label}</div>
                    </div>
                    <Icon name="chev-u" size={14} className="text-muted-foreground shrink-0" />
                  </>
                )}
              </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent side="top" align="start" className="w-[200px]">
              <DropdownMenuItem asChild>
                <Link href="/settings">
                  <Icon name="cog" size={16} />
                  {tNav('settings')}
                </Link>
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        )}
      </aside>

      <main className="flex min-w-0 flex-1 flex-col">
        <div className="border-border hidden shrink-0 items-center justify-between gap-4 border-b px-8 py-5 md:flex">
          {crumb ? (
            // `min-w-0 flex-1` lets the flex container shrink past its content's
            // natural width; `shrink-0` on the parent label + chevron keeps
            // them whole; `truncate` on the current segment takes the spill.
            // Without this, a long account name pushed the right-side actions
            // onto a second row at 1024-1280px viewport widths.
            <nav aria-label={tShell('breadcrumb')} className="flex min-w-0 flex-1 items-center gap-2 text-sm">
              <Link href={crumb.parent} className="text-muted-foreground shrink-0 hover:text-foreground">
                {crumb.label}
              </Link>
              <Icon name="chev" size={11} className="text-muted-foreground shrink-0" />
              <span className="text-foreground min-w-0 truncate font-medium">{crumb.current}</span>
            </nav>
          ) : (
            <div className="min-w-0 flex-1 truncate font-serif text-2xl tracking-tight">{pageTitle}</div>
          )}
          <div className="flex shrink-0 items-center gap-2">
            <SearchButton />
            {showAdd && (
              <Button
                onClick={openAddExpense}
                size="icon"
                aria-label={tShell('addExpense')}
                title={tShell('addExpense')}
                className="rounded-full"
              >
                <Icon name="plus" size={16} stroke={2} />
              </Button>
            )}
          </div>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto pb-24 [overscroll-behavior:contain] md:pb-0">
          <div className="md:mx-auto md:w-full md:max-w-6xl md:pt-6">{children}</div>
        </div>
      </main>

      {tabBarTabs.length > 0 && (
        <nav
          aria-label={tShell('primaryNav')}
          className="border-border bg-background fixed inset-x-0 bottom-0 z-50 flex h-[88px] items-start justify-around border-t px-2 pt-3 pb-[calc(0.75rem+env(safe-area-inset-bottom))] md:hidden"
        >
          {tabBarTabs.map((tab) => {
            const tabClass = cn(
              'flex min-w-[56px] flex-col items-center gap-1',
              tab.id === activeTab ? 'text-foreground' : 'text-muted-foreground',
            );
            // The pinned (+) tab opens the add-expense dialog instead of navigating.
            if (tab.pinned) {
              return (
                <button key={tab.id} type="button" aria-label={tab.label} onClick={openAddExpense} className={tabClass}>
                  <span className="bg-primary text-primary-foreground flex size-11 items-center justify-center rounded-full shadow-lg">
                    <Icon name={tab.icon ?? 'plus'} size={22} stroke={2.5} />
                  </span>
                </button>
              );
            }
            return (
              <Link key={tab.id} href={tab.path ?? `/${tab.id}`} aria-label={tab.label} className={tabClass}>
                <Icon name={tab.icon} size={22} />
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
