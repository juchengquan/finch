'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Icon } from './primitives';
import styles from './MobileComponents.module.css';

interface Tab {
  id: string;
  icon?: string;
  label: string;
  path?: string;
  pinned?: boolean;
}

interface MobileTabBarProps {
  active: string;
  tabs: Tab[];
}

export function MobileTabBar({ active, tabs }: MobileTabBarProps) {
  return (
    <nav className={styles.tabBar} role="navigation" aria-label="Main navigation">
      {tabs.map((tab) => {
        const isActive = tab.id === active;
        const isPinned = tab.pinned;
        const href = tab.path ?? `/${tab.id}`;
        return (
          <Link key={tab.id} href={href} className={`${styles.tab} ${isActive ? styles.tabActive : ''}`}>
            {isPinned ? (
              <button type="button" className={styles.pinnedButton} aria-label={tab.label}>
                <Icon name={tab.icon ?? 'plus'} size={22} stroke={2.5}/>
              </button>
            ) : (
              <>
                <Icon name={tab.icon ?? 'doc'} size={22}/>
                <span className={styles.tabLabel}>{tab.label}</span>
              </>
            )}
          </Link>
        );
      })}
    </nav>
  );
}

export function ProfileChip() {
  return (
    <button type="button" className={styles.profileChip} aria-label="Profile">
      A
    </button>
  );
}

interface SidebarTab {
  id: string;
  icon: string;
  label: string;
  path: string;
}

interface SidebarBrand {
  glyph?: string;
  glyphBg?: string;
  label: string;
  toggleable?: boolean;
}

interface SidebarBottomLink {
  icon: string;
  label: string;
  path: string;
  warnDot?: boolean;
}

interface SidebarProps {
  brand: SidebarBrand;
  mainTabs: SidebarTab[];
  moreTabs?: SidebarTab[];
  bottomLinks?: SidebarBottomLink[];
  user?: { name: string; label: string };
  open: boolean;
  onToggle?: () => void;
}

export function Sidebar({ brand, mainTabs, moreTabs, bottomLinks, user, open, onToggle }: SidebarProps) {
  const pathname = usePathname();

  const isActive = (path: string) => {
    if (path === '/accounts') return pathname === '/accounts' || pathname === '/';
    return pathname === path;
  };

  return (
    <aside className={`${styles.sidebar} ${open ? styles.sidebarOpen : styles.sidebarCollapsed}`} role="complementary">
      <div className={styles.brand}>
        {brand.toggleable ? (
          <button
            type="button"
            className={styles.toggleButton}
            aria-label={open ? 'Collapse sidebar' : 'Expand sidebar'}
            aria-expanded={open}
            onClick={onToggle}
          >
            <Icon name={open ? 'menu' : 'arrow-r'} size={16}/>
          </button>
        ) : (
          <div className={styles.brandGlyph}>
            {brand.glyph ?? brand.label.charAt(0)}
          </div>
        )}
        {open && <span className={styles.brandLabel}>{brand.label}</span>}
      </div>

      <nav className={styles.navSection}>
        {mainTabs.map((tab) => (
          <Link
            key={tab.id}
            href={tab.path}
            className={`${styles.navTab} ${isActive(tab.path) ? styles.navTabActive : ''}`}
          >
            <Icon name={tab.icon} size={16} stroke={1.5}/>
            {open && <span className={styles.navLabel}>{tab.label}</span>}
          </Link>
        ))}
      </nav>

      {open && moreTabs && moreTabs.length > 0 && (
        <div className={styles.sectionLabel}>MORE</div>
      )}
      {moreTabs?.map((tab) => (
        <Link
          key={tab.id}
          href={tab.path}
          className={`${styles.navTab} ${isActive(tab.path) ? styles.navTabActive : ''}`}
        >
          <Icon name={tab.icon} size={16} stroke={1.5}/>
          {open && <span className={styles.navLabel}>{tab.label}</span>}
        </Link>
      ))}

      <div className={styles.spacer}/>

      {bottomLinks?.map((link) => (
        <Link
          key={link.path}
          href={link.path}
          className={`${styles.bottomLink} ${link.warnDot ? styles.bottomLinkWarn : ''}`}
        >
          <Icon name={link.icon} size={16} stroke={1.5}/>
          {open && <span>{link.label}</span>}
          {link.warnDot && <span className={styles.warnDot} aria-label="Pending items"/>}
        </Link>
      ))}

      {user && open && (
        <div className={styles.userProfile}>
          <div className={styles.userAvatar}>{user.name.charAt(0)}</div>
          <div className={styles.userInfo}>
            <div className={styles.userName}>{user.name}</div>
            <div className={styles.userLabel}>{user.label}</div>
          </div>
        </div>
      )}
    </aside>
  );
}

