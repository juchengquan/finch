'use client';

import { useState } from 'react';
import { Icon } from '@/components/primitives';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
} from '@/components/ui/dropdown-menu';
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';

interface RowActionsProps {
  onEdit?: () => void;
  onDelete?: () => void;
  editLabel?: string;
  deleteLabel?: string;
  confirmTitle: string;
  confirmDescription?: string;
  confirmLabel?: string;
  /** Accessible label for the trigger button. */
  triggerLabel?: string;
  align?: 'start' | 'end';
  className?: string;
}

/**
 * A trailing "⋯" menu with optional Edit / Delete items. Delete opens a built-in
 * confirm dialog so callers only supply the action and copy. `stopPropagation`
 * on the trigger keeps it safe inside clickable rows.
 */
export function RowActions({
  onEdit,
  onDelete,
  editLabel = 'Edit',
  deleteLabel = 'Delete',
  confirmTitle,
  confirmDescription,
  confirmLabel = 'Delete',
  triggerLabel = 'More actions',
  align = 'end',
  className,
}: RowActionsProps) {
  const [confirmOpen, setConfirmOpen] = useState(false);
  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button
            variant="ghost"
            size="icon"
            className={className ?? 'text-muted-foreground size-8 shrink-0 rounded-full'}
            aria-label={triggerLabel}
            onClick={(e) => { e.stopPropagation(); e.preventDefault(); }}
          >
            <Icon name="dots" size={16} />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align={align}>
          {onEdit && (
            <DropdownMenuItem onSelect={() => onEdit()}>
              <Icon name="edit" size={14} />{editLabel}
            </DropdownMenuItem>
          )}
          {onDelete && (
            <DropdownMenuItem variant="destructive" onSelect={() => setConfirmOpen(true)}>
              <Icon name="trash" size={14} />{deleteLabel}
            </DropdownMenuItem>
          )}
        </DropdownMenuContent>
      </DropdownMenu>

      <Dialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{confirmTitle}</DialogTitle>
            {confirmDescription && <DialogDescription>{confirmDescription}</DialogDescription>}
          </DialogHeader>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button variant="destructive" onClick={() => { onDelete?.(); setConfirmOpen(false); }}>
              {confirmLabel}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
