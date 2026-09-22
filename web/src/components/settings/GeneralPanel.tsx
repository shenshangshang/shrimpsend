'use client';
import { useEffect, useState } from 'react';
import { toast } from 'sonner';
import { useI18n } from '@/contexts/I18nContext';
import { useChatContext } from '@/contexts/ChatContext';
import { syncDeviceName } from '@/lib/devicePresence';
import { getDeviceName, setDeviceName } from '@/lib/deviceId';
import { loadAutoCopyIncomingText, persistAutoCopyIncomingText } from '@/lib/autoCopyPreferences';
import { SettingRow, Toggle } from '@/components/ui/page';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';

export function GeneralPanel() {
  const { localeTag } = useI18n(); const zh = localeTag === 'zh_CN';
  const { refreshDevices, connected } = useChatContext();
  const [name, setName] = useState(''); const [saving, setSaving] = useState(false); const [savedName, setSavedName] = useState(''); const [copy, setCopy] = useState(true);
  useEffect(() => { let alive = true; queueMicrotask(() => { if (alive) { setName(getDeviceName()); setSavedName(getDeviceName()); setCopy(loadAutoCopyIncomingText()); } }); return () => { alive = false; }; }, []);
  const validName = !!name.trim() && name.trim().length <= 80 && !/[\u0000-\u001f\u007f-\u009f]/.test(name.trim());
  return <div>
    <SettingRow title={zh ? '设备名称' : 'Device name'} description={zh ? '其他设备会通过这个名称找到你。' : 'How this device appears to others.'} control={<form className="flex gap-2" onSubmit={async e => { e.preventDefault(); if (!validName || saving) return; setSaving(true); try { setDeviceName(name.trim()); setSavedName(name.trim()); await syncDeviceName(); refreshDevices(); toast.success(zh ? '设备名称已同步' : 'Device name synced'); } catch { toast.info(zh ? '已保存在本机，联网后自动同步' : 'Saved locally; will sync when connected'); } finally { setSaving(false); } }}><Input value={name} maxLength={80} onChange={e => setName(e.target.value)} aria-label={zh ? '设备名称' : 'Device name'} className="max-w-44"/><Button variant="outline" type="submit" disabled={saving || !validName || name.trim() === savedName}>{saving ? (zh ? '保存中…' : 'Saving…') : (zh ? '保存' : 'Save')}</Button></form>}/>
    <SettingRow title={zh ? '自动复制收到的文本' : 'Copy incoming text'} description={zh ? '收到文本后，自动放入本机剪贴板。浏览器可能需要允许访问剪贴板。' : 'Copy received text to the clipboard when permission is available.'} control={<Toggle label={zh ? '自动复制收到的文本' : 'Copy incoming text'} checked={copy} onChange={value => { setCopy(value); persistAutoCopyIncomingText(value); }}/>} />
    <SettingRow title={zh ? '连接状态' : 'Connection'} description={zh ? '自动选择可用通道，优先直接传输。' : 'Available direct connections are preferred automatically.'} control={<span className={`text-sm ${connected ? 'text-primary' : 'text-muted-foreground'}`}>{connected ? (zh ? '在线' : 'Online') : (zh ? '离线模式' : 'Offline mode')}</span>}/>
    <p className="quiet-note mt-6">{zh ? '无需登录即可传输。授权只影响本机的在线服务额度，文件和历史始终属于各自设备。' : 'Transfer without signing in. Authorization changes this device’s online service allowance; files and history remain independent.'}</p>
  </div>;
}
