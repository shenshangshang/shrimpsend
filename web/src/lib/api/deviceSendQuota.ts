import { getApiUrl, getDeviceAccessToken } from './client';

export type DeviceSendBucketQuota = {
  used: number;
  limit: number;
  remaining: number;
  retryAfterMs: number;
};

export type DeviceSendQuota = {
  message: DeviceSendBucketQuota;
  signaling: DeviceSendBucketQuota;
  kind?: string;
  limited?: boolean;
};

export class DeviceSendRateLimitedError extends Error {
  quota: DeviceSendQuota;
  constructor(quota: DeviceSendQuota) {
    super('rate_limited');
    this.name = 'DeviceSendRateLimitedError';
    this.quota = quota;
  }
}

type Listener = (quota: DeviceSendQuota) => void;
let listener: Listener | null = null;

export function setDeviceSendQuotaListener(fn: Listener | null): void {
  listener = fn;
}

export function publishDeviceSendQuota(quota: DeviceSendQuota): void {
  listener?.(quota);
}

function asInt(v: unknown, fallback: number): number {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string') {
    const n = Number.parseInt(v, 10);
    return Number.isFinite(n) ? n : fallback;
  }
  return fallback;
}

function bucketFromUnknown(raw: unknown, fallbackLimit: number): DeviceSendBucketQuota {
  const json = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : null;
  const limit = asInt(json?.limit, fallbackLimit);
  const used = asInt(json?.used, 0);
  const remaining = asInt(json?.remaining, Math.max(0, limit - used));
  return {
    used,
    limit,
    remaining,
    retryAfterMs: asInt(json?.retryAfterMs, 0),
  };
}

export function parseDeviceSendQuota(raw: unknown, limited = false): DeviceSendQuota | null {
  if (!raw || typeof raw !== 'object') return null;
  const json = raw as Record<string, unknown>;
  if (!('message' in json) && !('signaling' in json)) return null;
  return {
    message: bucketFromUnknown(json.message, 90),
    signaling: bucketFromUnknown(json.signaling, 600),
    kind: typeof json.kind === 'string' ? json.kind : undefined,
    limited: limited || json.error === 'rate_limited',
  };
}

export async function readQuotaFromResponse(res: Response): Promise<DeviceSendQuota | null> {
  const header = res.headers.get('X-Device-Send-Quota');
  if (header) {
    try {
      return parseDeviceSendQuota(JSON.parse(header), res.status === 429);
    } catch {
      /* fall through */
    }
  }
  try {
    const body = await res.clone().json();
    return parseDeviceSendQuota(body, res.status === 429);
  } catch {
    return null;
  }
}

export async function fetchDeviceQuota(): Promise<DeviceSendQuota | null> {
  const token = getDeviceAccessToken();
  if (!token) return null;
  const res = await fetch(`${getApiUrl()}/api/messages/device-quota`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) return null;
  return readQuotaFromResponse(res);
}

export function quotaRetrySeconds(quota: DeviceSendQuota): number {
  const ms =
    quota.kind === 'signaling' ? quota.signaling.retryAfterMs : quota.message.retryAfterMs;
  const fallback = Math.max(quota.message.retryAfterMs, quota.signaling.retryAfterMs);
  const chosen = ms > 0 ? ms : fallback;
  return Math.min(60, Math.max(1, Math.ceil(chosen / 1000)));
}
