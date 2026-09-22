'use client';
import { useSyncExternalStore } from 'react';
import { Cloud, X } from 'lucide-react';
import { useI18n } from '@/contexts/I18nContext';
import { readCloudTransfers,subscribeCloudTransfers,cancelCloudTransfer,retryCloudTransfer,type CloudTransfer } from '@/lib/cloudTransfers';
import { Button } from '@/components/ui/button';
const EMPTY: CloudTransfer[]=[];
export function CloudTransferList({ filter='all' }: { filter?:string }) {
  const {localeTag}=useI18n();const zh=localeTag==='zh_CN';
  const jobs=useSyncExternalStore(subscribeCloudTransfers,readCloudTransfers,()=>EMPTY).filter(row=>filter==='all'||row.status===filter||(filter==='failed'&&row.status==='cancelled'));
  if(!jobs.length)return null;
  return <section aria-label={zh?'云端传输':'Cloud transfers'} className="mb-6 divide-y divide-border rounded-xl border border-border px-4">{jobs.map(job=><div key={job.id} className="flex items-center gap-3 py-4"><Cloud size={22} className="shrink-0 text-primary"/><div className="min-w-0 flex-1"><p className="truncate text-sm">{job.name}</p><p className="mt-1 text-xs text-muted-foreground">{job.status==='active'?(zh?'正在传输':'Transferring'):job.status==='complete'?(zh?'已完成':'Completed'):job.status==='failed'?(zh?'传输失败，请检查连接后重试':'Transfer failed. Check the connection and retry'):(zh?'已取消':'Cancelled')}</p>{job.status==='active'&&<progress aria-label={job.name} className="mt-2 h-1 w-full accent-primary" max={100} value={job.progress}/>}</div>{job.status==='active'?<Button size="icon" variant="ghost" aria-label={zh?'取消云端传输':'Cancel cloud transfer'} onClick={()=>cancelCloudTransfer(job.id)}><X size={16}/></Button>:job.status!=='complete'?<Button variant="outline" size="sm" onClick={()=>retryCloudTransfer(job.id)}>{zh?'重试':'Retry'}</Button>:null}</div>)}</section>;
}
