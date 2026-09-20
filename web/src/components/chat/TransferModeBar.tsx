'use client';

import { useEffect, useMemo, useState } from 'react';
import { useChatContext, S3_VIRTUAL_DEVICE_ID } from '@/contexts/ChatContext';
import { useI18n } from '@/contexts/I18nContext';
import { buildTransferModeOptions } from '@/lib/sendModeResolution';
import {
  resolveTransferModeDotStateFromItem,
  transferModeDotClassName,
  transferModeDotTooltip,
  type TransferModeBarItem,
} from '@/lib/transferModeDot';
import { cn } from '@/lib/utils';
import { isWebPeer } from '@/lib/peerPlatform';
import type { WebSendMode } from '@/lib/sendTargetStorage';
import { Gauge, RefreshCw } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { TransferModeDotLegendButton } from '@/components/chat/TransferModeDotLegend';
import {
  fetchDeviceQuota,
  quotaRetrySeconds,
  setDeviceSendQuotaListener,
  type DeviceSendQuota,
} from '@/lib/api/deviceSendQuota';

function httpTransferAvailable(methods?: {
  directHttp?: boolean;
  pullReachable?: boolean;
  peerHttpHealthy?: boolean;
  lanSignaling?: boolean;
}): boolean {
  return !!(
    methods?.directHttp ||
    methods?.pullReachable ||
    methods?.peerHttpHealthy ||
    methods?.lanSignaling
  );
}

function httpPullOnlyAvailable(methods?: {
  directHttp?: boolean;
  pullReachable?: boolean;
}): boolean {
  return !!(methods?.pullReachable && !methods?.directHttp);
}

export function TransferModeBar() {
  const { t } = useI18n();
  const {
    sendMode,
    onSendModeChange,
    webrtcAvailable,
    selectedDeviceId,
    devices,
    deviceReach,
    runSessionConnectionDiagnostic,
    checkS3Config,
    s3Configured,
    s3Online,
    isGuest,
  } = useChatContext();

  const hidden =
    !selectedDeviceId || selectedDeviceId === S3_VIRTUAL_DEVICE_ID;

  const selectedDevice = selectedDeviceId
    ? devices.find((d) => d.deviceId === selectedDeviceId)
    : undefined;
  const peerIsWeb = isWebPeer(selectedDevice?.platform);

  const entry = selectedDeviceId ? deviceReach[selectedDeviceId] : undefined;
  const sessionProbing = entry?.probing ?? false;
  const methods = entry?.methods;
  const httpAvailable = httpTransferAvailable(methods);
  const httpPullOnly = httpPullOnlyAvailable(methods);
  const s3Available = s3Configured && s3Online;
  const webrtcReachable = methods?.webrtc ?? null;

  const allModes: TransferModeBarItem[] = useMemo(() => {
    if (hidden) return [];
    const options = buildTransferModeOptions({
      peerIsWeb,
      webrtcAvailable,
      httpAvailable,
      webrtcReachable,
      s3Available,
      guest: isGuest,
    });
    const labelFor = (value: WebSendMode): string => {
      switch (value) {
        case 'lan':
          return t('chat.transportMode.httpLan');
        case 'webrtc':
          return peerIsWeb
            ? t('chat.transferBar.webrtc')
            : t('chat.transportMode.webrtcLan');
        case 's3':
          return t('chat.transferBar.s3');
      }
    };
    return options.map((m) => {
      let reachKnownOnline: boolean | null = m.available;
      let reachPullOnly = false;
      switch (m.value) {
        case 'lan':
          reachKnownOnline = httpAvailable;
          reachPullOnly = httpPullOnly;
          break;
        case 'webrtc':
          reachKnownOnline = webrtcReachable;
          break;
        case 's3':
          reachKnownOnline = s3Available;
          break;
      }
      return {
        value: m.value,
        label: labelFor(m.value),
        available: m.available,
        attemptable: m.attemptable,
        reachKnownOnline,
        reachPullOnly,
      };
    });
  }, [
    hidden,
    peerIsWeb,
    webrtcAvailable,
    webrtcReachable,
    httpAvailable,
    httpPullOnly,
    s3Available,
    t,
    isGuest,
  ]);

  if (hidden || allModes.length === 0) {
    if (isGuest) {
      return (
        <div className="flex shrink-0 flex-col">
          <DeviceSendQuotaStrip />
        </div>
      );
    }
    return null;
  }

  const sorted = [...allModes].sort((a, b) => {
    if (a.available === b.available) return 0;
    return a.available ? -1 : 1;
  });

  return (
    <div className="flex shrink-0 flex-col">
      <div className="flex shrink-0 items-center gap-1 border-b border-border/50 bg-card px-3 py-1.5">
        <span className="text-[11px] text-muted-foreground mr-0.5 shrink-0">
          {t('chat.transportMode.label')}
        </span>
        <TransferModeDotLegendButton />
        <div className="flex items-center gap-0.5 flex-1 min-w-0 flex-wrap">
          {sorted.map((m) => {
            const dotState = resolveTransferModeDotStateFromItem(m);
            const tooltip = transferModeDotTooltip(t, m, s3Configured);
            return (
              <button
                key={m.value}
                type="button"
                title={tooltip}
                onClick={() => m.attemptable && onSendModeChange(m.value)}
                disabled={!m.attemptable}
                className={cn(
                  'inline-flex items-center gap-1 rounded-md px-2 py-1 text-[11px] font-medium transition-colors',
                  sendMode === m.value
                    ? 'item-selected-soft text-primary'
                    : m.attemptable
                      ? 'bg-muted/60 text-foreground hover:bg-muted cursor-pointer'
                      : 'bg-muted/30 text-text-tertiary cursor-not-allowed opacity-60',
                )}
              >
                {m.label}
                <span
                  className={cn(
                    'size-1.5 shrink-0 rounded-full',
                    transferModeDotClassName(dotState),
                  )}
                />
              </button>
            );
          })}
        </div>
        <Button
          type="button"
          variant="ghost"
          size="icon-sm"
          className="shrink-0"
          title={t('deviceList.refreshReachTitle')}
          disabled={sessionProbing}
          onClick={() => {
            if (selectedDeviceId && selectedDeviceId !== S3_VIRTUAL_DEVICE_ID) {
              runSessionConnectionDiagnostic(selectedDeviceId);
            } else {
              void checkS3Config();
            }
          }}
        >
          <RefreshCw className={cn('size-3.5', sessionProbing && 'motion-safe:animate-spin')} />
        </Button>
      </div>
      {isGuest ? <DeviceSendQuotaStrip /> : null}
    </div>
  );
}

function DeviceSendQuotaStrip() {
  const { t } = useI18n();
  const [quota, setQuota] = useState<DeviceSendQuota | null>(null);
  const [dialogOpen, setDialogOpen] = useState(false);

  useEffect(() => {
    setDeviceSendQuotaListener((next) => {
      setQuota(next);
      if (next.limited) setDialogOpen(true);
    });
    void fetchDeviceQuota().then((q) => {
      if (q) setQuota(q);
    });
    return () => setDeviceSendQuotaListener(null);
  }, []);

  const limited = !!quota?.limited || (quota?.message.remaining ?? 1) <= 0 || (quota?.signaling.remaining ?? 1) <= 0;
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
