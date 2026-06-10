// frontend/components/ui/icon-button.tsx — extracted from
// MobileComponents.tsx (was 17 lines; PR 4). Used by the bottom tab
// bar, settings tabs, and sidebar chrome. The component is a thin
// shadcn Button wrapper that takes a stringly-typed icon name
// (resolved through the ICON_FOR map below).
'use client';

import { Button } from './button';
import { Plus, Filter } from '@/components/icons';
import type { LucideIcon } from 'lucide-react';

const ICON_FOR: Record<string, LucideIcon> = {
  plus: Plus,
  filter: Filter,
};

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
