'use client';

import { deviceDisplayName } from '@/lib/deviceDisplayName';

import type { DeviceDto } from '@/lib/api';
import type { ReachStatus } from '@/hooks/useSendTargetProbes';
import { cn } from '@/lib/utils';
import { useI18n } from '@/contexts/I18nContext';
import { DeviceGlyph } from './DeviceGlyph';

export function DeviceConversationItem({ device, selected, reachStatus, onClick }: {
  device: DeviceDto;
  isMyDevice?: boolean;
  selected: boolean;
  reachStatus: ReachStatus;
  lastMessage?: string;
  onClick: () => void;
}) {
  const { t } = useI18n();
  const online = reachStatus === 'online';
  const checking = reachStatus === 'checking';
  return (
    <button type="button" onClick={onClick} aria-pressed={selected}
      className={cn('flex min-h-[72px] w-full items-center gap-3 rounded-lg px-3 py-3 text-left transition-colors focus-visible:outline-2 focus-visible:outline-ring',
        selected ? 'bg-accent-soft' : 'hover:bg-muted')}>
      <DeviceGlyph platform={device.platform} name={deviceDisplayName(device)} className="size-8 shrink-0 text-foreground" />
      <div className="min-w-0 flex-1">
        <p className="truncate text-[15px] font-medium text-foreground">{deviceDisplayName(device)}</p>
        <p className="mt-1 flex items-center gap-1.5 text-xs text-muted-foreground">
          <span className={cn('size-1.5 shrink-0 rounded-full', online ? 'bg-primary' : checking ? 'bg-amber-500' : 'bg-muted-foreground/50')} />
          {online ? t('conversation.available') : checking ? t('chat.header.checking') : t('chat.header.offline')}
        </p>
      </div>
    </button>
  );
}
