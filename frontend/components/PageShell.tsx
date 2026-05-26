'use client';

import { ReactNode } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
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
}: PageShellProps) {
  const pathname = usePathname();
  const tabBarTabs = mobileTabs ?? tabs;

  const isActivePath = (path?: string) => {
    if (!path) return false;
    if (path === '/accounts') return pathname === '/accounts' || pathname === '/';
    return pathname === path || pathname.startsWith(`${path}/`);
  };

  return (
    <div className={styles.shell}>
      <aside
        className={`${styles.sidebar} ${sidebarOpen ? styles.sidebarOpen : styles.sidebarCollapsed}`}
        aria-label="Primary navigation"
      >
        <div className={styles.brand}>
          {brand?.toggleable ? (
            <button
              type="button"
              className={styles.toggleButton}
              aria-label={sidebarOpen ? 'Collapse sidebar' : 'Expand sidebar'}
              aria-expanded={sidebarOpen}
              onClick={onSidebarToggle}
            >
              <Icon name={sidebarOpen ? 'menu' : 'arrow-r'} size={16} />
            </button>
          ) : (
            <div className={styles.brandGlyph}>{brand?.glyph ?? brand?.label?.charAt(0) ?? 'F'}</div>
          )}
          {sidebarOpen && <span className={styles.brandLabel}>{brand?.label ?? 'Finch'}</span>}
        </div>

        {tabs.length > 0 && (
          <nav className={styles.navSection}>
            {tabs.map((tab) => (
              <Link
                key={tab.id}
                href={tab.path ?? '/'}
                title={tab.label}
                className={`${styles.navTab} ${isActivePath(tab.path) ? styles.navTabActive : ''}`}
              >
                <Icon name={tab.icon} size={16} stroke={1.5} />
                {sidebarOpen && <span className={styles.navLabel}>{tab.label}</span>}
              </Link>
            ))}
          </nav>
        )}

        <div className={styles.spacer} />

        {bottomLinks?.map((link) => (
          <Link
            key={link.path}
            href={link.path}
            title={link.label}
            className={`${styles.bottomLink} ${link.warnDot ? styles.bottomLinkWarn : ''}`}
          >
            <Icon name={link.icon} size={16} stroke={1.5} />
            {sidebarOpen && <span>{link.label}</span>}
            {link.warnDot && <span className={styles.warnDot} aria-label="Pending items" />}
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

      <main className={styles.main}>
        <div className={styles.desktopHeader}>
          <div className={styles.headerTitle}>{headerTitle}</div>
          <div className={styles.headerActions}>
            <button type="button" className={styles.searchButton}>
              <Icon name="search" size={14} />Search transactions…
            </button>
            {showAdd && (
              <Link href="/add" className={styles.addButton}>
                <Icon name="plus" size={14} stroke={2} />Add expense
              </Link>
            )}
          </div>
        </div>
        <div className={styles.scroll}>{children}</div>
      </main>

      {tabBarTabs.length > 0 && (
        <nav className={styles.tabBar} aria-label="Main navigation">
          {tabBarTabs.map((tab) => (
            <Link
              key={tab.id}
              href={tab.path ?? `/${tab.id}`}
              aria-label={tab.label}
              className={`${styles.tab} ${tab.id === activeTab ? styles.tabActive : ''}`}
            >
              {tab.pinned ? (
                <span className={styles.pinnedButton} aria-hidden>
                  <Icon name={tab.icon ?? 'plus'} size={22} stroke={2.5} />
                </span>
              ) : (
                <>
                  <Icon name={tab.icon} size={22} />
                  <span className={styles.tabLabel}>{tab.label}</span>
                </>
              )}
            </Link>
          ))}
        </nav>
      )}
    </div>
  );
}
