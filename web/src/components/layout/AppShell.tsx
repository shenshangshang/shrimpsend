'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Folder, Send, Settings } from 'lucide-react';
import { BrandLogo } from '@/components/brand/BrandLogo';
import { useI18n } from '@/contexts/I18nContext';
import { cn } from '@/lib/utils';

export function AppNavigation({ hideMobile = false }: { hideMobile?: boolean }) {
  const { localeTag } = useI18n();
  const zh = localeTag === 'zh_CN';
  const pathname = usePathname();
  const section = pathname.startsWith('/files') || pathname === '/search' ? 'files'
    : pathname === '/chat' || pathname === '/devices' ? 'chat' : 'settings';
  const items = [
    { id: 'chat', href: '/chat', icon: Send, label: zh ? '传输' : 'Transfer' },
    { id: 'files', href: '/files', icon: Folder, label: zh ? '文件' : 'Files' },
    { id: 'settings', href: '/settings', icon: Settings, label: zh ? '设置' : 'Settings' },
  ];
  return <nav aria-label={zh ? '主导航' : 'Main navigation'} className={cn('app-navigation', hideMobile && 'app-navigation-desktop')}>
    <Link href="/chat" className="app-navigation-brand" aria-label={zh ? '虾传首页' : 'Shrimpsend home'}><BrandLogo size={32} alt="" /><span>{zh ? '虾传' : 'Shrimp'}</span></Link>
    {items.map(({ id, href, icon: Icon, label }) => <Link key={id} href={href} aria-current={section === id ? 'page' : undefined}
      className={cn('app-navigation-item', id === 'settings' && 'app-navigation-settings', section === id && 'is-active')}>
      <Icon size={22} strokeWidth={1.65} /><span>{label}</span>
    </Link>)}
  </nav>;
}

export function AppShell({ children, sidebar, hideMobileNavigation = false, className }: {
  children: React.ReactNode; sidebar?: React.ReactNode; hideMobileNavigation?: boolean; className?: string;
}) {
  return <div className={cn('workspace-shell', !hideMobileNavigation && 'has-mobile-navigation', className)}>
    <AppNavigation hideMobile={hideMobileNavigation} />
    {sidebar && <aside className="workspace-sidebar">{sidebar}</aside>}
    <main className="workspace-main">{children}</main>
  </div>;
}
