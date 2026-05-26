'use client';

import { Icon } from './primitives';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';

export function ProfileChip() {
  return (
    <div className="bg-primary text-primary-foreground flex size-9 items-center justify-center rounded-full font-serif text-base italic">
      A
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
  return (
    <header className="bg-background sticky top-0 z-[100] md:hidden">
      <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-2 px-5 pt-[calc(1rem+env(safe-area-inset-top))] pb-4">
        <div className="flex min-h-9 items-center gap-2 justify-self-start">
          {leading ??
            (back ? (
              <Button variant="outline" size="icon" aria-label="Go back">
                <Icon name="chev-l" size={16} />
              </Button>
            ) : (
              <ProfileChip />
            ))}
        </div>
        <h1 className="text-foreground text-center font-serif text-lg italic tracking-tight">
          {title}
        </h1>
        <div className="flex min-h-9 items-center gap-2 justify-self-end">
          {trailing ?? (
            <Button variant="outline" size="icon" aria-label="Search">
              <Icon name="search" size={16} />
            </Button>
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
  trend?: { text: string; icon: string; color: 'pos' | 'neg' | 'warn' };
  borderTop?: boolean;
}

const TREND_CLASS: Record<string, string> = {
  pos: 'bg-success/10 text-success',
  neg: 'bg-destructive/10 text-destructive',
  warn: 'bg-warning/10 text-warning',
};

export function PageHeader({ label, value, sublabel, trend, borderTop = false }: PageHeaderProps) {
  return (
    <div className={cn('px-5 pb-[22px]', borderTop && 'border-border border-t pt-[18px]')}>
      <div className="text-muted-foreground text-[10px] tracking-wider uppercase">{label}</div>
      <div className="text-foreground mt-1.5 font-serif text-5xl leading-none font-normal -tracking-[2px]">
        {value}
      </div>
      {sublabel && <div className="text-muted-foreground mt-1 text-xs">{sublabel}</div>}
      {trend && (
        <div
          className={cn(
            'mt-2 inline-flex items-center gap-1.5 rounded-[10px] px-2.5 py-1 text-[11px] font-medium',
            TREND_CLASS[trend.color],
          )}
        >
          <Icon name={trend.icon} size={12} />
          {trend.text}
        </div>
      )}
    </div>
  );
}

export function SchemaChip({ label }: { label: string }) {
  return (
    <Badge variant="outline" className="text-muted-foreground font-mono text-[9px] tracking-wide">
      {label}
    </Badge>
  );
}

interface IconButtonProps {
  icon: string;
  onClick?: () => void;
  'aria-label'?: string;
  variant?: 'default' | 'ghost' | 'primary';
  disabled?: boolean;
}

export function IconButton({
  icon,
  onClick,
  'aria-label': ariaLabel,
  variant = 'default',
  disabled = false,
}: IconButtonProps) {
  const mapped = variant === 'primary' ? 'default' : variant === 'ghost' ? 'ghost' : 'outline';
  return (
    <Button
      variant={mapped}
      size="icon"
      className="rounded-full"
      aria-label={ariaLabel}
      onClick={onClick}
      disabled={disabled}
    >
      <Icon name={icon} size={16} />
    </Button>
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
      {header}
      {contentPadding !== undefined ? <div style={{ padding: contentPadding }}>{children}</div> : children}
    </>
  );
}
