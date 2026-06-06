'use client';

// Receipt-photo UI for the transaction detail sheet. RECEIPT_PHOTOS_PLAN §6.
//
// Two surfaces, exported together because they share the "currently open
// attachment" state:
//
//   - <AttachmentsRow>  — the row in the detail sheet (empty state with an
//     "Attach receipt" button, or a thumbnail strip + add button when
//     attachments exist). File picker uses capture="environment" so mobile
//     taps open the camera directly.
//   - <AttachmentViewer> — full-screen Dialog rendering the file. Images get
//     pinch-zoom via CSS touch-action; PDFs use <embed>. Keyboard ← → cycles
//     through the transaction's attachments; Delete prompts via toast confirm.

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Dialog, DialogContent, DialogTitle } from '@/components/ui/dialog';
import { Icon } from '@/components/primitives';
import { useFinanceStore } from '@/lib/store';
import { attachmentUrl } from '@/lib/api-client';
import { cn } from '@/lib/utils';
import { toast } from 'sonner';

// Mirrors the upload route's allowlist so the picker pre-filters; the
// server still re-validates via magic bytes.
const ACCEPT = 'image/jpeg,image/png,image/webp,image/heic,image/heif,application/pdf';

function fmtBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(0)} KB`;
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
}

export interface AttachmentsRowProps {
  transactionId: string;
}

export function AttachmentsRow({ transactionId }: AttachmentsRowProps) {
  const attachments = useFinanceStore((s) => s.attachments);
  const uploadAttachment = useFinanceStore((s) => s.uploadAttachment);
  const inputRef = useRef<HTMLInputElement | null>(null);
  const [uploading, setUploading] = useState(false);
  const [openId, setOpenId] = useState<string | null>(null);

  const items = useMemo(
    () =>
      attachments
        .filter((a) => a.transactionId === transactionId)
        .sort((a, b) => (a.createdAt < b.createdAt ? -1 : 1)),
    [attachments, transactionId],
  );

  const onPick = useCallback(
    async (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      // Reset so picking the same file twice in a row still fires onChange.
      e.target.value = '';
      if (!file) return;
      setUploading(true);
      try {
        await uploadAttachment(transactionId, file);
        toast.success('Receipt attached');
      } catch (err) {
        const message = err instanceof Error ? err.message : 'Upload failed';
        toast.error(message);
      } finally {
        setUploading(false);
      }
    },
    [transactionId, uploadAttachment],
  );

  return (
    <div className="border-border flex items-center justify-between border-t-[0.5px] py-3 text-[13px]">
      <span className="text-muted-foreground">Receipts</span>
      <div className="flex items-center gap-2">
        {items.length > 0 && (
          <div className="flex items-center gap-1.5 overflow-x-auto">
            {items.map((a) => (
              <button
                key={a.id}
                type="button"
                onClick={() => setOpenId(a.id)}
                aria-label={`Open ${a.originalFilename || 'attachment'}`}
                className={cn(
                  'border-border focus-ring relative size-12 shrink-0 overflow-hidden rounded-[10px] border outline-none',
                  a.kind === 'pdf' && 'bg-muted text-muted-foreground flex items-center justify-center',
                )}
              >
                {a.kind === 'image' ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={attachmentUrl(a.id)}
                    alt={a.originalFilename || 'receipt'}
                    className="size-full object-cover"
                  />
                ) : (
                  <Icon name="doc" size={20} />
                )}
              </button>
            ))}
          </div>
        )}
        <button
          type="button"
          onClick={() => inputRef.current?.click()}
          disabled={uploading}
          aria-label="Attach receipt"
          className={cn(
            'focus-ring inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[12px] font-medium outline-none',
            uploading ? 'bg-secondary text-muted-foreground' : 'bg-secondary text-foreground hover:bg-muted',
          )}
        >
          <Icon name={uploading ? 'sync' : 'paperclip'} size={12} className={uploading ? 'animate-spin' : undefined} />
          {items.length === 0 ? (uploading ? 'Uploading…' : 'Attach') : '+'}
        </button>
        <input
          ref={inputRef}
          type="file"
          accept={ACCEPT}
          capture="environment"
          className="hidden"
          onChange={onPick}
        />
      </div>
      {openId && (
        <AttachmentViewer
          transactionId={transactionId}
          openId={openId}
          onClose={() => setOpenId(null)}
          onSwitch={setOpenId}
        />
      )}
    </div>
  );
}

interface AttachmentViewerProps {
  transactionId: string;
  openId: string;
  onClose: () => void;
  onSwitch: (id: string) => void;
}

function AttachmentViewer({ transactionId, openId, onClose, onSwitch }: AttachmentViewerProps) {
  const attachments = useFinanceStore((s) => s.attachments);
  const removeAttachment = useFinanceStore((s) => s.removeAttachment);

  const items = useMemo(
    () =>
      attachments
        .filter((a) => a.transactionId === transactionId)
        .sort((a, b) => (a.createdAt < b.createdAt ? -1 : 1)),
    [attachments, transactionId],
  );
  const idx = items.findIndex((a) => a.id === openId);
  const cur = idx >= 0 ? items[idx] : null;

  // Keyboard nav between the transaction's attachments.
  useEffect(() => {
    if (!cur) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'ArrowRight' && idx < items.length - 1) onSwitch(items[idx + 1].id);
      else if (e.key === 'ArrowLeft' && idx > 0) onSwitch(items[idx - 1].id);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [cur, idx, items, onSwitch]);

  // If the open attachment was deleted from another surface, close.
  useEffect(() => {
    if (!cur) onClose();
  }, [cur, onClose]);

  if (!cur) return null;

  const onDelete = () => {
    toast('Delete this receipt?', {
      action: {
        label: 'Delete',
        onClick: () => {
          removeAttachment(cur.id);
          toast.success('Receipt deleted');
          onClose();
        },
      },
    });
  };

  return (
    <Dialog open onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="max-h-[95vh] max-w-[95vw] overflow-hidden p-0 sm:max-w-3xl">
        <DialogTitle className="sr-only">
          {cur.originalFilename || `Receipt ${cur.id}`}
        </DialogTitle>
        <div className="flex flex-col">
          <div className="border-border bg-card flex items-center justify-between gap-2 border-b px-4 py-2.5 text-[12px]">
            <div className="min-w-0 flex-1">
              <div className="truncate font-medium">{cur.originalFilename || `Attachment ${cur.id.slice(0, 8)}`}</div>
              <div className="text-muted-foreground">
                {cur.kind === 'pdf' ? 'PDF' : 'Image'} · {fmtBytes(cur.byteSize)}
                {items.length > 1 && ` · ${idx + 1} of ${items.length}`}
              </div>
            </div>
            <a
              href={attachmentUrl(cur.id)}
              download={cur.originalFilename || undefined}
              className="focus-ring inline-flex items-center gap-1 rounded-full px-2 py-1 hover:bg-muted"
              aria-label="Download"
            >
              <Icon name="download" size={14} />
            </a>
            <button
              type="button"
              onClick={onDelete}
              className="focus-ring text-destructive hover:bg-destructive/10 inline-flex items-center gap-1 rounded-full px-2 py-1"
              aria-label="Delete"
            >
              <Icon name="trash" size={14} />
            </button>
          </div>
          <div className="bg-muted/40 flex items-center justify-center" style={{ minHeight: '60vh', touchAction: 'pinch-zoom' }}>
            {cur.kind === 'image' ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={attachmentUrl(cur.id)}
                alt={cur.originalFilename || 'receipt'}
                className="max-h-[80vh] max-w-full object-contain"
              />
            ) : (
              <embed
                src={attachmentUrl(cur.id)}
                type="application/pdf"
                className="h-[80vh] w-full"
              />
            )}
          </div>
          {items.length > 1 && (
            <div className="border-border bg-card flex items-center justify-between border-t px-4 py-2 text-[12px]">
              <button
                type="button"
                onClick={() => idx > 0 && onSwitch(items[idx - 1].id)}
                disabled={idx === 0}
                className="focus-ring inline-flex items-center gap-1 rounded-full px-2 py-1 hover:bg-muted disabled:opacity-30"
                aria-label="Previous"
              >
                <Icon name="chev-l" size={14} />
                Prev
              </button>
              <button
                type="button"
                onClick={() => idx < items.length - 1 && onSwitch(items[idx + 1].id)}
                disabled={idx === items.length - 1}
                className="focus-ring inline-flex items-center gap-1 rounded-full px-2 py-1 hover:bg-muted disabled:opacity-30"
                aria-label="Next"
              >
                Next
                <Icon name="chev" size={14} />
              </button>
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
