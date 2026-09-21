'use client';
import Link from 'next/link';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Check, Laptop, Loader2 } from 'lucide-react';
import { useI18n } from '@/contexts/I18nContext';
import { SettingsShell } from '@/components/settings/SettingsShell';
import { PageHeader } from '@/components/ui/page';
import { Button, buttonVariants } from '@/components/ui/button';
import { CodeInput } from '@/components/ui/code-input';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { LicenseScanner } from '@/components/licenses/LicenseScanner';
import { getMyDeviceLicense, licenseError, redeemDeviceLicense, releaseMyDeviceLicense, type DeviceLicense } from '@/lib/api/deviceLicenses';
import { getDeviceName } from '@/lib/deviceId';

export default function AuthorizePage() {
  const { localeTag } = useI18n(); const zh = localeTag === 'zh_CN';
  const [license, setLicense] = useState<DeviceLicense | null>(null);
  const [input, setInput] = useState(''); const [busy, setBusy] = useState(false);
  const [error, setError] = useState(''); const [release, setRelease] = useState(false);
  const [scanValue, setScanValue] = useState('');
  const [pollError, setPollError] = useState('');
  const revision = useRef(0); const mutating = useRef(false);
  const refresh = useCallback(async (force = false) => {
    if (mutating.current && !force) return;
    const current = ++revision.current;
    try { const next = await getMyDeviceLicense(); if (current === revision.current) { setLicense(next); setPollError(''); } }
    catch (e) { if (current === revision.current) setPollError(licenseError(e, zh)); }
  }, [zh]);
  useEffect(() => {
    const fragment = new URLSearchParams(window.location.hash.slice(1)).get('license');
    if (fragment) { setScanValue(window.location.href); window.history.replaceState(null, '', '/authorize'); }
    void refresh();
    const timer = setInterval(() => { if (!document.hidden) void refresh(); }, 5000);
    return () => clearInterval(timer);
  }, [refresh]);
  const redeem = async (value: string) => {
    mutating.current = true; revision.current++; setBusy(true); setError('');
    try { setLicense(await redeemDeviceLicense(value)); setInput(''); setScanValue(''); }
    catch (e) { setError(licenseError(e, zh)); }
    finally { mutating.current = false; setBusy(false); }
  };
  const authorized = license?.authorized;
  const pending = license?.pendingRequest;
  return <SettingsShell><div className="max-w-xl">
    <PageHeader title={zh ? '本机授权' : 'Device authorization'} description={zh ? '无需登录，让这台设备独立获得会员服务。' : 'Give this device membership service without signing in.'}/>
    {(authorized || pending) && <div className="mb-7 flex flex-col items-center gap-3 pt-3 text-center"><div className="flex size-14 items-center justify-center rounded-xl bg-accent-soft text-primary">{authorized ? <Check size={30}/> : <Loader2 size={28} className="animate-spin"/>}</div><h2 className="text-xl font-semibold">{authorized ? (zh ? '本机已授权' : 'Device authorized') : (zh ? '等待购买者确认' : 'Waiting for approval')}</h2><p className="text-sm text-muted-foreground">{authorized ? (zh ? '已授权设备无需保持账号登录。' : 'You can stay signed out on this device.') : (zh ? '请让生成授权码的人确认这台设备，本页会自动更新。' : 'Ask the code owner to approve this device. This page updates automatically.')}</p></div>}
    <section className="mb-7 overflow-hidden rounded-xl border border-border">
      <div className="flex items-center gap-4 bg-muted/70 p-4"><Laptop size={29} strokeWidth={1.5}/><div className="min-w-0 flex-1"><p className="truncate text-sm font-medium">{getDeviceName() || license?.name}</p><p className="mt-1 text-xs text-muted-foreground">{authorized ? (zh ? '已授权 · 在线信令服务已启用' : 'Authorized · Online signaling enabled') : license?.status === 'SUSPENDED' ? (zh ? '名额不足，请联系购买者调整' : 'Contact the owner to adjust device slots') : license?.status === 'EXPIRED' ? (zh ? '授权到期，续费后自动恢复' : 'Expired · Renew to restore service') : (zh ? '免费设备 · 离线传输可用' : 'Free device · Offline transfers available')}</p></div><span className="text-xs text-muted-foreground">Web</span></div>
      {license?.ownerLabel && <dl className="grid grid-cols-[100px_1fr] gap-3 p-4 text-xs"><dt className="text-muted-foreground">{zh ? '授权来源' : 'Provided by'}</dt><dd>{license.ownerLabel}</dd><dt className="text-muted-foreground">{zh ? '有效期' : 'Valid until'}</dt><dd>{license.expiresAt ? new Date(license.expiresAt).toLocaleDateString() : (zh ? '长期有效' : 'Lifetime')}</dd></dl>}
      {pending && <p className="p-4 text-xs text-muted-foreground">{zh ? '申请有效至' : 'Request expires'} {new Date(pending.expiresAt).toLocaleTimeString()}</p>}
    </section>
    {!authorized && !pending && <form className="space-y-4" onSubmit={e => { e.preventDefault(); if (/^[A-Z0-9]{6}$/.test(input)) void redeem(input); }}>
      <label className="block text-sm text-muted-foreground" htmlFor="license-code">{zh ? '六位授权码' : 'Six-character code'}</label>
      <CodeInput id="license-code" value={input} onChange={setInput} label={zh ? '六位授权码' : 'Six-character authorization code'}/>
      <Button type="submit" className="w-full" disabled={!/^[A-Z0-9]{6}$/.test(input) || busy}>{busy ? (zh ? '处理中…' : 'Working…') : (zh ? '授权本机' : 'Authorize this device')}</Button>
      <LicenseScanner zh={zh} onRead={value => { setScanValue(value); setError(''); }}/>
      <p className="text-center text-xs leading-6 text-muted-foreground">{zh ? '六位码提交后，需由购买者确认。' : 'The purchaser must approve short-code requests.'}</p>
    </form>}
    {authorized && <Link href="/chat" className={`${buttonVariants()} w-full`}>{zh ? '返回传输' : 'Back to transfers'}</Link>}
    {license && ['AUTHORIZED','EXPIRED','SUSPENDED'].includes(license.status) && <Button variant="outline" className="mt-3 w-full" onClick={() => setRelease(true)}>{zh ? '解除本机授权' : 'Release authorization'}</Button>}
    {(error || pollError) && <p role="alert" className="mt-4 rounded-lg bg-destructive/5 p-3 text-sm text-destructive">{error || pollError}</p>}
    <p className="mt-8 border-t border-border pt-5 text-xs text-muted-foreground">{zh ? '已有会员账号？' : 'Already have a membership?'} <Link href="/settings/membership" className="text-primary hover:underline">{zh ? '管理设备名额 →' : 'Manage device slots →'}</Link></p>
    <Dialog open={!!scanValue} onOpenChange={open => { if (!open) setScanValue(''); }}><DialogContent className="max-w-sm"><DialogHeader><DialogTitle>{zh ? '授权这台设备' : 'Authorize this device'}</DialogTitle><DialogDescription>{zh ? '请核对本机名称。授权不会登录购买账号或同步文件。' : 'Check the device name. Authorization does not sign in or sync files.'}</DialogDescription></DialogHeader><p className="flex items-center gap-3 rounded-lg bg-muted p-4 text-sm"><Laptop size={24}/>{getDeviceName()}</p><Button disabled={busy} onClick={() => void redeem(scanValue)}>{zh ? '授权本机' : 'Authorize'}</Button>{error && <p role="alert" className="text-sm text-destructive">{error}</p>}</DialogContent></Dialog>
    <Dialog open={release} onOpenChange={setRelease}><DialogContent className="max-w-sm"><DialogHeader><DialogTitle>{zh ? '解除本机授权？' : 'Release authorization?'}</DialogTitle><DialogDescription>{zh ? '本机恢复免费服务。下载文件和本地历史会保留。' : 'Return to free service. Downloaded files and local history are kept.'}</DialogDescription></DialogHeader><div className="flex justify-end gap-2"><Button variant="outline" onClick={() => setRelease(false)}>{zh ? '取消' : 'Cancel'}</Button><Button variant="destructive" disabled={busy} onClick={async () => { mutating.current = true; revision.current++; setBusy(true); try { await releaseMyDeviceLicense(); await refresh(true); setRelease(false); } catch(e) { setError(licenseError(e,zh)); } finally { mutating.current = false; setBusy(false); } }}>{zh ? '解除授权' : 'Release'}</Button></div></DialogContent></Dialog>
  </div></SettingsShell>;
}
