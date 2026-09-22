'use client';

import { useMemo, useState } from 'react';
import { BrandLogo } from '@/components/brand/BrandLogo';
import { useI18n } from '@/contexts/I18nContext';
import { collatorForLocaleTag } from '@/lib/i18nCollator';
import { useChatContext, S3_VIRTUAL_DEVICE_ID } from '@/contexts/ChatContext';
import { DeviceConversationItem } from '@/components/devices/DeviceConversationItem';
import { DeviceGlyph } from '@/components/devices/DeviceGlyph';
import { AddPeerPanel } from '@/components/devices/AddPeerPanel';
import { getReachDisplayStatus, reachSortPriority } from '@/hooks/useSendTargetProbes';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { cn } from '@/lib/utils';
import { getDeviceName } from '@/lib/deviceId';
import { Cloud, Plus, Search, Settings } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { deviceDisplayName } from '@/lib/deviceDisplayName';

export function DeviceListPanel({ onShowSettings, className }: {
  onShowSettings: () => void;
  className?: string;
}) {
  const { t, localeTag } = useI18n();
  const collator = useMemo(() => collatorForLocaleTag(localeTag), [localeTag]);
  const [addOpen, setAddOpen] = useState(false);
  const [query, setQuery] = useState('');
  const { otherDevices, selectedDeviceId, setSelectedDeviceId, deviceReach, s3Configured, s3Online, s3Checking, isGuest, connected } = useChatContext();
  const zh = localeTag === 'zh_CN';
  const sortedDevices = useMemo(() => otherDevices.filter(d => deviceDisplayName(d).toLocaleLowerCase().includes(query.toLocaleLowerCase())).sort((a, b) =>
    reachSortPriority(deviceReach[a.deviceId]) - reachSortPriority(deviceReach[b.deviceId]) || collator.compare(a.name, b.name)),
  [otherDevices, deviceReach, collator, query]);
  return (
    <aside className={cn('flex h-full min-h-0 flex-col bg-muted/65', className)} aria-label={t('deviceList.section')}>
      <div className="flex shrink-0 items-center gap-2 px-5 pt-6 md:hidden">
        <BrandLogo size={28} alt={t('deviceList.logoAlt')} priority />
        <span className="text-lg font-semibold">{t('deviceList.brand')}</span>
      </div>
      <div className="flex items-center justify-between px-5 pb-4 pt-7">
        <h2 className="text-xl font-semibold">{zh ? '传输' : 'Transfers'}</h2>
        <Button variant="ghost" size="sm" className="-mr-2 gap-1.5 px-2 text-muted-foreground" onClick={() => setAddOpen(true)}>
          <Plus className="size-4" />{t('conversation.connect')}
        </Button>
      </div>
      <div className="relative mx-4 mb-5"><Search className="pointer-events-none absolute left-3 top-3 size-4 text-muted-foreground" /><Input aria-label={zh ? '搜索设备' : 'Search devices'} placeholder={zh ? '搜索设备' : 'Search devices'} value={query} onChange={e => setQuery(e.target.value)} className="h-10 bg-card pl-9 shadow-none" /></div>
      <p className="px-5 pb-2 text-xs text-muted-foreground">{zh ? '我的设备' : 'My devices'}</p>
      <div className="min-h-0 flex-1 overflow-y-auto px-2">
        {sortedDevices.length === 0 && (
          <div className="px-5 py-6 text-sm leading-7 text-muted-foreground">{t('conversation.noDevices')}</div>
        )}
        <div className="space-y-1">
          {sortedDevices.map(device => <DeviceConversationItem key={device.deviceId} device={device}
            selected={selectedDeviceId === device.deviceId} reachStatus={getReachDisplayStatus(deviceReach[device.deviceId])}
            onClick={() => setSelectedDeviceId(device.deviceId)} />)}
          {s3Configured && !isGuest && (
            <button type="button" onClick={() => setSelectedDeviceId(S3_VIRTUAL_DEVICE_ID)} aria-pressed={selectedDeviceId === S3_VIRTUAL_DEVICE_ID}
              className={cn('flex min-h-[72px] w-full items-center gap-3 rounded-lg px-3 py-3 text-left', selectedDeviceId === S3_VIRTUAL_DEVICE_ID ? 'bg-accent-soft' : 'hover:bg-muted')}>
              <Cloud className="size-8 shrink-0" strokeWidth={1.6} />
              <div className="min-w-0"><p className="text-[15px] font-medium">{t('deviceList.s3RelayTitle')}</p><p className="mt-1 text-xs text-muted-foreground">{s3Checking ? t('deviceList.s3Checking') : s3Online ? t('conversation.available') : t('deviceList.s3Unavailable')}</p></div>
            </button>
          )}
        </div>
      </div>
      <div className="mx-4 flex min-h-[76px] shrink-0 items-center gap-3 border-t border-border py-4">
        <DeviceGlyph name={getDeviceName()} className="size-6 shrink-0" />
        <div className="min-w-0 flex-1"><p className="truncate text-xs font-medium" title={getDeviceName()}>{getDeviceName()}</p><p className="mt-1 text-[11px] text-muted-foreground">{connected ? (zh ? '在线 · 本机' : 'Online · This device') : (zh ? '本机 · 离线可用' : 'This device · Offline ready')}</p></div>
        <Button variant="ghost" size="icon" className="-mr-2 shrink-0" onClick={onShowSettings} aria-label={t('settings.title')} title={t('settings.title')}><Settings className="size-5" strokeWidth={1.7} /></Button>
      </div>
      <Dialog open={addOpen} onOpenChange={setAddOpen}>
        <DialogContent className="sm:max-w-sm"><DialogHeader><DialogTitle>{t('deviceList.addDeviceTitle')}</DialogTitle></DialogHeader>
          <AddPeerPanel onAdded={() => setAddOpen(false)} />
        </DialogContent>
      </Dialog>
    </aside>
  );
}
