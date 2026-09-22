'use client';

import { useState } from 'react';
import { Laptop, Plus } from 'lucide-react';
import { useI18n } from '@/contexts/I18nContext';
import { AddPeerPanel } from '@/components/devices/AddPeerPanel';
import { useChatContext } from '@/contexts/ChatContext';
import { DeviceGlyph } from '@/components/devices/DeviceGlyph';
import { deviceDisplayName } from '@/lib/deviceDisplayName';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';

export function WelcomePanel() {
  const { t, localeTag } = useI18n(); const zh = localeTag === 'zh_CN';
  const { otherDevices, setSelectedDeviceId } = useChatContext();
  const [open, setOpen] = useState(false);
  return <div className="flex min-h-0 flex-1 overflow-y-auto px-8 py-14 lg:px-14">
    <div className="mx-auto w-full max-w-xl">
      <div className="flex items-center gap-4"><Laptop size={38} strokeWidth={1.4}/><div><h1 className="text-2xl font-semibold tracking-tight">{zh ? '把文件传到另一台设备' : 'Send to another device'}</h1><p className="mt-2 text-sm leading-6 text-muted-foreground">{t('conversation.welcomeHint')}</p></div></div>
      <div className="mt-10 space-y-3">{otherDevices.slice(0, 4).map(device => <div key={device.deviceId} className="flex items-center gap-4 rounded-xl border border-border p-4"><DeviceGlyph name={device.name} platform={device.platform} className="size-8"/><p className="min-w-0 flex-1 truncate text-sm font-medium">{deviceDisplayName(device)}</p><Button variant="outline" onClick={() => setSelectedDeviceId(device.deviceId)}>{zh ? '打开' : 'Open'}</Button></div>)}</div>
      <div className="mt-8 border-t border-border pt-8 text-center"><Button onClick={() => setOpen(true)} className="gap-2"><Plus className="size-4" />{t('conversation.connectDevice')}</Button><p className="mt-4 text-xs leading-6 text-muted-foreground">{zh ? '连接码和扫码都可以连接。设备只需连接一次。' : 'Connect with a code or QR. Pair each device once.'}</p></div>
    </div>
    <Dialog open={open} onOpenChange={setOpen}><DialogContent className="sm:max-w-sm"><DialogHeader><DialogTitle>{t('conversation.connectDevice')}</DialogTitle></DialogHeader><AddPeerPanel onAdded={() => setOpen(false)} /></DialogContent></Dialog>
  </div>;
}
