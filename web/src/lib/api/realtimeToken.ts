import { logger } from '../logger';
import { getApiUrl, TAG, AuthError, getToken, isAuthFailure, withAuthRetry } from './client';

export type RealtimeTokenResponse = {
  uid: string;
  token: string;
  websocketUrl: string;
  deviceFlag: number;
  deviceLevel: number;
  channelId: string;
  channelType: number;
};

export async function getRealtimeToken(deviceId: string, platform = 'web'): Promise<RealtimeTokenResponse> {
  logger.info(TAG, 'getRealtimeToken', deviceId, platform);
  return withAuthRetry(async () => {
    const token = getToken();
    if (!token) throw new Error('Not authenticated');
    const qs = new URLSearchParams({ deviceId, platform });
    const res = await fetch(`${getApiUrl()}/api/realtime/token?${qs}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (isAuthFailure(res)) throw new AuthError();
    if (!res.ok) {
      logger.warn(TAG, 'getRealtimeToken failed', res.status);
      throw new Error('Failed to get realtime token');
    }
    const data = await res.json() as RealtimeTokenResponse;
    logger.info(TAG, 'getRealtimeToken success uid=', data.uid, 'ws=', data.websocketUrl);
    return data;
  });
}
