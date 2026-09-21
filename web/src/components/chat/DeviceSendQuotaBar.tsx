'use client';

import { useEffect, useState } from 'react';
import { useI18n } from '@/contexts/I18nContext';
import { cn } from '@/lib/utils';
import { Gauge } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import {
  fetchDeviceQuota,
  quotaRetrySeconds,
  setDeviceSendQuotaListener,
  type DeviceSendQuota,
} from '@/lib/api/deviceSendQuota';

export function DeviceSendQuotaBar() {
  const { t } = useI18n();
  const [quota, setQuota] = useState<DeviceSendQuota | null>(null);
  const [dialogOpen, setDialogOpen] = useState(false);

  useEffect(() => {
    let active = true;
    setDeviceSendQuotaListener((next) => {
      if (!active) return;
      setQuota(next);
      if (next.limited) setDialogOpen(true);
    });
    const refresh = async () => {
      try {
        const next = await fetchDeviceQuota();
        if (active && next) setQuota(next);
      } catch {
        // Keep the last known quota while offline; sends remain server-validated.
      }
    };
    void refresh();
    window.addEventListener('online', refresh);
    return () => {
      active = false;
      window.removeEventListener('online', refresh);
      setDeviceSendQuotaListener(null);
    };
  }, []);


  const limited = !!quota?.limited || (quota?.message.remaining ?? 1) <= 0 || (quota?.signaling.remaining ?? 1) <= 0;
  const nearLimit = !!quota && (quota.message.used >= quota.message.limit * 0.8 || quota.signaling.used >= quota.signaling.limit * 0.8);
  if (!limited && !nearLimit && !dialogOpen) return null;
  const seconds = quota ? quotaRetrySeconds(quota) : 1;
  const dialogBody = (() => {
    if (limited && quota?.kind === 'signaling') {
      return t('chat.quota.signalingBody', {
        used: quota.signaling.used,
        limit: quota.signaling.limit,
        seconds,
      });
    }
    if (limited && (quota?.kind === 'message' || (quota?.message.remaining ?? 1) <= 0)) {
      return t('chat.quota.messageBody', {
        used: quota?.message.used ?? 90,
        limit: quota?.message.limit ?? 90,
        seconds,
      });
    }
    return t('chat.quota.infoBody', {
      messageUsed: quota?.message.used ?? 0,
      messageLimit: quota?.message.limit ?? 90,
      signalingUsed: quota?.signaling.used ?? 0,
      signalingLimit: quota?.signaling.limit ?? 600,
    });
  })();

  return (
    <>
      <button
        type="button"
        onClick={() => setDialogOpen(true)}
        className={cn(
          'flex w-full items-center gap-1.5 border-b border-border/50 px-3 py-1 text-left text-[11px]',
          limited ? 'bg-amber-500/10 text-amber-800 dark:text-amber-300' : 'bg-muted/40 text-muted-foreground',
        )}
      >
        <Gauge className="size-3.5 shrink-0" />
        <span className="min-w-0 truncate">
          {t('chat.quota.hint')} · {t('chat.quota.message', { used: quota?.message.used ?? 0, limit: quota?.message.limit ?? 90 })} · {t('chat.quota.signaling', { used: quota?.signaling.used ?? 0, limit: quota?.signaling.limit ?? 600 })}
        </span>
      </button>
      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{limited ? t('chat.quota.title') : t('chat.quota.hint')}</DialogTitle>
            <DialogDescription>{dialogBody}</DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button type="button" onClick={() => setDialogOpen(false)}>
              {t('chat.quota.gotIt')}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
