'use client';
import { Suspense, useMemo, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { Copy, File, MessageSquare, Search, SearchX } from 'lucide-react';
import { toast } from 'sonner';
import { useChatContext } from '@/contexts/ChatContext';
import { useI18n } from '@/contexts/I18nContext';
import { FilesShell } from '@/components/files/FilesShell';
import { PageHeader, EmptyState } from '@/components/ui/page';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
export default function SearchPage() { return <Suspense><SearchContent/></Suspense>; }
function SearchContent() {
  const params = useSearchParams();
  const { localeTag } = useI18n(); const zh = localeTag === 'zh_CN'; const router = useRouter();
  const { messages, devices, currentDeviceId, setSelectedDeviceId } = useChatContext();
  const [query,setQuery] = useState(''); const [type,setType] = useState('all'); const [peer,setPeer] = useState(params.get('device') || 'all');
  const results = useMemo(() => messages.filter(m => {
    if (!['text','file'].includes(m.type) || (type !== 'all' && m.type !== type)) return false;
    if (peer !== 'all' && m.fromDeviceId !== peer && m.toDeviceId !== peer) return false;
    const p = m.payload as {text?:string;fileName?:string}; return `${p.text || ''} ${p.fileName || ''}`.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase());
  }).sort((a,b)=>b.ts-a.ts),[messages,query,type,peer]);
  return <FilesShell><PageHeader title={zh?'搜索':'Search'} description={zh?'在这台设备的文本和文件记录中查找，无需登录。':'Search text and files stored on this device, without signing in.'}/><div className="relative mb-5"><Search className="absolute left-3 top-3 size-5 text-muted-foreground"/><Input value={query} onChange={e=>setQuery(e.target.value)} className="h-11 pl-10" autoFocus aria-label={zh?'搜索文本或文件':'Search text or files'} placeholder={zh?'搜索文本、文件名…':'Search text or file names…'}/></div><div className="mb-5 flex flex-wrap items-center justify-between gap-4"><nav className="flex gap-2" aria-label={zh?'内容类型':'Content type'}>{[['all',zh?'全部':'All'],['text',zh?'文本':'Text'],['file',zh?'文件':'Files']].map(([value,label])=><Button key={value} size="sm" variant={type===value?'secondary':'ghost'} aria-pressed={type===value} onClick={()=>setType(value)}>{label}</Button>)}</nav><select value={peer} onChange={e=>setPeer(e.target.value)} aria-label={zh?'筛选设备':'Filter by device'} className="h-10 max-w-64 rounded-lg border border-input bg-card px-3 text-sm"><option value="all">{zh?'所有设备':'All devices'}</option>{devices.filter(d=>d.deviceId!==currentDeviceId).map(d=><option key={d.deviceId} value={d.deviceId}>{d.name}</option>)}</select></div>{results.length ? <div className="divide-y divide-border">{results.map((m,index)=>{ const p=m.payload as {text?:string;fileName?:string}; const deviceId=m.fromDeviceId===currentDeviceId?m.toDeviceId:m.fromDeviceId; return <article key={m._localId || `${m.id}-${index}`} className="flex items-start gap-4 py-5"><div className="rounded-lg bg-muted p-2.5 text-muted-foreground">{m.type==='text'?<MessageSquare size={20}/>:<File size={20}/>}</div><button className="min-w-0 flex-1 text-left" onClick={()=>{if(deviceId)setSelectedDeviceId(deviceId);router.push('/chat');}}><p className="line-clamp-3 whitespace-pre-wrap break-words text-sm leading-6">{p.text || p.fileName}</p><p className="mt-2 text-xs text-muted-foreground">{devices.find(d=>d.deviceId===deviceId)?.name || (zh?'设备':'Device')} · {new Date(m.ts).toLocaleString()}</p></button>{m.type==='text'&&<Button variant="ghost" size="icon" aria-label={zh?'复制文本':'Copy text'} onClick={async()=>{try {await navigator.clipboard.writeText(p.text||'');toast.success(zh?'已复制':'Copied');}catch{toast.error(zh?'无法访问剪贴板，请选择文本复制。':'Select the text to copy it.');}}}><Copy size={16}/></Button>}</article>;})}</div>:<EmptyState icon={SearchX} title={zh?'没有找到结果':'No results'} description={zh?'试试其他关键词，或更改设备筛选。':'Try another keyword or device filter.'}/>}<p className="mt-5 text-xs text-muted-foreground">{results.length} {zh?'条结果 · 仅搜索本机记录':'results · Local history only'}</p></FilesShell>;
}
