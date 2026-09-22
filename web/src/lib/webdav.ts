
export type DavConnection = { id: string; name: string; url: string; username: string };
export type DavEntry = { name: string; path: string; directory: boolean; size: number; modified: string };
const passwords = new Map<string,string>();
const CONFIG_KEY = 'shrimpsend:webdav-connections';
export function readDavConnections(): DavConnection[] { try { const value = JSON.parse(localStorage.getItem(CONFIG_KEY) || '[]'); return Array.isArray(value) ? value.filter(c => c && ['id','name','url','username'].every(key => typeof c[key] === 'string')) : []; } catch { return []; } }
export function saveDavConnection(connection: DavConnection, password?: string) {
  const url = new URL(connection.url);
  if (!['http:','https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) throw new Error('invalid_url');
  const normalized = { ...connection, url: url.href.replace(/\/?$/,'/') };
  localStorage.setItem(CONFIG_KEY,JSON.stringify([...readDavConnections().filter(c=>c.id!==connection.id),normalized]));
  if (password !== undefined) passwords.set(connection.id,password);
  return normalized;
}
export function removeDavConnection(id: string) { localStorage.setItem(CONFIG_KEY,JSON.stringify(readDavConnections().filter(c=>c.id!==id)));passwords.delete(id); }
export function setDavPassword(id: string, password: string) { passwords.set(id,password); }
export function davNeedsPassword(connection: DavConnection) { return !!connection.username && !passwords.has(connection.id); }
function address(connection: DavConnection, path: string) {
  const base = new URL(connection.url);
  const url = new URL(path,base);
  const root = decodeURIComponent(base.pathname).replace(/\/?$/, '/');
  const decoded = decodeURIComponent(url.pathname);
  if (url.origin !== base.origin || url.username || url.password || url.search || url.hash || decoded.split('/').some(segment => segment === '..' || segment === '.') || decoded.includes('\\') || !(decoded === root.slice(0,-1) || decoded.startsWith(root))) throw new Error('invalid_path');
  return url.href;
}
async function request(connection: DavConnection, path: string, init: RequestInit) {
  const headers = new Headers(init.headers);
  if (connection.username) {
    if (!passwords.has(connection.id)) throw new Error('password_required');
    const bytes = new TextEncoder().encode(`${connection.username}:${passwords.get(connection.id)}`);
    headers.set('Authorization',`Basic ${btoa(Array.from(bytes,b=>String.fromCharCode(b)).join(''))}`);
  }
  const transfer = init.method === 'GET' || init.method === 'PUT';
  const timeout = AbortSignal.timeout(transfer ? 30 * 60 * 1000 : 15000);
  const signal = init.signal ? AbortSignal.any([init.signal, timeout]) : timeout;
  const res = await fetch(address(connection,path),{...init,headers,signal,credentials:'omit',redirect:'error'});
  if (!res.ok) throw new Error(res.status === 401 || res.status === 403 ? 'access_denied' : res.status === 412 ? 'file_exists' : `http_${res.status}`);
  return res;
}
export async function listDav(connection: DavConnection, path = connection.url): Promise<DavEntry[]> {
  const res = await request(connection,path,{method:'PROPFIND',headers:{Depth:'1','Content-Type':'application/xml'},body:'<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:resourcetype/><d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>'});
  const doc = new DOMParser().parseFromString(await res.text(),'application/xml');
  if (doc.querySelector('parsererror')) throw new Error('invalid_response');
  const current = new URL(address(connection,path)).pathname.replace(/\/$/,'');
  return Array.from(doc.getElementsByTagNameNS('DAV:','response')).flatMap(row=>{
    const value = (name: string) => row.getElementsByTagNameNS('DAV:',name)[0]?.textContent || '';
    const href=value('href'); if(!href)return [];
    const url=new URL(href,connection.url); if(url.pathname.replace(/\/$/,'')===current)return [];
    address(connection,url.href);
    return [{name:value('displayname') || decodeURIComponent(url.pathname.replace(/\/$/,'').split('/').pop() || ''),path:url.href,directory:!!row.getElementsByTagNameNS('DAV:','collection').length,size:Number(value('getcontentlength')) || 0,modified:value('getlastmodified')}];
  }).sort((a,b)=>Number(b.directory)-Number(a.directory)||a.name.localeCompare(b.name));
}
export async function createDavFolder(connection: DavConnection, path: string, name: string) { if(!name.trim() || /[\/\\]/.test(name) || ['.','..'].includes(name))throw new Error('invalid_name'); await request(connection,new URL(`${encodeURIComponent(name)}/`,path).href,{method:'MKCOL'}); }
export async function renameDavEntry(connection: DavConnection, entry: DavEntry, name: string) { if(!name.trim() || /[\/\\]/.test(name) || ['.','..'].includes(name))throw new Error('invalid_name'); const parent=new URL('.',entry.path.replace(/\/$/,''));const destination=new URL(encodeURIComponent(name)+(entry.directory?'/':''),parent).href;address(connection,destination);await request(connection,entry.path,{method:'MOVE',headers:{Destination:destination,Overwrite:'F'}}); }
export async function deleteDavEntry(connection: DavConnection, entry: DavEntry) { await request(connection,entry.path,{method:'DELETE'}); }
export async function uploadDav(connection: DavConnection, path: string, file: File, signal?: AbortSignal) { await request(connection,new URL(encodeURIComponent(file.name),path).href,{method:'PUT',headers:{'If-None-Match':'*'},body:file,signal}); }
export async function downloadDav(connection: DavConnection, entry: DavEntry, progress: (percent:number)=>void, signal?: AbortSignal) {
  const { createReceiveSink } = await import('./receiveFiles');
  const res=await request(connection,entry.path,{method:'GET',signal});const reader=res.body?.getReader();if(!reader)throw new Error('empty_response');const sink=await createReceiveSink(entry.name,res.headers.get('content-type') || undefined);let count=0;
  try { for(;;){const {value,done}=await reader.read();if(done)break;await sink.write(value);count+=value.byteLength;progress(entry.size?Math.min(99,count/entry.size*100):0);}await sink.finish();progress(100); }
  catch(e){await reader.cancel().catch(()=>{});await sink.abort().catch(()=>{});throw e;}finally{reader.releaseLock();}
}
export function davError(error: unknown, zh: boolean) { const key=error instanceof Error?(error.name === 'TimeoutError' ? 'timeout' : error.message):'';const map:Record<string,[string,string]>={preview_too_large:['文件较大，请下载后使用本机应用打开。','Download this larger file to open it locally.'],timeout:['连接超时，请检查网络后重试。','Connection timed out. Check your network and retry.'],access_denied:['请检查用户名、密码和访问权限。','Check your username, password and permissions.'],password_required:['请重新输入此连接的密码。','Enter the connection password again.'],invalid_url:['请输入有效的 WebDAV 地址，不要在地址中包含密码。','Enter a valid WebDAV URL without embedded credentials.'],file_exists:['已存在同名文件，请重命名后重试。','A file with this name exists. Rename and try again.'],invalid_name:['名称不能为空，也不能包含斜杠。','Enter a name without slashes.']};return map[key]?.[zh?0:1] || (zh?'连接未完成。请检查地址和网络，并确认服务允许浏览器跨域访问；也可使用桌面客户端。':'Connection failed. Check the address and network, and allow browser cross-origin access on the server, or use the desktop client.'); }

/** A bounded in-memory preview, never a received-file cache. */
export async function previewDav(connection: DavConnection, entry: DavEntry): Promise<File> {
  const limit = 32 * 1024 * 1024;
  if (entry.size > limit) throw new Error('preview_too_large');
  const res = await request(connection, entry.path, { method: 'GET' });
  const reader = res.body?.getReader();
  if (!reader) throw new Error('empty_response');
  const chunks: BlobPart[] = []; let size = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read(); if (done) break;
      size += value.byteLength; if (size > limit) throw new Error('preview_too_large');
      chunks.push(value);
    }
    return new File(chunks, entry.name, { type: res.headers.get('content-type')?.split(';')[0] || '', lastModified: Date.parse(entry.modified) || Date.now() });
  } catch(error) { await reader.cancel().catch(() => {}); throw error; }
  finally { reader.releaseLock(); }
}
