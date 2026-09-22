'use client';

import { useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { Copy, Loader2 } from 'lucide-react';
import { toast } from 'sonner';
import { useChatContext } from '@/contexts/ChatContext';
import { useI18n } from '@/contexts/I18nContext';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { devicePairUri } from '@/lib/devicePair';
import { formatUiMessage } from '@/lib/uiMessage';
import { cn } from '@/lib/utils';

export function AddPeerPanel({
  className,
  onAdded,
}: {
  className?: string;
  onAdded?: () => void;
}) {
  const { t } = useI18n();
  const { currentDeviceId, addPeerByDeviceId } = useChatContext();
  const pairUri = devicePairUri(currentDeviceId);
  const [paste, setPaste] = useState('');
  const [busy, setBusy] = useState(false);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(currentDeviceId);
      toast.success(t('deviceList.copiedDeviceId'));
    } catch {
      toast.error(t('deviceList.copyFailed'));
    }
  };

  const handleAdd = async () => {
    const raw = paste.trim();
    if (!raw || busy) return;
    setBusy(true);
    try {
      await addPeerByDeviceId(raw);
      setPaste('');
      toast.success(t('deviceList.peerAdded'));
      onAdded?.();
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'deviceList.pairFailed';
      toast.error(formatUiMessage(msg, t));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className={cn('flex flex-col items-center gap-3', className)}>
      <p className="text-xs leading-relaxed text-muted-foreground text-center">
        {t('deviceList.pairQrHint')}
      </p>
      <div className="rounded-2xl border border-border/80 bg-background p-3 shadow-sm ring-1 ring-foreground/6">
        <QRCodeSVG
          value={pairUri}
          size={168}
          level="M"
          includeMargin
          className="rounded-lg"
        />
      </div>
      <div className="flex w-full items-center gap-1.5">
        <code className="min-w-0 flex-1 truncate rounded-xl border border-border/70 bg-muted/40 px-2.5 py-1.5 font-mono text-[11px] text-muted-foreground">
          {currentDeviceId}
        </code>
        <Button
          type="button"
          variant="outline"
          size="icon-sm"
          onClick={() => void handleCopy()}
          title={t('deviceList.copyDeviceId')}
          aria-label={t('deviceList.copyDeviceId')}
        >
          <Copy className="size-3.5" />
        </Button>
      </div>
      <form
        className="flex w-full gap-1.5"
        onSubmit={(e) => {
          e.preventDefault();
          void handleAdd();
        }}
      >
        <Input
          aria-label={t('deviceList.pasteDeviceIdPlaceholder')}
          value={paste}
          onChange={(e) => setPaste(e.target.value)}
          placeholder={t('deviceList.pasteDeviceIdPlaceholder')}
          autoComplete="off"
          spellCheck={false}
          className="h-8 font-mono text-xs"
        />
        <Button type="submit" size="sm" disabled={busy || !paste.trim()} className="shrink-0">
          {busy ? <Loader2 className="size-3.5 animate-spin" /> : t('deviceList.pasteDeviceIdAction')}
        </Button>
      </form>
    </div>
  );
}
