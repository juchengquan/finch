'use client';

import { ReactNode } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';

import { Icon } from './primitives';
import { Button } from '@/components/ui/button';
import { ThemeToggle } from '@/components/theme-toggle';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { useAddExpense } from '@/components/add-expense-sheet';
import { acctById, catById } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { cn } from '@/lib/utils';

interface Tab {
  id: string;
  icon: string;
  label: string;
  path?: string;
  pinned?: boolean;
}

interface Brand {
  glyph?: string;
  label: string;
  toggleable?: boolean;
}

interface BottomLink {
  icon: string;
  label: string;
  path: string;
  warnDot?: boolean;
}

// Detail routes (`/<section>/<id>`) that show a breadcrumb in the desktop
// header. `name` mirrors what each detail page displays as its current crumb.
const BREADCRUMB_SECTIONS: Record<string, { label: string; name: (id: string) => string }> = {
  accounts: { label: 'Accounts', name: (id) => acctById(id).name || id },
  budgets: { label: 'Budgets', name: (id) => catById(id).name },
  transfers: { label: 'Transfers', name: (id) => id },
  recurring: { label: 'Recurring', name: (id) => id },
};

interface PageShellProps {
  children: ReactNode;
  tabs?: Tab[];
  mobileTabs?: Tab[];
  activeTab?: string;
  brand?: Brand;
  bottomLinks?: BottomLink[];
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
  mobileTabs,
  activeTab,
  brand,
  bottomLinks,
  user,
  sidebarOpen = true,
  onSidebarToggle,
  headerTitle,
  showAdd = false,
  sidebarFooter,
}: PageShellProps) {
  const pathname = usePathname();
  const { openAddExpense } = useAddExpense();
  const accountOverrides = useFinanceStore((s) => s.accountOverrides);
  const tabBarTabs = mobileTabs ?? tabs;

  const segments = pathname.split('/').filter(Boolean);
  const section = BREADCRUMB_SECTIONS[segments[0]];
  const crumb =
    section && segments[1]
      ? {
          label: section.label,
          parent: `/${segments[0]}`,
          current:
            (segments[0] === 'accounts' && accountOverrides[segments[1]]?.name) ||
            section.name(segments[1]),
        }
      : null;

  const isActivePath = (path?: string) => {
    if (!path) return false;
    if (path === '/accounts') return pathname === '/accounts' || pathname === '/';
    return pathname === path || pathname.startsWith(`${path}/`);
  };

  return (
    <div className="bg-background text-foreground flex h-[100dvh] overflow-hidden font-sans">
      <aside
        aria-label="Primary navigation"
        className={cn(
          'bg-sidebar text-sidebar-foreground border-sidebar-border hidden h-[100dvh] shrink-0 flex-col gap-1 overflow-hidden border-r px-3 py-5 transition-[width] duration-200 md:flex',
          sidebarOpen ? 'w-[220px]' : 'w-[60px]',
        )}
      >
        <div className="border-sidebar-border mb-3 border-b pb-[18px]">
          {brand?.toggleable ? (
            <button
              type="button"
              aria-label={sidebarOpen ? 'Collapse sidebar' : 'Expand sidebar'}
              aria-expanded={sidebarOpen}
              onClick={onSidebarToggle}
              className="text-sidebar-foreground/80 hover:bg-sidebar-accent hover:text-sidebar-foreground flex w-full items-center gap-3 rounded-md px-2.5 py-2 transition-colors"
            >
              <Icon name={sidebarOpen ? 'menu' : 'arrow-r'} size={16} />
              {sidebarOpen && (
                <span className="font-serif text-lg italic tracking-tight whitespace-nowrap">
                  {brand?.label ?? 'Finch'}
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
                  {brand?.label ?? 'Finch'}
                </span>
              )}
            </div>
          )}
        </div>

        {tabs.length > 0 && (
          <nav className="flex flex-col gap-1">
            {tabs.map((tab) => (
              <Link
                key={tab.id}
                href={tab.path ?? '/'}
                title={tab.label}
                className={cn(
                  'flex items-center gap-3 rounded-md px-2.5 py-2 text-[13px] transition-colors',
                  isActivePath(tab.path)
                    ? 'bg-sidebar-primary text-sidebar-primary-foreground font-medium'
                    : 'text-sidebar-foreground/80 hover:bg-sidebar-accent hover:text-sidebar-foreground',
                )}
              >
                <Icon name={tab.icon} size={16} />
                {sidebarOpen && <span className="whitespace-nowrap">{tab.label}</span>}
              </Link>
            ))}
          </nav>
        )}

        <div className="flex-1" />

        {bottomLinks?.map((link) => (
          <Link
            key={link.path}
            href={link.path}
            title={link.label}
            className={cn(
              'relative flex items-center gap-3 rounded-md px-2.5 py-2',
              link.warnDot ? 'text-warning' : 'text-muted-foreground hover:text-foreground',
            )}
          >
            <span className="relative">
              <Icon name={link.icon} size={16} />
              {link.warnDot && (
                <span className="bg-warning absolute -top-0.5 -right-0.5 size-2 rounded-full" />
              )}
            </span>
            {sidebarOpen && <span className="whitespace-nowrap">{link.label}</span>}
          </Link>
        ))}

        {sidebarFooter && <div className="mt-1">{sidebarFooter}</div>}

        {user && (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <button
                type="button"
                aria-label="Account menu"
                title={sidebarOpen ? undefined : user.name}
                className={cn(
                  'border-sidebar-border hover:bg-sidebar-accent mt-1 flex items-center gap-2.5 border-t px-2.5 py-2 transition-colors',
                  sidebarOpen ? 'w-full text-left' : 'justify-center',
                )}
              >
                <div className="bg-primary text-primary-foreground flex size-7 shrink-0 items-center justify-center rounded-full font-serif text-sm italic">
                  {user.name.charAt(0)}
                </div>
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
                  Settings
                </Link>
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        )}
      </aside>

      <main className="flex min-w-0 flex-1 flex-col">
        <div className="border-border hidden shrink-0 items-center justify-between gap-4 border-b px-8 py-5 md:flex">
          {crumb ? (
            <nav aria-label="Breadcrumb" className="flex items-center gap-2 text-sm">
              <Link href={crumb.parent} className="text-muted-foreground hover:text-foreground">
                {crumb.label}
              </Link>
              <Icon name="chev" size={11} className="text-muted-foreground" />
              <span className="text-foreground font-medium">{crumb.current}</span>
            </nav>
          ) : (
            <div className="font-serif text-2xl tracking-tight">{headerTitle}</div>
          )}
          <div className="flex items-center gap-2">
            <button
              type="button"
              className="bg-secondary text-muted-foreground flex h-9 w-60 items-center gap-2 rounded-full px-3.5 text-[13px]"
            >
              <Icon name="search" size={14} />
              Search transactions…
            </button>
            <ThemeToggle />
            {showAdd && (
              <Button className="rounded-full" onClick={openAddExpense}>
                <Icon name="plus" size={14} stroke={2} />
                Add expense
              </Button>
            )}
          </div>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto pb-24 [overscroll-behavior:contain] md:pb-0">
          <div className="md:mx-auto md:w-full md:max-w-6xl">{children}</div>
        </div>
      </main>

      {tabBarTabs.length > 0 && (
        <nav
          aria-label="Main navigation"
          className="border-border bg-background fixed inset-x-0 bottom-0 z-50 flex h-[88px] items-start justify-around border-t px-2 pt-3 pb-[calc(0.75rem+env(safe-area-inset-bottom))] md:hidden"
        >
          {tabBarTabs.map((tab) => {
            const tabClass = cn(
              'flex min-w-[56px] flex-col items-center gap-1',
              tab.id === activeTab ? 'text-foreground' : 'text-muted-foreground',
            );
            // The pinned (+) tab opens the add-expense slider instead of navigating.
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
