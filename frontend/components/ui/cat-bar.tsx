// frontend/components/ui/cat-bar.tsx — extracted from
// primitives.tsx:267 (was 9 lines; PR 4). A vertical
// category-coloured accent bar, used as the leading element of
// transaction rows.
import { cn } from '@/lib/utils';

const FALLBACK_CAT_COLOR = '#9ca3af';

export function CatBar({ color, className }: { color: string | null | undefined; className?: string }) {
  return (
    <span
      aria-hidden
      className={cn('w-1 shrink-0 self-stretch rounded-full', className)}
      style={{ background: color || FALLBACK_CAT_COLOR }}
    />
  );
}
