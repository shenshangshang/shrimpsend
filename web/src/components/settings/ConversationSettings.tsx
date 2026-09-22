'use client';

import { useState } from 'react';
import { BookOpen, ChevronRight, Download, FolderDown, Monitor, Moon, Settings, ShieldCheck, Sun, User } from 'lucide-react';
import { useI18n } from '@/contexts/I18nContext';
import { useTheme } from '@/contexts/ThemeContext';
import { useAuth } from '@/contexts/AuthContext';
import { useChatContext } from '@/contexts/ChatContext';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { ReceiveFolder } from './receive-folder';
import { openInNewTab } from '@/lib/openInNewTab';
import { openClientReleaseDownload } from '@/lib/clientReleaseDownload';
import { localizedDocsHref, localeTagToPath } from '@/lib/i18nRouting';

export function ConversationSettings({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  const { t, localeTag } = useI18n();
  const { theme, setTheme } = useTheme();
  const { accessToken } = useAuth();
  const { refreshSendTargets, targetsProbing } = useChatContext();
  const [showReceive, setShowReceive] = useState(false);
  const rows = [
    { icon: FolderDown, label: t('receive.folder'), action: () => setShowReceive(v => !v) },
    { icon: ShieldCheck, label: t('deviceLicense.entry'), action: () => openInNewTab('/authorize') },
    { icon: User, label: t('conversation.membership'), action: () => openInNewTab(accessToken ? '/settings/membership' : '/login?next=/settings/membership') },
    { icon: Settings, label: t('conversation.allSettings'), action: () => openInNewTab('/settings') },
  ];
  return <Dialog open={open} onOpenChange={onOpenChange}>
    <DialogContent className="max-h-[85dvh] overflow-y-auto sm:max-w-md">
      <DialogHeader><DialogTitle>{t('settings.title')}</DialogTitle></DialogHeader>
      <div className="flex items-center justify-between gap-3 border-b border-border pb-4">
        <span className="text-sm">{t('settings.navAppearance')}</span>
        <div className="flex gap-1" role="group" aria-label={t('settings.navAppearance')}>
          {([{ value: 'light', icon: Sun, label: t('conversation.light') }, { value: 'dark', icon: Moon, label: t('conversation.dark') }, { value: 'system', icon: Monitor, label: t('conversation.system') }] as const).map(item =>
            <Button key={item.value} variant={theme === item.value ? 'secondary' : 'ghost'} size="icon" aria-label={item.label} title={item.label} aria-pressed={theme === item.value} onClick={() => setTheme(item.value)}><item.icon className="size-4" /></Button>)}
        </div>
      </div>
      <div>
        {rows.map(({ icon: Icon, label, action }, i) => <div key={label}>
          <button type="button" onClick={action} className="flex w-full items-center gap-3 rounded-lg px-2 py-3.5 text-left text-sm hover:bg-muted">
            <Icon className="size-4 text-muted-foreground" /><span className="flex-1">{label}</span><ChevronRight className="size-4 text-muted-foreground" />
          </button>
          {i === 0 && showReceive && <div className="rounded-lg bg-muted/50 p-4"><ReceiveFolder /></div>}
        </div>)}
      </div>
      <div className="flex flex-wrap gap-2 border-t border-border pt-3">
        <Button variant="ghost" size="sm" onClick={() => openClientReleaseDownload()}><Download className="size-4" />{t('deviceList.downloadTitle')}</Button>
        <Button variant="ghost" size="sm" onClick={() => openInNewTab(localizedDocsHref(localeTagToPath(localeTag), 'intro'))}><BookOpen className="size-4" />{t('deviceList.docsTitle')}</Button>
        <Button variant="ghost" size="sm" onClick={refreshSendTargets} disabled={targetsProbing}>{t('deviceList.refreshReachTitle')}</Button>
      </div>
    </DialogContent>
  </Dialog>;
}
