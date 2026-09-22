import type { ChatMessage } from './api/messages';

/** Store message metadata only; received file bytes always go to the chosen folder. */
export function historyRecord(message: ChatMessage, deviceId: string): ChatMessage | null {
  if (!['text', 'file', 'lan_file_offer'].includes(message.type)) return null;
  if (message.fromDeviceId !== deviceId && message.toDeviceId && message.toDeviceId !== deviceId) return null;
  const copy = JSON.parse(JSON.stringify(message, (_key, value) => {
    if (typeof Blob !== 'undefined' && value instanceof Blob) return undefined;
    if (value instanceof ArrayBuffer || ArrayBuffer.isView(value)) return undefined;
    if (typeof value === 'string' && value.startsWith('blob:')) return undefined;
    return value;
  })) as ChatMessage;
  // Progress and memory-backed download links cannot survive a browser restart.
  delete copy._speed;
  delete copy._phase;
  if (['sending', 'uploading', 'downloading'].includes(copy._status ?? '')) copy._status = 'failed';
  return copy;
}

export function historyKey(m: ChatMessage): string {
  const payload = m.payload as { localId?: string } | undefined;
  return m._localId ?? payload?.localId ?? `${m.fromDeviceId}:${m.toDeviceId ?? ''}:${m.type}:${m.ts}`;
}

let database: Promise<IDBDatabase> | null = null;
function db(): Promise<IDBDatabase> {
  if (!database) database = new Promise((resolve, reject) => {
    const req = indexedDB.open('shrimpsend-device-history', 1);
    req.onupgradeneeded = () => {
      const store = req.result.createObjectStore('messages', { keyPath: 'id' });
      store.createIndex('device', 'device');
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => { database = null; reject(req.error); };
  });
  return database;
}
export async function loadDeviceHistory(deviceId: string): Promise<ChatMessage[]> {
  const store = (await db()).transaction('messages', 'readonly').objectStore('messages');
  return new Promise((resolve, reject) => {
    const req = store.index('device').getAll(deviceId);
    req.onsuccess = () => resolve(req.result.map(row => row.message as ChatMessage).sort((a,b) => a.ts-b.ts));
    req.onerror = () => reject(req.error);
  });
}
/** Only change rows changed by this tab, preserving independent writes from other tabs. */
export async function saveDeviceHistory(deviceId: string, current: ChatMessage[], previous: Map<string,string>): Promise<Map<string,string>> {
  const records = current.map(m => historyRecord(m, deviceId)).filter((m): m is ChatMessage => m !== null);
  const next = new Map(records.map(m => [historyKey(m), JSON.stringify(m)]));
  const tx = (await db()).transaction('messages', 'readwrite');
  const store = tx.objectStore('messages');
  for (const [key, json] of next) if (previous.get(key) !== json)
    store.put({ id: `${deviceId}:${key}`, device: deviceId, message: JSON.parse(json) });
  for (const key of previous.keys()) if (!next.has(key)) store.delete(`${deviceId}:${key}`);
  await new Promise<void>((resolve,reject) => { tx.oncomplete=()=>resolve(); tx.onerror=()=>reject(tx.error); tx.onabort=()=>reject(tx.error); });
  return next;
}
