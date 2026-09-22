'use client';
import { useI18n } from '@/contexts/I18nContext';
import { MembershipPanel } from '@/components/settings';
import { PageHeader } from '@/components/ui/page';
export default function Page() { const {localeTag}=useI18n();const zh=localeTag==='zh_CN';return <><PageHeader title={zh?'会员与名额':'Membership & slots'} description={zh?'一个账号购买，按设备分配。其他设备无需登录。':'Purchase on one account. Assign device slots without signing in elsewhere.'}/><MembershipPanel/></>; }
