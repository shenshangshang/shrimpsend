'use client';

import { usePathname, useRouter } from 'next/navigation';
import { SiteNav } from '@/components/landing/SiteNav';
import { SiteFooter } from '@/components/landing/SiteFooter';
import { useI18n } from '@/contexts/I18nContext';

export function LegalShell({children}: {children: React.ReactNode}) {
  const {localeTag} = useI18n();
  const zh = localeTag.startsWith('zh');
  const pathname = usePathname();
  const router = useRouter();
  const document = pathname.endsWith('/terms') ? 'terms' : 'privacy';
  const value = pathname.includes('/cn/') ? 'cn' : pathname.includes('/intl/en/') ? 'intl/en' : 'intl/zh';
  return <div className="public-site">
    <SiteNav active="docs"/>
    <div className="mx-auto flex max-w-[1100px] justify-end px-5 pt-5">
      <label className="flex items-center gap-3 text-xs text-muted-foreground">{zh?'适用地区与语言':'Region and language'}
        <select className="rounded-lg border border-border bg-background px-3 h-10 text-foreground" value={value} onChange={e=>router.push(`/legal/${e.target.value}/${document}`)}>
          <option value="cn">中国大陆 · 简体中文</option><option value="intl/zh">国际 · 简体中文</option><option value="intl/en">International · English</option>
        </select>
      </label>
    </div>
    {children}
    <SiteFooter/>
  </div>;
}
