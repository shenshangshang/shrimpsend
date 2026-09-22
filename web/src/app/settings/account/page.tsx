'use client';
import { useI18n } from '@/contexts/I18nContext';
import { AccountPanel } from '@/components/settings';
import { PageHeader } from '@/components/ui/page';
export default function Page() { const {localeTag}=useI18n();const zh=localeTag==='zh_CN';return <><PageHeader title={zh?'账号':'Account'} description={zh?'管理购买账号。设备授权与账号登录相互独立。':'Manage your purchasing account. Device authorization is independent of sign-in.'}/><AccountPanel/></>; }