interface ScreenHeaderProps {
  title: string;
  back?: boolean;
  leading?: React.ReactNode;
  trailing?: React.ReactNode;
}

export function ScreenHeader({ title, back = false, leading, trailing }: ScreenHeaderProps) {
  return (
    <header className={styles.screenHeader}>
      <div className={styles.headerGrid}>
        <div className={styles.leading}>
          {leading ?? (back ? (
            <button type="button" className={styles.iconButton} aria-label="Go back">
              <Icon name="chev-l" size={16}/>
            </button>
          ) : (
            <ProfileChip/>
          ))}
        </div>
        <h1 className={styles.title}>{title}</h1>
        <div className={styles.trailing}>
          {trailing ?? (
            <button type="button" className={styles.iconButton} aria-label="Search">
              <Icon name="search" size={16}/>
            </button>
          )}
        </div>
      </div>
    </header>
  );
}

interface PageHeaderProps {
  label: string;
  value: React.ReactNode;
  sublabel?: React.ReactNode;
  trend?: { text: string; icon: string; color: string };
  borderTop?: boolean;
}

export function PageHeader({ label, value, sublabel, trend, borderTop = false }: PageHeaderProps) {
  return (
    <div className={`${styles.pageHeader} ${borderTop ? styles.borderTop : ''}`}>
      <div className={styles.pageLabel}>{label}</div>
      <div className={styles.pageValue}>{value}</div>
      {sublabel && <div className={styles.pageSublabel}>{sublabel}</div>}
      {trend && (
        <div className={`${styles.pageTrend} ${styles[trend.color]}`}>
          <Icon name={trend.icon} size={12}/>{trend.text}
        </div>
      )}
    </div>
  );
}

export function SchemaChip({ label }: { label: string }) {
  return <span className={styles.schemaChip}>{label}</span>;
}

interface IconButtonProps {
  icon: string;
  onClick?: () => void;
  'aria-label'?: string;
  variant?: 'default' | 'ghost' | 'primary';
  size?: 'small' | 'medium' | 'large';
  disabled?: boolean;
}

export function IconButton({
  icon,
  onClick,
  'aria-label': ariaLabel,
  variant = 'default',
  size = 'medium',
  disabled = false,
}: IconButtonProps) {
  const classNames = [
    styles.iconButton,
    styles[variant],
    styles[size],
    disabled ? styles.disabled : '',
  ].filter(Boolean).join(' ');

  return (
    <button
      type="button"
      className={classNames}
      aria-label={ariaLabel}
      onClick={onClick}
      disabled={disabled}
    >
      <Icon name={icon} size={size === 'small' ? 14 : size === 'large' ? 20 : 16}/>
    </button>
  );
}

interface MobilePageProps {
  children: React.ReactNode;
  header?: React.ReactNode;
  contentPadding?: string;
}

export function MobilePage({ children, header, contentPadding }: MobilePageProps) {
  return (
    <div className={styles.mobilePage}>
      {header && (
        <div className={styles.stickyHeader}>
          {header}
        </div>
      )}
      <div className={styles.scrollContainer}>
        {contentPadding !== undefined
          ? <div className={styles.content} style={{ padding: contentPadding }}>{children}</div>
          : children
        }
      </div>
    </div>
  );
}