'use client';

import { useEffect, useState } from 'react';
import { FolderDown } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { useI18n } from '@/contexts/I18nContext';
import { canChooseReceiveDirectory, chooseReceiveDirectory, receiveDirectoryLabel, resetReceiveDirectory } from '@/lib/receiveFiles';

export function ReceiveFolder() {
  const { t } = useI18n();
  const [folder, setFolder] = useState<string | null>(null);
  const [supported, setSupported] = useState(false);
  useEffect(() => { queueMicrotask(() => { setFolder(receiveDirectoryLabel()); setSupported(canChooseReceiveDirectory()); }); }, []);
  return (
    <div className="rounded-xl border border-border bg-card p-4">
      <div className="flex items-center gap-2 text-sm font-medium"><FolderDown className="size-4 text-primary" />{t('receive.folder')}</div>
      <p className="mt-2 break-all text-sm text-muted-foreground">{folder ?? t('receive.default')}</p>
      <p className="mt-1 text-xs leading-5 text-muted-foreground">{supported ? t('receive.hint') : t('receive.browserHint')}</p>
      {supported && <div className="mt-3 flex gap-2">
        <Button size="sm" variant="outline" onClick={async () => {
          try { setFolder(await chooseReceiveDirectory()); }
          catch (e) { if (!(e instanceof DOMException && e.name === 'AbortError')) toast.error(String(e)); }
        }}>{t('receive.choose')}</Button>
        {folder && <Button size="sm" variant="ghost" onClick={async () => { await resetReceiveDirectory(); setFolder(null); }}>{t('receive.reset')}</Button>}
      </div>}
    </div>
  );
}
