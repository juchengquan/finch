'use client';

import { useState } from 'react';
import { useTranslations } from 'next-intl';
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
  editLabel,
  deleteLabel,
  confirmTitle,
  confirmDescription,
  confirmLabel,
  triggerLabel,
  align = 'end',
  className,
}: RowActionsProps) {
  const [confirmOpen, setConfirmOpen] = useState(false);
  const tCommon = useTranslations('common');
  const resolvedEdit = editLabel ?? tCommon('edit');
  const resolvedDelete = deleteLabel ?? tCommon('delete');
  const resolvedConfirm = confirmLabel ?? tCommon('delete');
  const resolvedTrigger = triggerLabel ?? tCommon('moreActions');
  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button
            variant="ghost"
            size="icon"
            className={className ?? 'text-muted-foreground size-8 shrink-0 rounded-full'}
            aria-label={resolvedTrigger}
            onClick={(e) => { e.stopPropagation(); e.preventDefault(); }}
          >
            <Icon name="dots" size={16} />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align={align}>
          {onEdit && (
            <DropdownMenuItem onSelect={() => onEdit()}>
              <Icon name="edit" size={14} />{resolvedEdit}
            </DropdownMenuItem>
          )}
          {onDelete && (
            <DropdownMenuItem variant="destructive" onSelect={() => setConfirmOpen(true)}>
              <Icon name="trash" size={14} />{resolvedDelete}
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
              <Button variant="outline">{tCommon('cancel')}</Button>
            </DialogClose>
            <Button variant="destructive" onClick={() => { onDelete?.(); setConfirmOpen(false); }}>
              {resolvedConfirm}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
