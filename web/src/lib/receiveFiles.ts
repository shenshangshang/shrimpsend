/** Browser-managed Downloads by default; a chosen folder supports streaming. */
type WritableDirectory = FileSystemDirectoryHandle & {
  queryPermission(options: { mode: 'readwrite' }): Promise<PermissionState>;
};
type PickerWindow = Window & {
  showDirectoryPicker?: (options: { mode: 'readwrite'; startIn: 'downloads' }) => Promise<WritableDirectory>;
};

async function directoryStore(mode: IDBTransactionMode, value?: WritableDirectory | null): Promise<WritableDirectory | null> {
  return new Promise((resolve, reject) => {
    const open = indexedDB.open('shrimpsend-destination', 1);
    open.onupgradeneeded = () => open.result.createObjectStore('settings');
    open.onerror = () => reject(open.error);
    open.onsuccess = () => {
      const db = open.result;
      const tx = db.transaction('settings', mode);
      const store = tx.objectStore('settings');
      const request = mode === 'readonly' ? store.get('directory')
        : value ? store.put(value, 'directory') : store.delete('directory');
      tx.oncomplete = () => { db.close(); resolve(mode === 'readonly' ? request.result ?? null : value ?? null); };
      tx.onerror = () => { db.close(); reject(tx.error); };
    };
  });
}

export function canChooseReceiveDirectory(): boolean {
  return typeof window !== 'undefined' && typeof (window as PickerWindow).showDirectoryPicker === 'function';
}
export function receiveDirectoryLabel(): string | null {
  return typeof localStorage === 'undefined' ? null : localStorage.getItem('receive-directory-name');
}
export async function chooseReceiveDirectory(): Promise<string> {
  const picker = (window as PickerWindow).showDirectoryPicker;
  if (!picker) throw new Error('This browser uses its download settings.');
  const directory = await picker.call(window, { mode: 'readwrite', startIn: 'downloads' });
  await directoryStore('readwrite', directory);
  localStorage.setItem('receive-directory-name', directory.name);
  window.dispatchEvent(new Event('shrimpsend:receive-folder'));
  return directory.name;
}
export async function resetReceiveDirectory(): Promise<void> {
  await directoryStore('readwrite', null);
  localStorage.removeItem('receive-directory-name');
  window.dispatchEvent(new Event('shrimpsend:receive-folder'));
}

export type LocalFileEntry = { name: string; size: number; modified: number; handle: FileSystemFileHandle };
/** Enumerate only the folder the user explicitly selected for receiving. */
export async function listReceiveFiles(): Promise<LocalFileEntry[] | null> {
  const directory = await directoryStore('readonly');
  if (!directory) return null;
  if (await directory.queryPermission({ mode: 'readwrite' }) !== 'granted') throw new Error('folder_permission_required');
  const result: LocalFileEntry[] = [];
  const iterable = directory as WritableDirectory & { values(): AsyncIterableIterator<FileSystemHandle> };
  for await (const handle of iterable.values()) {
    if (handle.kind !== 'file') continue;
    const fileHandle = handle as FileSystemFileHandle;
    const file = await fileHandle.getFile();
    result.push({ name: file.name, size: file.size, modified: file.lastModified, handle: fileHandle });
  }
  return result.sort((a, b) => b.modified - a.modified);
}

export function downloadBlob(blob: Blob, name: string): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  a.click();
  // Some browsers start reading asynchronously after click returns.
  setTimeout(() => URL.revokeObjectURL(url), 60_000);
}

export interface ReceiveSink {
  write(data: Uint8Array<ArrayBuffer> | Blob): Promise<void>;
  finish(): Promise<void>;
  abort(): Promise<void>;
}

const reservedNames = new Set<string>();
export async function createReceiveSink(fileName: string, mimeType = 'application/octet-stream'): Promise<ReceiveSink> {
  const name = fileName.replaceAll('\\', '/').split('/').pop()?.replace(/[\x00-\x1f]/g, '_') || 'received';
  const directory = receiveDirectoryLabel() ? await directoryStore('readonly') : null;
  if (!directory) {
    const chunks: BlobPart[] = [];
    return {
      async write(data) { chunks.push(data); },
      async finish() { downloadBlob(new Blob(chunks, { type: mimeType }), name); chunks.length = 0; },
      async abort() { chunks.length = 0; },
    };
  }
  return createDirectoryReceiveSink(directory, name);
}

export async function createDirectoryReceiveSink(directory: WritableDirectory, fileName: string): Promise<ReceiveSink> {
  const leaf = fileName.replaceAll('\\', '/').split('/').pop()?.replace(/[\x00-\x1f]/g, '_') || 'received';
  const name = leaf === '.' || leaf === '..' ? 'received' : leaf;
  if (await directory.queryPermission({ mode: 'readwrite' }) !== 'granted') {
    throw new Error('请重新选择接收文件夹，以允许保存文件 / Select the receive folder again to allow saving.');
  }
  const dot = name.lastIndexOf('.');
  const stem = dot > 0 ? name.slice(0, dot) : name;
  const ext = dot > 0 ? name.slice(dot) : '';
  let candidate = name;
  for (let i = 0; ; i++) {
    candidate = i ? `${stem} (${i})${ext}` : name;
    if (reservedNames.has(candidate)) continue;
    reservedNames.add(candidate);
    try {
      await directory.getFileHandle(candidate);
      reservedNames.delete(candidate);
    } catch (e) {
      if (e instanceof DOMException && e.name === 'NotFoundError') break;
      if (e instanceof DOMException && e.name === 'TypeMismatchError') { reservedNames.delete(candidate); continue; }
      reservedNames.delete(candidate);
      throw e;
    }
  }
  try {
    const handle = await directory.getFileHandle(candidate, { create: true });
    const writable = await handle.createWritable();
    return {
      async write(data) { await writable.write(data); },
      async finish() { try { await writable.close(); } finally { reservedNames.delete(candidate); } },
      async abort() { try { await writable.abort(); } finally { reservedNames.delete(candidate); } },
    };
  } catch (e) { reservedNames.delete(candidate); throw e; }
}

export async function saveReceivedBlob(blob: Blob, fileName: string): Promise<void> {
  const sink = await createReceiveSink(fileName, blob.type);
  try { await sink.write(blob); await sink.finish(); }
  catch (e) { await sink.abort().catch(() => {}); throw e; }
}
