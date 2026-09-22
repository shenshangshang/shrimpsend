'use client';

import { deviceDisplayName } from '@/lib/deviceDisplayName';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useChatContext, S3_VIRTUAL_DEVICE_ID } from '@/contexts/ChatContext';
import { useI18n } from '@/contexts/I18nContext';
import { DeviceGlyph } from '@/components/devices/DeviceGlyph';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';
import { unpairDevice } from '@/lib/api/devices';
import { setGuestPeerAlias, loadGuestPeers, removeGuestPeer } from '@/lib/guestPeers';
import { setDeviceName } from '@/lib/deviceId';
import { logger } from '@/lib/logger';
import { toast } from 'sonner';
import { ArrowLeft, Search, Activity, Cloud, MessageSquareX, Settings, Ellipsis, Trash2 } from 'lucide-react';
import type { ReachStatus } from '@/hooks/useSendTargetProbes';
import { getReachDisplayStatus } from '@/hooks/useSendTargetProbes';

const TAG = 'chat-header';

export function ChatHeader({
  onBack,
  showBackButton,
}: {
  onBack?: () => void;
  showBackButton?: boolean;
}) {
  const router = useRouter();
  const { t, localeBcp47 } = useI18n();
  const zh = localeBcp47.startsWith('zh');
  const [confirmation, setConfirmation] = useState<'clear' | 'remove' | null>(null);
  const [sessionSettingsOpen, setSessionSettingsOpen] = useState(false);
  const [renameValue, setRenameValue] = useState('');
  const [renameSaving, setRenameSaving] = useState(false);
  const [clearingMessages, setClearingMessages] = useState(false);

  const {
    devices,
    runSessionConnectionDiagnostic,
    selectedDeviceId,
    deviceReach,
    selectMode,
    selectedKeys,
    exitSelectMode,
    toggleSelectAllMessages,
    handleBulkDelete,
    clearCurrentThreadMessages,
    messages,
    s3Configured,
    s3Online,
    s3Checking,
    currentDeviceId,
    refreshDevices,
    setSelectedDeviceId,
  } = useChatContext();

  const isS3 = selectedDeviceId === S3_VIRTUAL_DEVICE_ID;
  const device = isS3 ? null : devices.find((d) => d.deviceId === selectedDeviceId);

  useEffect(() => {
    if (sessionSettingsOpen && selectedDeviceId) {
      setRenameValue(loadGuestPeers().find(d => d.deviceId === selectedDeviceId)?.alias ?? '');
    }
  }, [sessionSettingsOpen, selectedDeviceId]);

  const handleSessionDeviceRename = async () => {
    if (!selectedDeviceId || renameSaving) return;
    const normalized = renameValue.trim();
    if (normalized.length > 80 || /[\u0000-\u001f\u007f-\u009f]/.test(normalized)) return;
    setRenameSaving(true);
    try {
      setGuestPeerAlias({deviceId:selectedDeviceId,name:device?.name ?? selectedDeviceId,platform:device?.platform}, normalized);
      if (selectedDeviceId === currentDeviceId) {
        setDeviceName(normalized);
      }
      refreshDevices();
      toast.success(t('common.saved'));
    } catch (e) {
      logger.warn(TAG, 'session device rename failed', e);
      toast.error(t('devices.saveFailed'));
    } finally {
      setRenameSaving(false);
    }
  };

  const handleSessionClearMessages = async () => {
    if (clearingMessages) return;

    setClearingMessages(true);
    try {
      await clearCurrentThreadMessages();
      setConfirmation(null);
      toast.success(t('chat.header.sessionClearMessagesDone'));
    } catch (e) {
      logger.warn(TAG, 'session clear messages failed', e);
      toast.error(t('chat.header.sessionClearMessagesFailed'));
    } finally {
      setClearingMessages(false);
    }
  };

  const handleSessionDeviceRemove = async () => {
    if (!selectedDeviceId) return;

    try {
      await unpairDevice(selectedDeviceId);
      removeGuestPeer(selectedDeviceId);
      setSessionSettingsOpen(false);
      setConfirmation(null);
      refreshDevices();
      setSelectedDeviceId(null);
      toast.success(t('devices.removed'));
    } catch (e) {
      logger.warn(TAG, 'session device remove failed', e);
      toast.error(t('chat.header.operationFailed'));
    }
  };

  if (selectMode) {
    const allKeys = messages
      .map((m) => {
        if (m.id != null) return `id:${m.id}`;
        if (m._localId) return `local:${m._localId}`;
        return null;
      })
      .filter(Boolean) as string[];
    const allSelected = allKeys.length > 0 && allKeys.every((k) => selectedKeys.has(k));

    return (
      <div className="flex shrink-0 items-center justify-between gap-3 border-b border-border/70 bg-card px-4 py-4 sm:px-8 sm:py-5">
        <div className="flex items-center gap-1 min-w-0 flex-1">
          <Button variant="ghost" size="icon" className="shrink-0" onClick={exitSelectMode} title={t('chat.header.back')}>
            <ArrowLeft className="size-5" />
          </Button>
          <span className="font-display truncate text-base font-semibold tracking-tight">
            {t('chat.header.selectedCount', { count: selectedKeys.size })}
          </span>
        </div>
        <div className="flex items-center gap-0.5 shrink-0">
          <Button variant="ghost" size="sm" className="text-primary" onClick={toggleSelectAllMessages}>
            {allSelected ? t('chat.header.deselectAll') : t('chat.header.selectAll')}
          </Button>
          <Button
            variant="ghost"
            size="icon"
            className="text-destructive hover:text-destructive"
            disabled={selectedKeys.size === 0}
            title={t('chat.header.delete')}
            onClick={handleBulkDelete}
          >
            <Trash2 className="size-5" />
          </Button>
          <Button variant="ghost" size="sm" onClick={exitSelectMode}>
            {t('chat.header.cancel')}
          </Button>
        </div>
      </div>
    );
  }

  const reachStatus: ReachStatus = (() => {
    if (!selectedDeviceId) return 'offline';
    return getReachDisplayStatus(deviceReach[selectedDeviceId]);
  })();

  const s3DotClass = s3Checking
    ? 'bg-amber-400'
    : !s3Configured
      ? 'bg-muted-foreground/40'
      : s3Online
        ? 'bg-emerald-500'
        : 'bg-amber-400';

  const s3Subtitle = s3Checking
    ? t('deviceList.s3Checking')
    : !s3Configured
      ? t('deviceList.s3NotConfigured')
      : s3Online
        ? t('deviceList.s3OnlineAll')
        : t('deviceList.s3Unavailable');

  const showSessionDeviceSettings =
    !!device && !isS3 && !!selectedDeviceId;

  return (
    <>
      <div className="flex shrink-0 items-center gap-3 border-b border-border/70 bg-card px-4 py-4 sm:px-8 sm:py-5">
        {showBackButton && (
          <Button variant="ghost" size="icon" className="shrink-0" onClick={onBack} title={t('chat.header.backToDeviceList')}>
            <ArrowLeft className="size-5" />
          </Button>
        )}
        {isS3 ? (
          <>
            <div className="flex items-center gap-2.5 min-w-0 flex-1">
              <div className="relative shrink-0">
                <div className="flex size-9 items-center justify-center rounded-lg bg-sky-500/10">
                  <Cloud className="size-5 text-sky-500" />
                </div>
                <span
                  className={cn(
                    'absolute -bottom-0.5 -right-0.5 size-2.5 rounded-full border-2 border-card',
                    s3DotClass,
                  )}
                />
              </div>
              <div className="min-w-0 flex-1">
                <div className="truncate text-sm font-semibold">{t('deviceList.s3RelayTitle')}</div>
                <div className="text-[11px] text-muted-foreground">{s3Subtitle}</div>
              </div>
            </div>
            <Button
              variant="ghost"
              size="icon"
              className="shrink-0"
              title={t('chat.header.s3SettingsTitle')}
              onClick={() => router.push('/settings/s3')}
            >
              <Settings className="size-5" />
            </Button>
          </>
        ) : device ? (
          <>
            <div className="flex min-w-0 flex-1 items-center gap-4">
              <DeviceGlyph platform={device.platform} name={deviceDisplayName(device)} className="size-8 shrink-0 sm:size-9" />
              <div className="min-w-0 flex-1">
                <h1 className="truncate text-lg font-semibold sm:text-lg">{deviceDisplayName(device)}</h1>
                <p className="mt-1 flex items-center gap-1.5 text-sm text-muted-foreground">
                  <span className={cn('size-1.5 rounded-full', reachStatus === 'online' ? 'bg-primary' : reachStatus === 'checking' ? 'bg-amber-500' : 'bg-muted-foreground/50')} />
                  {reachStatus === 'online' ? t('conversation.available') : reachStatus === 'checking' ? t('chat.header.checking') : t('chat.header.offline')}
                </p>
              </div>
            </div>
            <Button variant="ghost" size="icon" aria-label={zh ? '搜索会话' : 'Search conversation'} onClick={() => router.push(`/search?device=${encodeURIComponent(selectedDeviceId || '')}`)}><Search className="size-4"/></Button>
            <Button variant="ghost" size="icon" aria-label={zh ? '检查连接' : 'Check connection'} onClick={() => void runSessionConnectionDiagnostic(selectedDeviceId!)}><Activity className="size-4"/></Button>
            {showSessionDeviceSettings && <Button variant="ghost" size="icon" className="shrink-0" aria-label={t('chat.header.sessionSettingsTitle')} title={t('chat.header.sessionSettingsTitle')} onClick={() => setSessionSettingsOpen(true)}><Ellipsis className="size-5" /></Button>}
          </>
        ) : (
          <div className="flex-1 text-sm text-muted-foreground">{t('chat.header.pickDeviceHint')}</div>
        )}
      </div>

      <Dialog open={confirmation !== null} onOpenChange={open => { if (!open) setConfirmation(null); }}><DialogContent className="max-w-sm"><DialogHeader><DialogTitle>{confirmation === 'clear' ? t('chat.header.sessionClearMessages') : t('chat.header.removeDevice')}</DialogTitle></DialogHeader><p className="text-sm leading-6 text-muted-foreground">{confirmation === 'clear' ? t('chat.header.sessionClearMessagesConfirm') : t('chat.header.peerRemoveConfirm')}</p><div className="flex justify-end gap-2"><Button variant="outline" onClick={() => setConfirmation(null)}>{t('common.cancel')}</Button><Button variant="destructive" disabled={clearingMessages} onClick={() => void (confirmation === 'clear' ? handleSessionClearMessages() : handleSessionDeviceRemove())}>{zh ? '确认' : 'Confirm'}</Button></div></DialogContent></Dialog>
      <Dialog open={sessionSettingsOpen} onOpenChange={setSessionSettingsOpen}>
        <DialogContent showCloseButton className="max-w-sm gap-0 overflow-hidden p-0">
          <div className="border-b border-border/50 px-5 pb-3 pt-4 pr-12">
            <DialogHeader className="gap-0">
              <DialogTitle>{t('chat.header.sessionSettingsTitle')}</DialogTitle>
            </DialogHeader>
          </div>
          <div className="space-y-4 px-5 pb-5 pt-3">
            <div className="space-y-2">
              <label className="text-xs font-medium text-muted-foreground" htmlFor="session-device-name">
                {zh ? '设备备注（仅本机可见）' : 'Device nickname (only on this device)'}
              </label>
              <div className="flex gap-2">
                <Input
                  id="session-device-name"
                  maxLength={80}
                  placeholder={zh ? '留空使用设备名称' : 'Leave blank to use device name'}
                  value={renameValue}
                  onChange={(e) => setRenameValue(e.target.value)}
                  disabled={renameSaving}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') void handleSessionDeviceRename();
                  }}
                />
                <Button
                  type="button"
                  variant="secondary"
                  className="shrink-0"
                  disabled={renameSaving}
                  onClick={() => void handleSessionDeviceRename()}
                >
                  {t('common.save')}
                </Button>
              </div>
            </div>
            <Button
              variant="outline"
              className="w-full"
              disabled={clearingMessages}
              onClick={() => setConfirmation('clear')}
            >
              <MessageSquareX className="size-4" />
              {t('chat.header.sessionClearMessages')}
            </Button>
            <div className="space-y-2 border-t border-border/50 pt-3">
              <p className="text-sm text-muted-foreground leading-relaxed">
                {selectedDeviceId === currentDeviceId
                  ? t('chat.header.sessionRemoveSelfHint')
                  : t('chat.header.sessionRemoveOtherHint')}
              </p>
              <Button
                variant="destructive"
                className="w-full"
                onClick={() => setConfirmation('remove')}
              >
                {selectedDeviceId === currentDeviceId ? t('chat.header.deleteThisDevice') : t('chat.header.removeDevice')}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}
