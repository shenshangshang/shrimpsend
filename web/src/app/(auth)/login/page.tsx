'use client';
import Link from 'next/link';
import { ChevronLeft } from 'lucide-react';
import { useI18n } from '@/contexts/I18nContext';
import { LoginAuthCard } from '@/components/auth/login-auth-card';
export default function LoginPage() { const {localeTag}=useI18n();const zh=localeTag==='zh_CN';return <main className="auth-surface px-5"><div className="mx-auto max-w-5xl pt-7"><Link href="/chat" className="inline-flex items-center gap-1 text-sm text-muted-foreground"><ChevronLeft size={17}/>{zh?'返回传输':'Back to transfers'}</Link></div><div className="auth-form"><LoginAuthCard/><p className="mt-6 text-center text-xs text-muted-foreground">{zh?'只想传文件？':'Just want to transfer files?'} <Link href="/chat" className="text-primary hover:underline">{zh?'免登录使用 →':'Continue without signing in →'}</Link></p></div></main>; }
