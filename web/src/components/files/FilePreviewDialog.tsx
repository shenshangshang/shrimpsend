'use client';
import { useEffect, useState } from 'react';
import Image from 'next/image';
import { File as FileIcon, Download, Send } from 'lucide-react';
import { useI18n } from '@/contexts/I18nContext';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { downloadBlob } from '@/lib/receiveFiles';
import { formatFileSize } from '@/lib/fileUtils';

export function FilePreviewDialog({file, onClose, onSend}: {file: File | null; onClose: () => void; onSend?: (file: File) => void}) {
  const {localeTag} = useI18n(); const zh = localeTag === 'zh_CN';
  const [resource, setResource] = useState<{file: File; url: string; text?: string; failed?: boolean}>();
  useEffect(() => {
    if (!file) return;
    let alive = true;
    const url = URL.createObjectURL(file);
    void Promise.resolve().then(async () => {
      if (!alive) return;
      setResource({file,url});
      if ((file.type.startsWith('text/') || /\.(txt|md|json|csv|log)$/i.test(file.name)) && file.size <= 2*1024*1024) {
        try { const text = await file.text(); if (alive) setResource({file,url,text}); }
        catch { if (alive) setResource({file,url,failed:true}); }
      }
    });
    return () => {alive = false; URL.revokeObjectURL(url);};
  }, [file]);
  const current = resource?.file === file ? resource : undefined;
  return <Dialog open={!!file} onOpenChange={open => {if (!open) onClose();}}><DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-3xl"><DialogHeader><DialogTitle className="break-all pr-6">{file?.name}</DialogTitle></DialogHeader>{file && <>
    <div className="flex min-h-64 items-center justify-center overflow-hidden rounded-lg bg-muted p-4">
      {!current ? <p role="status" className="text-sm text-muted-foreground">{zh?'正在打开…':'Opening…'}</p> : file.type.startsWith('image/') ? <Image src={current.url} alt={file.name} width={1000} height={800} unoptimized className="max-h-[55dvh] h-auto w-auto object-contain"/> : file.type.startsWith('video/') ? <video src={current.url} controls className="max-h-[55dvh] w-full"/> : file.type.startsWith('audio/') ? <audio src={current.url} controls/> : file.type==='application/pdf' || /\.pdf$/i.test(file.name) ? <iframe src={current.url} title={file.name} className="h-[55dvh] w-full rounded-lg bg-white"/> : current.text !== undefined ? <pre className="max-h-[55dvh] w-full overflow-auto whitespace-pre-wrap break-all text-xs leading-6">{current.text || (zh?'空文本文件':'Empty text file')}</pre> : <div className="flex flex-col items-center gap-4 text-muted-foreground"><FileIcon size={42} strokeWidth={1.25}/><p className="text-sm">{current.failed ? (zh?'预览未能打开，仍可下载文件':'Preview unavailable. You can still download the file.') : (zh?'此格式可下载后使用本机应用打开':'Download this file to open it in a local app')}</p></div>}
    </div>
    <div className="flex flex-wrap items-center justify-between gap-3"><span className="text-xs text-muted-foreground">{formatFileSize(file.size)} · {new Date(file.lastModified).toLocaleDateString()}</span><div className="flex gap-2"><Button variant="outline" onClick={()=>downloadBlob(file,file.name)}><Download size={16}/>{zh?'下载':'Download'}</Button>{onSend && <Button onClick={()=>onSend(file)}><Send size={16}/>{zh?'发送到设备':'Send to device'}</Button>}</div></div>
  </>}</DialogContent></Dialog>;
}
