export type CloudTransfer = { id: string; name: string; progress: number; status: 'active' | 'complete' | 'failed' | 'cancelled' };
type Work = (signal: AbortSignal, progress: (value: number) => void) => Promise<void>;
let snapshot: CloudTransfer[] = [];
const listeners = new Set<() => void>();
const controllers = new Map<string, AbortController>();
const retries = new Map<string, Work>();
export const readCloudTransfers = () => snapshot;
export const subscribeCloudTransfers = (fn: () => void) => { listeners.add(fn); return () => { listeners.delete(fn); }; };
function patch(id: string, value: Partial<CloudTransfer>) { snapshot = snapshot.map(row => row.id === id ? { ...row, ...value } : row); listeners.forEach(fn => fn()); }
async function run(id: string, work: Work) {
  const controller = new AbortController(); controllers.set(id,controller); patch(id,{status:'active',progress:0});
  try { await work(controller.signal,value => patch(id,{progress:value})); patch(id,{status:'complete',progress:100}); retries.delete(id); }
  catch { patch(id,{status:controller.signal.aborted?'cancelled':'failed'}); }
  finally { controllers.delete(id); }
}
export function startCloudTransfer(name: string, work: Work) {
  const id=crypto.randomUUID(); snapshot=[{id,name,progress:0,status:'active' as const},...snapshot]; retries.set(id,work); void run(id,work); return id;
}
export function cancelCloudTransfer(id: string) { controllers.get(id)?.abort(); }
export function retryCloudTransfer(id: string) { const work=retries.get(id); if(work&&!controllers.has(id))void run(id,work); }
