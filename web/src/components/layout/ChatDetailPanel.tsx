'use client';

import { useCallback, useRef, useState } from 'react';
import { useChatContext } from '@/contexts/ChatContext';
import { ChatHeader } from '@/components/chat/ChatHeader';
import { MessageList } from '@/components/chat/MessageList';
import { MessageInput } from '@/components/chat/MessageInput';
import { DeviceSendQuotaBar } from '@/components/chat/DeviceSendQuotaBar';
import { ErrorBar } from '@/components/chat/ErrorBar';
import { cn } from '@/lib/utils';
import { WelcomePanel } from './WelcomePanel';
import { useI18n } from '@/contexts/I18nContext';

export function ChatDetailPanel({
  onBack,
  showBackButton,
  className,
}: {
  onBack?: () => void;
  showBackButton?: boolean;
  className?: string;
}) {
  const { t } = useI18n();
  const {
    selectedDeviceId,
    setPendingFiles,
    setFileError,
  } = useChatContext();
  const [isDraggingOver, setIsDraggingOver] = useState(false);
  const dragCounterRef = useRef(0);

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (e.dataTransfer.types.includes('Files')) {
      e.dataTransfer.dropEffect = 'copy';
      setIsDraggingOver(true);
    }
  }, []);

  const handleDragEnter = useCallback((e: React.DragEvent) => {
    if (!e.dataTransfer.types.includes('Files')) return;
    e.preventDefault();
    e.stopPropagation();
    dragCounterRef.current += 1;
    setIsDraggingOver(true);
  }, []);

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    dragCounterRef.current -= 1;
    if (dragCounterRef.current <= 0) {
      setIsDraggingOver(false);
    }
  }, []);

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    dragCounterRef.current = 0;
    setIsDraggingOver(false);
    const files = e.dataTransfer.files;
    if (!files || files.length === 0) return;
    const fileList = Array.from(files);
    setFileError(null);
    setPendingFiles((prev) => [...prev, ...fileList]);
  }, [setFileError, setPendingFiles]);

  return (
    <div
      className={cn('relative flex min-h-0 min-w-0 flex-1 flex-col bg-card', className)}
      onDragEnter={handleDragEnter}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      {selectedDeviceId && <ChatHeader onBack={onBack} showBackButton={showBackButton} />}

      {isDraggingOver && (
        <div className="pointer-events-none absolute inset-0 z-50 m-2 flex items-center justify-center rounded-2xl border-2 border-dashed border-primary/55 bg-card/78 backdrop-blur-sm">
          <p className="font-display text-sm tracking-tight text-muted-foreground">{t('chat.empty.dropHint')}</p>
        </div>
      )}

      {selectedDeviceId ? (
        <>
          <DeviceSendQuotaBar />
          <MessageList />
          <ErrorBar />
          <MessageInput />
        </>
      ) : (
        <WelcomePanel />
      )}
    </div>
  );
}
