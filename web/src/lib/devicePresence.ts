import { fetchWithDeviceAuth, getApiUrl } from './api/client';
import { getDeviceName, getOrCreatePresenceSessionId, PENDING_DEVICE_NAME } from './deviceId';
export { mergePeerSnapshot } from './peerRoster';

let sequence = 0;
export async function publishDevicePresence(status: 'online' | 'offline'): Promise<void> {
  // Assign before any await, preserving pagehide/resume ordering.
  const order = ++sequence;
  const response = await fetchWithDeviceAuth(`${getApiUrl()}/api/devices/self/presence`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, keepalive: status === 'offline',
    signal: AbortSignal.timeout(8000),
    body: JSON.stringify({ sessionId: getOrCreatePresenceSessionId(), sequence: order, status, name: getDeviceName().slice(0, 80), platform: 'web' }),
  });
  if (!response.ok) throw new Error('Device presence unavailable');
  if (status === 'online') await syncDeviceName();
}

export async function syncDeviceName(): Promise<void> {
  const name = localStorage.getItem(PENDING_DEVICE_NAME);
  if (!name) return;
  const response = await fetchWithDeviceAuth(`${getApiUrl()}/api/devices/self/profile`, {
    method: 'PATCH', headers: { 'Content-Type': 'application/json' }, signal: AbortSignal.timeout(8000), body: JSON.stringify({ name }),
  });
  if (!response.ok) throw new Error('Device name sync unavailable');
  if (localStorage.getItem(PENDING_DEVICE_NAME) === name) localStorage.removeItem(PENDING_DEVICE_NAME);
}

