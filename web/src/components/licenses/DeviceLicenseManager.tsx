'use client';
import { useCallback, useEffect, useRef, useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Laptop, RefreshCw } from 'lucide-react';
import { useI18n } from '@/contexts/I18nContext';
import { getMyDeviceLicense, getLicenseDashboard, issueDeviceLicense, licenseLink, licenseError, redeemDeviceLicense, approveDeviceLicense, revokeDeviceLicense, cancelDeviceLicense, renameDeviceLicense, type LicenseDashboard, type IssuedLicense } from '@/lib/api/deviceLicenses';

export function DeviceLicenseManager() {
  const { localeBcp47 } = useI18n(); const zh = localeBcp47.startsWith('zh');
  const [data, setData] = useState<LicenseDashboard | null>(null);
  const [issued, setIssued] = useState<IssuedLicense | null>(null);
  const [error, setError] = useState(''); const [busy, setBusy] = useState(false);
  const [confirm, setConfirm] = useState<string | null>(null);
  const [rename, setRename] = useState<string | null>(null); const [name, setName] = useState('');
  const revision = useRef(0); const mutating = useRef(false);
  const [copied, setCopied] = useState(false);
  const [codeOpen, setCodeOpen] = useState(false);
  const refresh = useCallback(async () => {
    const current = ++revision.current;
    try { const next = await getLicenseDashboard(); if (current !== revision.current) return; setData(next); setError(''); setIssued(old => old && next.requests.some(r => r.id === old.id) ? old : null); }
    catch(e) { if (current === revision.current) setError(licenseError(e,zh)); }
  }, [zh]);
  useEffect(() => { void refresh(); const timer = setInterval(() => { if (!document.hidden && !mutating.current) void refresh(); },5000); return () => clearInterval(timer); }, [refresh]);
  const act = async (work: () => Promise<unknown>) => { mutating.current = true; revision.current++; setBusy(true); setError(''); try { await work(); await refresh(); } catch(e) { setError(licenseError(e,zh)); } finally { mutating.current = false; setBusy(false); } };
  return <section className="space-y-5">
    <div><h2 className="text-base font-medium">{zh ? '设备授权' : 'Device authorizations'}</h2><p className="mt-2 text-sm text-muted-foreground">{zh ? '购买一次，分配给各台设备。它们无需登录此账号。' : 'Purchase once and assign slots. Your devices do not need to sign into this account.'}</p></div>
    <div className="flex flex-wrap items-center justify-between gap-4"><div><p className="text-2xl font-medium tabular-nums">{data ? `${data.used} / ${data.capacity}` : '—'}</p><p className="mt-1 text-xs text-muted-foreground">{zh ? '已授权设备' : 'Authorized devices'}{data?.reserved ? ` · ${data.reserved} ${zh ? '个名额待激活' : 'reserved'}` : ''}</p></div><div className="flex flex-wrap gap-2">
      <Button variant="outline" disabled={busy || !data?.available} onClick={() => void act(async () => {
        const mine = await getMyDeviceLicense(); if (mine.authorized) return;
        const next = await issueDeviceLicense();
        try { await redeemDeviceLicense(licenseLink(next.qrToken)); }
        catch(e) { await cancelDeviceLicense(next.id).catch(() => {}); throw e; }
      })}>{zh ? '授权本机' : 'Authorize this device'}</Button>
      <Button disabled={busy || !data?.available} onClick={() => void act(async () => { setCopied(false); setIssued(await issueDeviceLicense()); setCodeOpen(true); })}>{zh ? '生成授权码' : 'Generate code'}</Button>
    </div></div>
    {data && data.capacity > 0 && data.available === 0 && <p className="text-sm text-muted-foreground">{zh ? '名额已分配完。可解除一台设备的授权，或撤销待激活授权后重新分配。' : 'All slots are allocated. Release a device or revoke a pending code to free a slot.'}</p>}
    {data?.capacity === 0 && <p className="text-sm text-muted-foreground">{zh ? '在会员套餐中购买设备服务包后，即可分配授权名额。登录管理账号不占用名额。' : 'Purchase a plan in Plans to allocate slots. Signing in to manage billing does not use a slot.'}</p>}
    <Dialog open={codeOpen && !!issued} onOpenChange={setCodeOpen}><DialogContent className="max-w-md"><DialogHeader><DialogTitle>{zh ? '授权另一台设备' : 'Authorize another device'}</DialogTitle></DialogHeader>{issued && <div className="flex flex-col items-center gap-5 py-2">
      <div className="w-fit rounded-xl bg-white p-3"><QRCodeSVG value={licenseLink(issued.qrToken)} size={160}/></div>
      <div className="w-full text-center"><p className="text-xs text-muted-foreground">{zh ? '一次性授权码' : 'Single-use code'}</p><p className="my-3 font-mono text-3xl font-semibold tracking-[.2em]" data-testid="issued-license-code">{issued.code.slice(0,3)} {issued.code.slice(3)}</p><p className="text-xs text-muted-foreground">{zh ? '有效至 ' : 'Expires '}{new Date(issued.expiresAt).toLocaleTimeString()} · {zh ? '手输需在本页确认设备' : 'Manual codes require approval here'}</p><Button className="mt-3" size="sm" variant="outline" onClick={() => void navigator.clipboard.writeText(licenseLink(issued.qrToken)).then(() => setCopied(true)).catch(() => setError(zh ? '无法复制，可选中下方链接复制，或使用二维码。' : 'Select and copy the link below, or use the QR code.'))}>{copied ? (zh ? '已复制' : 'Copied') : (zh ? '复制授权链接' : 'Copy authorization link')}</Button><Input className="mt-3 text-xs" aria-label={zh ? '一次性授权链接' : 'Single-use authorization link'} value={licenseLink(issued.qrToken)} readOnly onFocus={event => event.target.select()}/></div>
    </div>}</DialogContent></Dialog>
    {data?.requests.map(r => <div key={r.id} className="flex flex-wrap items-center justify-between gap-3 rounded-xl border p-4"><div><p className="text-sm font-medium">{r.status === 'CLAIMED' ? `${zh ? '请求授权：' : 'Request: '}${r.name}` : (zh ? '授权码待使用' : 'Code waiting for a device')}</p><p className="mt-1 break-all text-xs text-muted-foreground">{r.deviceId ? `${r.platform} · ${r.deviceId}` : (zh ? '过期会自动释放名额' : 'The reserved slot releases on expiry')}</p></div><div className="flex gap-2">{r.status === 'CLAIMED' && <Button disabled={busy} onClick={() => void act(() => approveDeviceLicense(r.id))}>{zh ? '确认授权' : 'Approve device'}</Button>}<Button variant="ghost" disabled={busy} onClick={() => void act(() => cancelDeviceLicense(r.id))}>{zh ? '撤销' : 'Cancel'}</Button></div></div>)}
    {data && data.devices.length === 0 && data.requests.length === 0 && <div className="rounded-xl border py-12 text-center"><Laptop className="mx-auto mb-3 size-8 text-muted-foreground"/><p className="text-sm">{zh ? '还没有授权设备' : 'No authorized devices yet'}</p><p className="mt-2 text-xs text-muted-foreground">{zh ? '生成授权码，在另一台设备输入或扫码即可。' : 'Generate a code, then enter or scan it on another device.'}</p></div>}
    <div className="divide-y">{data?.devices.map(d => <div key={d.deviceId} className="space-y-3 py-4"><div className="flex flex-wrap items-center justify-between gap-3"><div className="min-w-0"><p className="font-medium">{d.name} <span className="ml-2 text-xs font-normal text-primary">{d.authorized ? (zh ? '已授权' : 'Authorized') : (zh ? '暂停权益' : 'Inactive')}</span></p><p className="mt-1 break-all text-xs text-muted-foreground">{d.platform} · {d.deviceId}</p>{d.lastSeen && <p className="mt-1 text-xs text-muted-foreground">{zh ? '最近连接：' : 'Last connection: '}{new Date(d.lastSeen).toLocaleString()}</p>}</div><div className="flex gap-1"><Button size="sm" variant="ghost" onClick={() => { setRename(d.deviceId); setName(d.name); }}>{zh ? '备注' : 'Rename'}</Button><Button size="sm" variant="outline" disabled={busy} onClick={() => setConfirm(d.deviceId)}>{zh ? '解除授权' : 'Release slot'}</Button></div></div>
      {rename === d.deviceId && <form className="flex gap-2" onSubmit={e => { e.preventDefault(); void act(async () => { await renameDeviceLicense(d.deviceId,name); setRename(null); }); }}><Input aria-label={zh ? '设备备注' : 'Device name'} value={name} maxLength={128} onChange={e => setName(e.target.value)}/><Button disabled={busy || !name.trim()} type="submit">{zh ? '保存' : 'Save'}</Button><Button variant="ghost" type="button" onClick={() => setRename(null)}>{zh ? '取消' : 'Cancel'}</Button></form>}
      {confirm === d.deviceId && <div className="rounded-xl bg-muted/50 p-3"><p className="mb-3 text-sm">{zh ? '解除后可把名额分配给新设备。对方下载的文件不会删除。' : 'Release this slot for another device. Downloaded files are kept.'}</p><Button variant="destructive" disabled={busy} onClick={() => void act(async () => { await revokeDeviceLicense(d.deviceId); setConfirm(null); })}>{zh ? '确认解除' : 'Confirm release'}</Button><Button variant="ghost" onClick={() => setConfirm(null)}>{zh ? '取消' : 'Cancel'}</Button></div>}
    </div>)}</div>
    {error && <div role="alert" className="flex items-center gap-3 text-sm text-destructive">{error}<Button variant="outline" onClick={() => void refresh()}><RefreshCw className="size-4"/>{zh ? '重试' : 'Retry'}</Button></div>}
    <p className="text-xs leading-5 text-muted-foreground">{zh ? '授权只提供设备服务权益，不共享账号文件或历史。会员到期后，本地文件和离线传输仍可使用。' : 'Authorization grants device service benefits, not account files or history. Local files and offline transfers remain available after expiry.'}</p>
  </section>;
}
