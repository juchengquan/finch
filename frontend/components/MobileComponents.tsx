'use client';

import { Icon } from './primitives';
import styles from './MobileComponents.module.css';

export function ProfileChip() {
  return (
    <button type="button" className={styles.profileChip} aria-label="Profile">
      A
    </button>
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
    <>
      {header && <div className={styles.stickyHeader}>{header}</div>}
      {contentPadding !== undefined
        ? <div style={{ padding: contentPadding }}>{children}</div>
        : children}
    </>
  );
}