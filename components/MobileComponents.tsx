'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useTranslations } from 'next-intl';
import { ChevL, Filter, Plus } from '@/components/icons';
import { SearchButton } from './command-palette';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';

const ICON_FOR: Record<string, typeof Plus> = {
  plus: Plus,
  filter: Filter,
};

export function ProfileChip({ className }: { className?: string }) {
  const tNav = useTranslations('nav');
  return (
    <Link
      href="/settings"
      aria-label={tNav('settings')}
      className={cn(
        'bg-primary text-primary-foreground flex size-9 items-center justify-center rounded-full font-serif text-base italic',
        className,
      )}
    >
      A
    </Link>
  );
}

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
  // trend.icon is a string from PageHeader callers; today no caller passes
  // a trend, so the chip below is dead. Keep the resolution here for the
  // next time trend is wired up.
  const TrendIcon = trend ? ICON_FOR[trend.icon] ?? Plus : null;
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
          {TrendIcon && <TrendIcon size={12} />}
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
  const Glyph = ICON_FOR[icon] ?? Plus;
  return (
    <Button
      variant={mapped}
      size="icon"
      className="rounded-full"
      aria-label={ariaLabel}
      onClick={onClick}
      disabled={disabled}
    >
      <Glyph size={16} />
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
