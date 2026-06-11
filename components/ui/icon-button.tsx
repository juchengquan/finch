// frontend/components/ui/icon-button.tsx
// Used by the bottom tab
// bar, settings tabs, and sidebar chrome. The component is a thin
// shadcn Button wrapper that takes a typed LucideIcon component.
'use client';

import { Button } from './button';
import type { LucideIcon } from 'lucide-react';

interface IconButtonProps {
  icon: LucideIcon;
  onClick?: () => void;
  'aria-label'?: string;
  variant?: 'default' | 'ghost' | 'primary';
  disabled?: boolean;
}

export function IconButton({
  icon: Icon,
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
      <Icon size={16} />
    </Button>
  );
}
