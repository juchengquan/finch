'use client';

import { ReactNode } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useTweaks } from './TweaksContext';
import { Icon } from './primitives';
import styles from './PageShell.module.css';

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

interface PageShellProps {
  mode: 'mobile' | 'desktop' | 'split';
  children: ReactNode;
  tabs?: Tab[];
  mobileTabs?: Tab[];
  activeTab?: string;
  brand?: Brand;
  bottomLinks?: BottomLink[];
  user?: { name: string; label: string };
  sidebarOpen?: boolean;
  onSidebarToggle?: () => void;
  header?: ReactNode;
}

const MAIN_MOBILE_TABS = [
  { id: 'accounts', icon: 'wallet', label: 'Accounts', path: '/accounts' },
  { id: 'budgets', icon: 'target', label: 'Budgets', path: '/budgets' },
  { id: 'add', icon: 'plus', label: 'Add', path: '/add', pinned: true },
  { id: 'scheduled', icon: 'calendar', label: 'Scheduled', path: '/scheduled' },
  { id: 'insights', icon: 'chart', label: 'Insights', path: '/insights' },
];

export function PageShell({
  mode,
  children,
  tabs,
  mobileTabs,
  activeTab,
  brand,
  bottomLinks,
  user,
  sidebarOpen = true,
  onSidebarToggle,
  header,
}: PageShellProps) {
  const pathname = usePathname();
  const { theme: th } = useTweaks();

  const displayTabs = tabs ?? MAIN_MOBILE_TABS;
  const displayMobileTabs = mobileTabs ?? displayTabs;
  const isActive = (path?: string) => {
    if (!path) return false;
    if (path === '/accounts') return pathname === '/accounts' || pathname === '/';
    return pathname === path;
  };

  if (mode === 'mobile') {
    return (
      <div className={styles.mobileShell}>
        {header && <div className={styles.stickyHeader}>{header}</div>}
        <div className={styles.scrollContainer}>{children}</div>
        <nav className={styles.tabBar} role="navigation" aria-label="Main navigation">
          {displayMobileTabs.map((tab) => {
            const isTabActive = tab.id === activeTab;
            const isPinned = tab.pinned;
            return (
              <Link key={tab.id} href={tab.path ?? '/'} className={`${styles.tab} ${isTabActive ? styles.tabActive : ''}`}>
                {isPinned ? (
                  <button type="button" className={styles.pinnedButton} aria-label={tab.label}>
                    <Icon name={tab.icon ?? 'plus'} size={22} stroke={2.5}/>
                  </button>
                ) : (
                  <>
                    <Icon name={tab.icon} size={22}/>
                    <span className={styles.tabLabel}>{tab.label}</span>
                  </>
                )}
              </Link>
            );
          })}
        </nav>
      </div>
    );
  }

  if (mode === 'split') {
    return (
      <>
        <div className={styles.mobileShell}>
          {header && <div className={styles.stickyHeader}>{header}</div>}
          <div className={styles.scrollContainer}>{children}</div>
          <nav className={styles.tabBar} role="navigation" aria-label="Main navigation">
            {displayMobileTabs.map((tab) => {
              const isTabActive = tab.id === activeTab;
              const isPinned = tab.pinned;
              return (
                <Link key={tab.id} href={tab.path ?? '/'} className={`${styles.tab} ${isTabActive ? styles.tabActive : ''}`}>
                  {isPinned ? (
                    <button type="button" className={styles.pinnedButton} aria-label={tab.label}>
                      <Icon name={tab.icon ?? 'plus'} size={22} stroke={2.5}/>
                    </button>
                  ) : (
                    <>
                      <Icon name={tab.icon} size={22}/>
                      <span className={styles.tabLabel}>{tab.label}</span>
                    </>
                  )}
                </Link>
              );
            })}
          </nav>
        </div>

        <div className={styles.desktopShell}>
          <aside className={`${styles.sidebar} ${sidebarOpen ? styles.sidebarOpen : styles.sidebarCollapsed}`} role="complementary">
            <div className={styles.brand}>
              {brand?.toggleable ? (
                <button
                  type="button"
                  className={styles.toggleButton}
                  aria-label={sidebarOpen ? 'Collapse sidebar' : 'Expand sidebar'}
                  aria-expanded={sidebarOpen}
                  onClick={onSidebarToggle}
                >
                  <Icon name={sidebarOpen ? 'menu' : 'arrow-r'} size={16}/>
                </button>
              ) : (
                <div className={styles.brandGlyph}>
                  {brand?.glyph ?? brand?.label?.charAt(0) ?? 'F'}
                </div>
              )}
              {sidebarOpen && <span className={styles.brandLabel}>{brand?.label ?? 'Finch'}</span>}
            </div>

            {displayTabs.length > 0 && (
              <nav className={styles.navSection}>
                {displayTabs.map((tab) => (
                  <Link
                    key={tab.id}
                    href={tab.path ?? '/'}
                    className={`${styles.navTab} ${isActive(tab.path) ? styles.navTabActive : ''}`}
                  >
                    <Icon name={tab.icon} size={16} stroke={1.5}/>
                    {sidebarOpen && <span className={styles.navLabel}>{tab.label}</span>}
                  </Link>
                ))}
              </nav>
            )}

            <div className={styles.spacer}/>

            {bottomLinks?.map((link) => (
              <Link
                key={link.path}
                href={link.path}
                className={`${styles.bottomLink} ${link.warnDot ? styles.bottomLinkWarn : ''}`}
              >
                <Icon name={link.icon} size={16} stroke={1.5}/>
                {sidebarOpen && <span>{link.label}</span>}
                {link.warnDot && <span className={styles.warnDot} aria-label="Pending items"/>}
              </Link>
            ))}

            {user && sidebarOpen && (
              <div className={styles.userProfile}>
                <div className={styles.userAvatar}>{user.name.charAt(0)}</div>
                <div className={styles.userInfo}>
                  <div className={styles.userName}>{user.name}</div>
                  <div className={styles.userLabel}>{user.label}</div>
                </div>
              </div>
            )}
          </aside>

          <div className={styles.desktopContent}>
            <div className={styles.desktopHeader}>
              <div/>
              <div className={styles.desktopHeaderRight}>
                <button type="button" className={styles.searchButton}>
                  <Icon name="search" size={14}/>Search transactions…
                </button>
                <Link href="/add" className={styles.addButton}>
                  <Icon name="plus" size={14} stroke={2}/>Add expense
                </Link>
              </div>
            </div>
            <div className={styles.desktopScroll}>{children}</div>
          </div>
        </div>
      </>
    );
  }

  return (
    <div className={styles.desktopShell}>
      <aside className={`${styles.sidebar} ${sidebarOpen ? styles.sidebarOpen : styles.sidebarCollapsed}`} role="complementary">
        <div className={styles.brand}>
          {brand?.toggleable ? (
            <button
              type="button"
              className={styles.toggleButton}
              aria-label={sidebarOpen ? 'Collapse sidebar' : 'Expand sidebar'}
              aria-expanded={sidebarOpen}
              onClick={onSidebarToggle}
            >
              <Icon name={sidebarOpen ? 'menu' : 'arrow-r'} size={16}/>
            </button>
          ) : (
            <div className={styles.brandGlyph}>
              {brand?.glyph ?? brand?.label?.charAt(0) ?? 'F'}
            </div>
          )}
          {sidebarOpen && <span className={styles.brandLabel}>{brand?.label ?? 'Finch'}</span>}
        </div>

        {displayTabs.length > 0 && (
          <nav className={styles.navSection}>
            {displayTabs.map((tab) => (
              <Link
                key={tab.id}
                href={tab.path ?? '/'}
                className={`${styles.navTab} ${isActive(tab.path) ? styles.navTabActive : ''}`}
              >
                <Icon name={tab.icon} size={16} stroke={1.5}/>
                {sidebarOpen && <span className={styles.navLabel}>{tab.label}</span>}
              </Link>
            ))}
          </nav>
        )}

        <div className={styles.spacer}/>

        {bottomLinks?.map((link) => (
          <Link
            key={link.path}
            href={link.path}
            className={`${styles.bottomLink} ${link.warnDot ? styles.bottomLinkWarn : ''}`}
          >
            <Icon name={link.icon} size={16} stroke={1.5}/>
            {sidebarOpen && <span>{link.label}</span>}
            {link.warnDot && <span className={styles.warnDot} aria-label="Pending items"/>}
          </Link>
        ))}

        {user && sidebarOpen && (
          <div className={styles.userProfile}>
            <div className={styles.userAvatar}>{user.name.charAt(0)}</div>
            <div className={styles.userInfo}>
              <div className={styles.userName}>{user.name}</div>
              <div className={styles.userLabel}>{user.label}</div>
            </div>
          </div>
        )}
      </aside>

      <div className={styles.desktopContent}>
        <div className={styles.desktopHeader}>
          <div/>
          <div className={styles.desktopHeaderRight}>
            <button type="button" className={styles.searchButton}>
              <Icon name="search" size={14}/>Search transactions…
            </button>
            <Link href="/add" className={styles.addButton}>
              <Icon name="plus" size={14} stroke={2}/>Add expense
            </Link>
          </div>
        </div>
        <div className={styles.desktopScroll}>{children}</div>
      </div>
    </div>
  );
}