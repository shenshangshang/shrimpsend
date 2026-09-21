'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { UserRound } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useI18n } from '@/contexts/I18nContext';
import { SettingsShell } from '@/components/settings/SettingsShell';
import { EmptyState } from '@/components/ui/page';
import { buttonVariants } from '@/components/ui/button';
export default function SettingsLayout({ children }: { children: React.ReactNode }) {
  const { accessToken, isReady } = useAuth();
  const { t } = useI18n();
  const path = usePathname();
  const accountRequired = ['/settings/account','/settings/s3'].includes(path);
  return <SettingsShell>{!isReady ? <p role="status" className="quiet-note">{t('common.loading')}</p> : !accessToken && accountRequired ? <EmptyState icon={UserRound} title={t('settings.navAccount')} description={t('conversation.accountNeeded')} action={<Link href={`/login?next=${encodeURIComponent(path)}`} className={buttonVariants()}>{t('deviceList.guestLoginCta')}</Link>}/> : children}</SettingsShell>;
}
