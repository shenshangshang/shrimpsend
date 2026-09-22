import { AuthError, fetchWithDeviceAuth, getApiUrl, getDeviceAccessToken, getToken, withAuthRetry } from './client';
import { createDeviceSession } from './realtimeToken';
import { getDeviceName, getOrCreateDeviceId } from '../deviceId';

export type LicenseRequest = { id: string; status: string; createdAt: string; expiresAt: string; deviceId: string | null; name: string | null; platform: string | null };
export type DeviceLicense = { deviceId: string; status: string; authorized: boolean; name: string | null; expiresAt: string | null; ownerLabel: string | null; pendingRequest: LicenseRequest | null };
export type LicenseDashboard = { capacity: number; used: number; boundCount: number; reserved: number; available: number; devices: { deviceId: string; name: string; platform: string; authorized: boolean; legacy: boolean; activatedAt: string; lastSeen: string | null }[]; requests: LicenseRequest[] };
export type IssuedLicense = { id: string; code: string; qrToken: string; expiresAt: string };

async function request<T>(path: string, owner: boolean, method = 'GET', body?: unknown): Promise<T> {
  const run = async () => {
    const url = `${getApiUrl()}/api/device-licenses${path}`;
    const init: RequestInit = { method, headers: { 'Content-Type': 'application/json' }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) };
    if (!owner && !getDeviceAccessToken()) await createDeviceSession(getOrCreateDeviceId());
    const res = owner
      ? await fetch(url, { ...init, headers: { ...init.headers, Authorization: `Bearer ${getToken()}` } })
      : await fetchWithDeviceAuth(url, init);
    if (owner && res.status === 401) throw new AuthError();
    if (!res.ok) {
      const error = await res.json().catch(() => ({}));
      throw new Error(error.error || 'license_request_failed');
    }
    return (res.status === 204 ? undefined : await res.json()) as T;
  };
  return owner ? withAuthRetry(run) : run();
}
export const getMyDeviceLicense = () => request<DeviceLicense>('/me', false);
export const releaseMyDeviceLicense = () => request<void>('/me', false, 'DELETE');
export const getLicenseDashboard = () => request<LicenseDashboard>('', true);
export const issueDeviceLicense = () => request<IssuedLicense>('/codes', true, 'POST');
export const approveDeviceLicense = (id: string) => request<LicenseDashboard>(`/requests/${encodeURIComponent(id)}/approve`, true, 'POST');
export const cancelDeviceLicense = (id: string) => request<void>(`/requests/${encodeURIComponent(id)}`, true, 'DELETE');
export const revokeDeviceLicense = (id: string) => request<void>(`/devices/${encodeURIComponent(id)}`, true, 'DELETE');
export const renameDeviceLicense = (id: string, name: string) => request<void>(`/devices/${encodeURIComponent(id)}`, true, 'PATCH', { name });
export function redeemDeviceLicense(input: string) {
  const value = input.trim();
  let token: string | null = null;
  try {
    const url = new URL(value);
    token = new URLSearchParams(url.hash.slice(1)).get('license');
    if ((url.protocol !== 'https:' && url.protocol !== 'http:') || !/^[A-Za-z0-9_-]{43}$/.test(token ?? '')) token = null;
  } catch { /* A manually entered short code. */ }
  return request<DeviceLicense>('/redeem', false, 'POST', {
    ...(token ? { qrToken: token } : { code: value.replace(/[\s-]/g, '').toUpperCase() }),
    name: getDeviceName(), platform: 'web',
  });
}
export function licenseLink(token: string) { return `${window.location.origin}/authorize#license=${encodeURIComponent(token)}`; }
export function licenseError(error: unknown, zh: boolean): string {
  const key = error instanceof Error ? error.message : '';
  const messages: Record<string, [string, string]> = {
    license_no_slots: ['没有可用名额，请先释放设备名额或购买设备服务包。', 'No slots available. Release a device or purchase a device plan.'],
    license_invalid_code: ['授权码无效、已使用或已过期，请生成新码。', 'The code is invalid, used or expired. Generate a new code.'],
    license_code_claimed: ['这个授权码已由另一台设备申请使用。', 'Another device has already claimed this code.'],
    license_device_already_bound: ['本机已有授权，请先解除原授权。', 'This device is already assigned. Release its current authorization first.'],
    license_membership_expired: ['此授权来源的会员已到期，请联系购买者续费。', 'The membership has expired. Ask the purchaser to renew.'],
    license_too_many_attempts: ['操作过于频繁，请稍后再试。', 'Too many attempts. Please try again later.'],
    license_request_failed: ['暂时无法连接授权服务，请稍后重试。', 'Cannot connect to the authorization service. Try again shortly.'],
  };
  return messages[key]?.[zh ? 0 : 1] ?? (zh ? '操作未完成，请检查连接后重试。' : 'Could not complete the action. Check your connection and retry.');
}
