'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { BadgeCheck, ChevronLeft, ChevronRight, CircleHelp, Monitor, ShieldCheck, UserRound } from 'lucide-react';
import { useI18n } from '@/contexts/I18nContext';
import { AppShell } from '@/components/layout/AppShell';
import { PageHeader } from '@/components/ui/page';

export function SettingsShell({ children }: { children: React.ReactNode }) {
  const { localeTag } = useI18n();
  const zh = localeTag === 'zh_CN';
  const path = usePathname();
  const sections = [
    { href: '/settings', label: zh ? '本机设置' : 'Device settings', icon: Monitor },
    { href: '/authorize', label: zh ? '本机授权' : 'Authorization', icon: ShieldCheck },
    { href: '/settings/membership', label: zh ? '会员与名额' : 'Membership & slots', icon: BadgeCheck },
    { href: '/settings/account', label: zh ? '账号' : 'Account', icon: UserRound },
    { href: '/settings/about', label: zh ? '帮助' : 'Help', icon: CircleHelp },
  ];
  const tabs = [
    { href: '/settings', label: zh ? '通用' : 'General' },
    { href: '/settings/receiving', label: zh ? '接收与保存' : 'Receiving' },
    { href: '/settings/appearance', label: zh ? '外观' : 'Appearance' },
    { href: '/settings/language', label: zh ? '语言' : 'Language' },
    { href: '/settings/fonts', label: zh ? '字体' : 'Fonts' },
    { href: '/settings/shortcuts', label: zh ? '快捷键' : 'Shortcuts' },
  ];
  const local = tabs.some(tab => tab.href === path);
  const active = local ? '/settings' : path.startsWith('/settings/help') ? '/settings/about' : path;
  return <AppShell sidebar={<><h1 className="workspace-sidebar-title">{zh ? '设置' : 'Settings'}</h1><nav aria-label={zh ? '设置分类' : 'Settings sections'}>{sections.map(({ href, label, icon: Icon }) => <Link key={href} href={href} className={`workspace-nav-link ${active === href ? 'is-active' : ''}`} aria-current={active === href ? 'page' : undefined}><Icon size={18} strokeWidth={1.65}/>{label}</Link>)}</nav></>}>
    <div className="settings-content">
      {path !== '/settings' && <Link href="/settings" className="mb-5 inline-flex items-center gap-1 text-sm text-muted-foreground md:hidden"><ChevronLeft size={18}/>{zh ? '设置' : 'Settings'}</Link>}
      {local && <><PageHeader title={zh ? '本机设置' : 'Device settings'} description={zh ? '只影响这台设备，按你的习惯使用。' : 'Make this device work the way you like.'}/><nav className="settings-tabs" aria-label={zh ? '本机设置选项' : 'Device preferences'}>{tabs.map(tab => <Link key={tab.href} href={tab.href} aria-current={path === tab.href ? 'page' : undefined}>{tab.label}</Link>)}</nav></>}
      {children}
      {path === '/settings' && <nav className="mt-8 divide-y divide-border md:hidden" aria-label={zh ? '其他设置' : 'More settings'}>{sections.slice(1).map(({ href, label, icon: Icon }) => <Link key={href} href={href} className="flex items-center gap-3 py-4 text-sm"><Icon size={19}/><span className="flex-1">{label}</span><ChevronRight size={17} className="text-muted-foreground"/></Link>)}</nav>}
    </div>
  </AppShell>;
}
