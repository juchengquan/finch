'use client';

import { Icon } from '@/components/primitives';
import { cn } from '@/lib/utils';

interface EmptyStateProps {
  /** One-line label; the only required prop. e.g. "No transactions". */
  title: React.ReactNode;
  /** Secondary explainer beneath the title. */
  description?: React.ReactNode;
  /** Lucide icon name (`primitives.ts` shim); rendered in a tinted chip when set. */
  icon?: string;
  /** Optional CTA at the bottom — pass a Button or a plain Link. */
  action?: React.ReactNode;
  /** Visual variant:
   *  - `card` (default): dashed-bordered rounded card, fits inside a section.
   *  - `inline`: bare centered text, no border — for empty groups inside an
   *    existing card (e.g. an account group with no accounts).
   *  - `page`: full-page empty with extra top padding; for routes that have
   *    no data at all (no accounts, no transactions in a brand-new ledger). */
  variant?: 'card' | 'inline' | 'page';
  /** Vertical padding inside the `card` variant. */
  size?: 'sm' | 'md';
  className?: string;
}

/** Shared empty-state surface. Standardises the dashed-card and bare-centered
 *  patterns scattered across Activity / Accounts / Budgets / Categories /
 *  Transfers / Reports etc. — same copy, same spacing, one component. */
export function EmptyState({
  title,
  description,
  icon,
  action,
  variant = 'card',
  size = 'md',
  className,
}: EmptyStateProps) {
  const inner = (
    <>
      {icon && (
        <div className="bg-secondary text-muted-foreground mx-auto mb-3 flex size-9 items-center justify-center rounded-full">
          <Icon name={icon} size={16} />
        </div>
      )}
      <div className={cn('text-foreground text-sm font-medium', !description && !action && 'text-muted-foreground font-normal')}>
        {title}
      </div>
      {description && <div className="text-muted-foreground mt-1 text-xs">{description}</div>}
      {action && <div className="mt-3 flex justify-center">{action}</div>}
    </>
  );

  if (variant === 'inline') {
    return <div className={cn('text-muted-foreground py-6 text-center text-sm', className)}>{inner}</div>;
  }
  if (variant === 'page') {
    return <div className={cn('px-5 pt-16 text-center', className)}>{inner}</div>;
  }
  return (
    <div
      className={cn(
        'border-border rounded-xl border border-dashed text-center',
        size === 'sm' ? 'py-4' : 'py-10',
        className,
      )}
    >
      {inner}
    </div>
  );
}
