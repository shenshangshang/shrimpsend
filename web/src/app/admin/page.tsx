'use client';
import Link from 'next/link';
import { useEffect, useState } from 'react';
import { ArrowRight, Package } from 'lucide-react';
import { listAdminAppVersions, type AdminAppVersionRow } from '@/lib/api/adminAppVersion';
import { Button, buttonVariants } from '@/components/ui/button';

export default function AdminDashboardPage() {
  const [versions,setVersions] = useState<AdminAppVersionRow[]>([]);
  const [error,setError] = useState('');
  const [loading,setLoading] = useState(true);
  const [refresh,setRefresh] = useState(0);
  useEffect(()=>{let disposed=false;listAdminAppVersions().then(rows=>{if(!disposed)setVersions(rows.slice(0,5));}).catch(()=>{if(!disposed)setError('暂时无法加载最近更新');}).finally(()=>{if(!disposed)setLoading(false);});return()=>{disposed=true;};},[refresh]);
  return <div className="max-w-4xl space-y-8">
    <div><h1 className="text-2xl font-semibold">管理后台</h1><p className="mt-2 text-sm text-muted-foreground">管理各端的应用版本与下载信息。</p></div>
    <div className="flex flex-wrap items-center gap-4 rounded-xl border border-border p-5"><Package className="text-primary" size={32}/><div className="flex-1 min-w-40"><h2 className="text-base font-medium">版本管理</h2><p className="mt-1 text-sm text-muted-foreground">维护版本、平台与更新说明。</p></div><Link href="/admin/versions" className={buttonVariants()}>打开版本管理<ArrowRight size={16}/></Link></div>
    <section><h2 className="text-base font-medium mb-5">最近更新</h2>
      {loading?<p className="text-sm text-muted-foreground py-10">加载中…</p>:error?<div className="flex items-center gap-3 text-sm text-destructive">{error}<Button variant="outline" onClick={()=>{setLoading(true);setError('');setRefresh(v=>v+1);}}>重试</Button></div>:versions.length===0?<p className="py-10 text-sm text-muted-foreground">还没有发布记录。添加第一个版本后会显示在这里。</p>:<div className="overflow-auto"><table className="w-full text-sm"><thead className="bg-muted text-muted-foreground"><tr><th className="text-left p-3 font-normal">版本</th><th className="text-left p-3 font-normal">构建号</th><th className="text-left p-3 font-normal">发布时间</th><th className="text-left p-3 font-normal">状态</th></tr></thead><tbody>{versions.map(v=><tr key={v.id} className="border-b border-border"><td className="p-3"><Link className="text-primary" href="/admin/versions">{v.version}</Link></td><td className="p-3 tabular-nums">{v.buildNumber}</td><td className="p-3 text-muted-foreground">{v.releasedAt||'—'}</td><td className="p-3">{v.webPublished?'官网发布中':v.enabled?'已启用':'未启用'}</td></tr>)}</tbody></table></div>}
    </section>
  </div>;
}
