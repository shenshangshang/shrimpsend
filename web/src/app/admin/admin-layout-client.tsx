'use client';

import Link from 'next/link';
import { useAuth } from '@/contexts/AuthContext';
import { useRouter, usePathname } from 'next/navigation';
import { ArrowLeft, House, Package, UserRound } from 'lucide-react';
import { BrandLogo } from '@/components/brand/BrandLogo';
import { useEffect, useState } from 'react';
import { fetchUserProfile } from '@/lib/api/user';
import { isAdminEmail } from '@/lib/adminEmails';
import { logger } from '@/lib/logger';
import { buttonVariants } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { cn } from '@/lib/utils';

const TAG = 'adminLayout';

type GateState = 'loading' | 'allowed' | 'forbidden';

/**
 * 后台路由统一门禁：已登录且邮箱在管理员白名单内才展示子页面。
 */
export default function AdminLayout({ children }: { children: React.ReactNode }) {
  const { accessToken, isReady } = useAuth();
  const router = useRouter();
  const pathname = usePathname();
  const [gate, setGate] = useState<GateState>('loading');

  useEffect(() => {
    if (!isReady) return;
    if (!accessToken) {
      router.replace('/login?next=' + encodeURIComponent(pathname));
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        const p = await fetchUserProfile();
        if (cancelled) return;
        setGate(isAdminEmail(p.email) ? 'allowed' : 'forbidden');
      } catch (e) {
        logger.warn(TAG, 'profile failed', e);
        if (!cancelled) setGate('forbidden');
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [isReady, accessToken, router, pathname]);

  if (!isReady) {
    return (
      <div className="flex min-h-dvh items-center justify-center text-muted-foreground text-sm">加载中…</div>
    );
  }

  if (!accessToken) {
    return null;
  }

  if (gate === 'loading') {
    return (
      <div className="flex min-h-dvh items-center justify-center text-muted-foreground text-sm">验证管理员权限…</div>
    );
  }

  if (gate === 'forbidden') {
    return (
      <div className="mx-auto max-w-lg px-4 py-16">
        <Card>
          <CardHeader>
            <CardTitle>无权访问</CardTitle>
            <CardDescription>当前账号不在后台管理员邮箱白名单中。</CardDescription>
          </CardHeader>
          <CardContent>
            <Link href="/chat" className={cn(buttonVariants())}>
              返回会话
            </Link>
          </CardContent>
        </Card>
      </div>
    );
  }

  return <div className="admin-shell">
    <header className="admin-header"><Link href="/admin" className="flex items-center gap-2.5"><BrandLogo size={30} alt="虾传"/><strong className="font-medium">虾传</strong><span className="text-sm text-muted-foreground">后台管理</span></Link><Link href="/settings/account" className="flex items-center gap-2 text-sm"><UserRound size={17}/>管理员</Link></header>
    <div className="admin-body"><aside className="admin-sidebar"><nav aria-label="后台导航">
      <Link href="/admin" aria-current={pathname==='/admin'?'page':undefined}><House size={19}/>概览</Link>
      <Link href="/admin/versions" aria-current={pathname.startsWith('/admin/versions')?'page':undefined}><Package size={19}/>版本管理</Link>
      <Link href="/chat" className="admin-back"><ArrowLeft size={18}/>返回应用</Link>
    </nav></aside><main className="admin-content">{children}</main></div>
  </div>;
}
