'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useTweaks } from './TweaksContext';
import { Icon } from './primitives';

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
  const { theme: th } = useTweaks();

  return (
    <div style={{
      position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 50,
      height: 88, background: th.paper,
      borderTop: `1px solid ${th.line}`,
      display: 'flex', alignItems: 'flex-start', justifyContent: 'space-around',
      padding: '12px 8px 24px',
    }}>
      {tabs.map((tab) => {
        const isActive = tab.id === active;
        const isPinned = tab.pinned;
        const href = tab.path ?? `/${tab.id}`;
        return (
          <Link key={tab.id} href={href} style={{
            display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4,
            minWidth: 56, textDecoration: 'none',
          }}>
            {isPinned ? (
              <div style={{
                width: 44, height: 44, borderRadius: 22, background: th.accent,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                color: '#fff', boxShadow: '0 4px 12px rgba(201,100,66,0.3)',
              }}>
                <Icon name={tab.icon ?? 'plus'} size={22} stroke={2.5}/>
              </div>
            ) : (
              <>
                <Icon name={tab.icon ?? 'doc'} size={22} style={{ color: isActive ? th.ink : th.muted }}/>
                <span style={{
                  fontSize: 10, fontWeight: isActive ? 600 : 400,
                  color: isActive ? th.ink : th.muted,
                }}>{tab.label}</span>
              </>
            )}
          </Link>
        );
      })}
    </div>
  );
}

export function ProfileChip() {
  const { theme: th } = useTweaks();
  return (
    <button type="button" style={{
      width: 36, height: 36, borderRadius: 18,
      background: th.accent, color: '#fff',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontFamily: th.display, fontSize: 16, fontStyle: 'italic',
      cursor: 'pointer', border: 'none', padding: 0,
    }}>
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
  const { theme: th } = useTweaks();
  const pathname = usePathname();

  const isActive = (path: string) => {
    if (path === '/accounts') return pathname === '/accounts' || pathname === '/';
    return pathname === path;
  };

  return (
    <div style={{
      width: open ? 220 : 60, background: th.paperAlt, color: th.ink,
      padding: '20px 12px', display: 'flex', flexDirection: 'column', gap: 4,
      borderRight: `1px solid ${th.line}`, flexShrink: 0, transition: 'width 0.2s',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', padding: '0 8px 18px', borderBottom: `1px solid ${th.line}`, marginBottom: 12 }}>
        {brand.toggleable ? (
          <button type="button" aria-label={open ? 'Collapse sidebar' : 'Expand sidebar'} aria-expanded={open} onClick={onToggle} style={{ width: 36, height: 36, borderRadius: 18, background: th.paperAlt, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink, cursor: 'pointer', border: 'none', padding: 0 }}>
            <Icon name={open ? 'menu' : 'arrow-r'} size={16}/>
          </button>
        ) : (
          <div style={{ width: 28, height: 28, borderRadius: 14, background: brand.glyphBg ?? th.ink, color: th.paper, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: th.display, fontStyle: 'italic', fontWeight: 500, flexShrink: 0 }}>
            {brand.glyph ?? brand.label.charAt(0)}
          </div>
        )}
        {open && <div style={{ fontFamily: th.display, fontSize: 18, fontStyle: 'italic', letterSpacing: -0.3, marginLeft: brand.toggleable ? 10 : 10 }}>{brand.label}</div>}
      </div>

      {mainTabs.map((tab) => (
        <Link key={tab.id} href={tab.path} style={{
          display: 'flex', alignItems: 'center', gap: 12, padding: '9px 10px', borderRadius: 8,
          background: isActive(tab.path) ? th.ink : 'transparent',
          color: isActive(tab.path) ? th.paper : th.ink2,
          fontSize: 13, fontWeight: isActive(tab.path) ? 500 : 400, cursor: 'pointer',
          textDecoration: 'none',
        }}>
          <Icon name={tab.icon} size={16} stroke={1.5}/>
          {open && <span>{tab.label}</span>}
        </Link>
      ))}

      {open && moreTabs && moreTabs.length > 0 && (
        <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 1.5, padding: '14px 10px 6px' }}>MORE</div>
      )}
      {moreTabs?.map((tab) => (
        <Link key={tab.id} href={tab.path} style={{
          display: 'flex', alignItems: 'center', gap: 12, padding: '9px 10px', borderRadius: 8,
          background: isActive(tab.path) ? th.ink : 'transparent',
          color: isActive(tab.path) ? th.paper : th.ink2,
          fontSize: 13, fontWeight: isActive(tab.path) ? 500 : 400, cursor: 'pointer',
          textDecoration: 'none',
        }}>
          <Icon name={tab.icon} size={16} stroke={1.5}/>
          {open && <span>{tab.label}</span>}
        </Link>
      ))}

      <div style={{ flex: 1 }}/>

      {bottomLinks?.map((link) => (
        <Link key={link.path} href={link.path} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '8px 10px', borderRadius: 8, color: link.warnDot ? th.warn : th.muted, cursor: 'pointer', textDecoration: 'none', position: 'relative' }}>
          <Icon name={link.icon} size={16} stroke={1.5}/>
          {open && <span>{link.label}</span>}
          {link.warnDot && <div style={{ position: 'absolute', top: 6, left: open ? 140 : 16, width: 8, height: 8, borderRadius: 4, background: th.warn }} />}
        </Link>
      ))}

      {user && open && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 10px', borderRadius: 8, borderTop: `0.5px solid ${th.line}`, marginTop: 4 }}>
          <div style={{ width: 28, height: 28, borderRadius: 14, background: th.accent, color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: th.display, fontStyle: 'italic', fontSize: 14, flexShrink: 0 }}>
            {user.name.charAt(0)}
          </div>
          <div style={{ fontSize: 12, lineHeight: 1.3 }}>
            <div style={{ fontWeight: 500 }}>{user.name}</div>
            <div style={{ color: th.muted, fontSize: 11 }}>{user.label}</div>
          </div>
        </div>
      )}
    </div>
  );
}

