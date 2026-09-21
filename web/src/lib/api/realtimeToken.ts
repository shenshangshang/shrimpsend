import { logger } from '../logger';
import { getApiUrl, TAG, setDeviceAccessToken, deviceSessionRetry } from './client';
import { getOrCreateDeviceSecret } from '../deviceId';

export type RealtimeTokenResponse = {
  uid: string;
  token: string;
  websocketUrl: string;
  deviceFlag: number;
  deviceLevel: number;
  channelId: string;
  channelType: number;
  deviceAccessToken?: string;
};

export async function createDeviceSession(deviceId: string, platform = 'web'): Promise<RealtimeTokenResponse> {
  logger.info(TAG, 'createDeviceSession', deviceId, platform);
  const res = await fetch(`${getApiUrl()}/api/realtime/device-session`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      deviceId,
      deviceSecret: getOrCreateDeviceSecret(),
      platform,
    }),
  });
  if (!res.ok) {
    logger.warn(TAG, 'createDeviceSession failed', res.status);
    throw new Error('Failed to get realtime token');
  }
  const data = await res.json() as RealtimeTokenResponse;
  if (data.deviceAccessToken) {
    setDeviceAccessToken(data.deviceAccessToken);
    deviceSessionRetry.renew = async () => { await createDeviceSession(deviceId, platform); };
  }
  logger.info(TAG, 'createDeviceSession success uid=', data.uid, 'ws=', data.websocketUrl);
  return data;
}

export async function getRealtimeToken(deviceId: string, platform = 'web'): Promise<RealtimeTokenResponse> {
  return createDeviceSession(deviceId, platform);
}

/** @deprecated Billing credentials no longer grant transport access. */
export async function getRealtimeTokenWithUserJwt(deviceId: string, platform = 'web'): Promise<RealtimeTokenResponse> {
  return createDeviceSession(deviceId, platform);
}
