'use client';

import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { receiveDirectoryLabel } from '@/lib/receiveFiles';
import { useConversationDraft } from './ConversationDrafts';
import { useChatContext } from '@/contexts/ChatContext';
import { useI18n } from '@/contexts/I18nContext';
import { useSendShortcutMode } from '@/hooks/useSendShortcutMode';
import { isMacPlatform } from '@/lib/shortcutPreferences';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { extractClipboardFiles } from '@/lib/clipboardFiles';
import { FolderDown, ImagePlus, Paperclip, Send } from 'lucide-react';
import { PendingFilesBar } from './PendingFilesBar';

export function MessageInput() {
  const { t, localeTag } = useI18n(); const zh = localeTag === 'zh_CN';
  const [folder, setFolder] = useState<string | null>(null);
  useEffect(() => { const sync = () => setFolder(receiveDirectoryLabel()); sync(); window.addEventListener('shrimpsend:receive-folder', sync); return () => window.removeEventListener('shrimpsend:receive-folder', sync); }, []);
  const { sendTextMessage, sending, handleFileSelect, addPendingFiles, selectedDeviceId, pendingFiles, handleSendFiles } = useChatContext();
  const [input, setInput] = useConversationDraft(selectedDeviceId);
  const [sendShortcutMode] = useSendShortcutMode();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const imageInputRef = useRef<HTMLInputElement>(null);
  const submitting = useRef(false);
  const sendTooltip = sendShortcutMode === 'enter' ? t('chat.input.sendEnter')
    : isMacPlatform() ? t('chat.input.sendModifierEnterMac') : t('chat.input.sendModifierEnter');
  const disabled = !selectedDeviceId;
  const canSend = !disabled && !sending && (!!input.trim() || pendingFiles.length > 0);
  const handleSend = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!canSend || submitting.current) return;
    submitting.current = true;
    const text = input.trim();
    try {
      if (pendingFiles.length) handleSendFiles();
      if (text) { setInput(''); await sendTextMessage(text); }
    } finally { submitting.current = false; }
  };
  return (
    <form onSubmit={handleSend} className="mx-auto w-full max-w-[1024px] shrink-0 bg-card px-4 pb-3 pt-2 sm:px-8 sm:pb-5 sm:pt-3">
      <div className={cn('overflow-hidden rounded-xl border border-input bg-card transition-colors focus-within:border-primary/60 focus-within:ring-2 focus-within:ring-primary/10', disabled && 'opacity-50')}>
        <PendingFilesBar />
        <input type="file" ref={fileInputRef} onChange={handleFileSelect} className="hidden" multiple aria-label={t('chat.input.pickFile')} />
        <input type="file" ref={imageInputRef} onChange={handleFileSelect} className="hidden" accept="image/*" multiple aria-label={zh ? '选择图片' : 'Choose images'} />
        <textarea value={input} onChange={e => setInput(e.target.value)}
          onPaste={e => {
            if (disabled) return;
            const files = extractClipboardFiles(e.clipboardData);
            if (!files.length) return;
            e.preventDefault(); addPendingFiles(files);
          }}
          onKeyDown={e => {
            if (e.key !== 'Enter' || e.nativeEvent.isComposing) return;
            if (sendShortcutMode === 'enter' ? !e.shiftKey : e.ctrlKey || e.metaKey) {
              e.preventDefault(); void handleSend(e);
            }
          }}
          aria-label={t('conversation.composer')} placeholder={disabled ? t('chat.header.pickDeviceHint') : t('conversation.composer')}
          disabled={disabled} rows={1}
          className="block max-h-40 min-h-[60px] w-full resize-none border-0 bg-transparent px-4 pb-2 pt-4 text-sm leading-6 outline-none placeholder:text-muted-foreground"
          style={{ fieldSizing: 'content' } as React.CSSProperties} />
        <div className="flex items-center justify-between gap-3 px-3 pb-3 sm:px-4">
          <div className="flex gap-1"><Button type="button" variant="ghost" size="sm" disabled={disabled} onClick={() => fileInputRef.current?.click()} title={t('chat.input.pickFile')} className="gap-2 px-1.5 text-sm text-muted-foreground">
            <Paperclip className="size-5" strokeWidth={1.7} />{t('conversation.file')}
          </Button>
          <Button type="button" variant="ghost" size="icon" disabled={disabled} onClick={() => imageInputRef.current?.click()} aria-label={zh ? '添加图片' : 'Add images'} className="text-muted-foreground"><ImagePlus size={18}/></Button></div>
          <Button type="submit" disabled={!canSend} title={sendTooltip} className="h-9 gap-2 text-sm rounded-lg px-4 shadow-none">
            <Send className="size-4" />{t('chat.send')}
          </Button>
        </div>
      </div>
      <div className="mt-2 flex flex-wrap items-center justify-between gap-2 text-[11px] text-muted-foreground"><Link href="/settings/receiving" className="inline-flex items-center gap-1 hover:text-primary"><FolderDown size={13}/>{zh ? '接收保存至' : 'Save received files to'} {folder ?? (zh ? '下载目录' : 'Downloads')}</Link><span className="hidden sm:inline">{sendTooltip}{sendShortcutMode === 'enter' && ` · ${t('conversation.newline')}`}</span></div>
    </form>
  );
}
