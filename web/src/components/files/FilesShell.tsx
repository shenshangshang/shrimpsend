'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { ArrowDownUp, Clock3, Cloud, Folder, Settings2, Star } from 'lucide-react';
import { AppShell } from '@/components/layout/AppShell';
import { useI18n } from '@/contexts/I18nContext';
export function FilesShell({ children }: { children: React.ReactNode }) {
  const { localeTag } = useI18n(); const zh = localeTag === 'zh_CN'; const path = usePathname();
  const items = [
    ['/files', zh ? '本机文件' : 'Local files', Folder],
    ['/files/cloud', zh ? '云端文件' : 'Cloud files', Cloud],
    ['/files/recent', zh ? '最近使用' : 'Recent', Clock3],
    ['/files/favorites', zh ? '收藏' : 'Favorites', Star],
    ['/files/tasks', zh ? '传输任务' : 'Transfers', ArrowDownUp],
    ['/files/connections', zh ? '连接设置' : 'Connections', Settings2],
  ] as const;
  return <AppShell sidebar={<><h1 className="workspace-sidebar-title">{zh ? '文件' : 'Files'}</h1><nav aria-label={zh ? '文件分类' : 'File sections'}>{items.map(([href,label,Icon]) => <Link key={href} href={href} className="workspace-nav-link" aria-current={path === href ? 'page' : undefined}><Icon size={18} strokeWidth={1.6}/>{label}</Link>)}</nav></>}><div className="page-content"><nav className="settings-tabs md:hidden" aria-label={zh ? '文件分类' : 'File sections'}>{items.map(([href,label]) => <Link key={href} href={href} aria-current={path === href ? 'page' : undefined}>{label}</Link>)}</nav>{children}</div></AppShell>;
}