interface ScreenHeaderProps {
  title: string;
  back?: boolean;
  leading?: React.ReactNode;
  trailing?: React.ReactNode;
}

export function ScreenHeader({ title, back = false, leading, trailing }: ScreenHeaderProps) {
  const { theme: th } = useTweaks();
  const _leading = leading !== undefined ? leading : (back
    ? <button type="button" aria-label="Go back" style={{
        width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`,
        display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink, cursor: 'pointer', background: 'none', padding: 0,
      }}>
        <Icon name="chev-l" size={16}/>
      </button>
    : <ProfileChip/>);
  const _trailing = trailing !== undefined ? trailing : (
    <button type="button" aria-label="Search" style={{
      width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`,
      display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink, cursor: 'pointer', background: 'none', padding: 0,
    }}>
      <Icon name="search" size={16}/>
    </button>
  );

  return (
    <div className="mobile-only">
      <div style={{
        display: 'grid', gridTemplateColumns: '1fr auto 1fr', alignItems: 'center',
        padding: 'calc(16px + env(safe-area-inset-top)) 20px 16px', gap: 8,
      }}>
        <div style={{ justifySelf: 'start', minHeight: 36 }}>{_leading}</div>
        <div style={{
          fontFamily: th.display, fontSize: 18, fontStyle: 'italic', letterSpacing: -0.2,
          textAlign: 'center', color: th.ink,
        }}>{title}</div>
        <div style={{ justifySelf: 'end', display: 'flex', alignItems: 'center', gap: 8, minHeight: 36 }}>{_trailing}</div>
      </div>
    </div>
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
  const { theme: th } = useTweaks();
  return (
    <div style={{ paddingTop: borderTop ? 18 : 0 }}>
      <div style={{ fontSize: 10, color: th.muted, letterSpacing: 1.2, textTransform: 'uppercase' }}>{label}</div>
      <div style={{ fontFamily: th.display, fontSize: 48, letterSpacing: -2, lineHeight: 1, marginTop: 6, fontWeight: 400 }}>{value}</div>
      {sublabel && <div style={{ fontSize: 12, color: th.muted, marginTop: 4 }}>{sublabel}</div>}
      {trend && (
        <div style={{
          marginTop: 8, padding: '4px 10px', display: 'inline-flex', alignItems: 'center', gap: 6,
          background: `${trend.color}1a`, color: trend.color, borderRadius: 10, fontSize: 11, fontWeight: 500
        }}>
          <Icon name={trend.icon} size={12}/>{trend.text}
        </div>
      )}
    </div>
  );
}

export function SchemaChip({ label }: { label: string }) {
  const { theme: th } = useTweaks();
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', height: 18, padding: '0 6px',
      fontFamily: th.mono, fontSize: 9, letterSpacing: 0.5, color: th.muted,
      border: `1px solid ${th.line}`, borderRadius: 4,
    }}>{label}</span>
  );
}

export function IconButton({ icon, onClick, 'aria-label': ariaLabel }: { icon: string; onClick?: () => void; 'aria-label'?: string }) {
  const { theme: th } = useTweaks();
  return (
    <button type="button" aria-label={ariaLabel} onClick={onClick} style={{
      width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`,
      display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink, cursor: 'pointer', background: 'none', padding: 0,
    }}>
      <Icon name={icon} size={16}/>
    </button>
  );
}

interface MobilePageProps {
  children: React.ReactNode;
  header?: React.ReactNode;
  contentPadding?: string;
}

export function MobilePage({ children, header, contentPadding }: MobilePageProps) {
  const { theme: th } = useTweaks();
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative', overflow: 'hidden' }}>
      {header && (
        <div style={{ position: 'sticky', top: 0, zIndex: 100, background: th.paper }}>
          {header}
        </div>
      )}
      <div style={{ height: '100%', overflowY: 'auto' }}>
        {contentPadding !== undefined
          ? <div style={{ padding: contentPadding }}>{children}</div>
          : children
        }
      </div>
    </div>
  );
}