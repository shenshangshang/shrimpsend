import { logger } from '../logger';
import { getApiUrl, TAG, AuthError, getToken, getDeviceAccessToken, isAuthFailure, withAuthRetry } from './client';
import { DeviceSendRateLimitedError, publishDeviceSendQuota, readQuotaFromResponse } from './deviceSendQuota';

export type MessageEnvelope = {
  type: 'text' | 'file' | 'control' | 'lan_file_offer' | 'lan_pull_probe' | 'lan_pull_probe_result'
    | 'lan_http_probe' | 'lan_http_probe_result' | 'lan_pull_cancelled'
    | 'webrtc_probe' | 'webrtc_probe_result'
    | 'webrtc_offer' | 'webrtc_answer' | 'webrtc_ice_candidate' | 'webrtc_transfer_cancel'
    | 'device_pair_hello'
    | 'device_roster_patch';
  payload: unknown;
  fromDeviceId: string;
  ts: number;
  id?: number;
  toDeviceId?: string;
  threadKey?: string;
};

/** Local-only fields for optimistic UI and progress */
export type LocalStatus = 'sending' | 'uploading' | 'downloading' | 'sent' | 'failed' | 'cancelled';
export type ChatMessage = MessageEnvelope & {
  _localId?: string;
  _status?: LocalStatus;
  _progress?: number;
  _speed?: string;
};

export type MessageHistoryItem = MessageEnvelope & { id: number };

export async function getMessageHistory(limit = 50, before?: number, threadKey?: string): Promise<MessageHistoryItem[]> {
  return withAuthRetry(async () => {
    const token = getToken();
    if (!token) throw new Error('Not authenticated');
    const params = new URLSearchParams({ limit: String(limit) });
    if (before != null && before > 0) params.set('before', String(before));
    if (threadKey != null && threadKey !== '') params.set('threadKey', threadKey);
    const res = await fetch(`${getApiUrl()}/api/messages/history?${params}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (isAuthFailure(res)) throw new AuthError();
    if (!res.ok) {
      logger.warn(TAG, 'getMessageHistory failed', res.status);
      throw new Error('Failed to load history');
    }
    const list = (await res.json()) as MessageHistoryItem[];
    logger.info(TAG, 'getMessageHistory success count=', list.length);
    return list;
  });
}

export async function deleteMessage(id: number): Promise<void> {
  return withAuthRetry(async () => {
    const token = getToken();
    if (!token) throw new Error('Not authenticated');
    const res = await fetch(`${getApiUrl()}/api/messages/${id}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${token}` },
    });
    if (isAuthFailure(res)) throw new AuthError();
    if (!res.ok) {
      logger.warn(TAG, 'deleteMessage failed', res.status);
      throw new Error('Failed to delete message');
    }
    logger.debug(TAG, 'deleteMessage ok');
  });
}

export async function deleteThreadMessages(threadKey: string): Promise<void> {
  return withAuthRetry(async () => {
    const token = getToken();
    if (!token) throw new Error('Not authenticated');
    const params = new URLSearchParams({ threadKey });
    const res = await fetch(`${getApiUrl()}/api/messages/thread?${params}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${token}` },
    });
    if (isAuthFailure(res)) throw new AuthError();
    if (!res.ok) {
      logger.warn(TAG, 'deleteThreadMessages failed', res.status);
      throw new Error('Failed to clear messages');
    }
    logger.debug(TAG, 'deleteThreadMessages ok');
  });
}

export async function sendMessage(data: MessageEnvelope): Promise<void> {
  logger.info(TAG, 'sendMessage type=', data.type, 'fromDeviceId=', data.fromDeviceId);
  const userToken = getToken();
  if (userToken) {
    return withAuthRetry(async () => {
      const token = getToken();
      if (!token) throw new Error('Not authenticated');
      const res = await fetch(`${getApiUrl()}/api/messages/send`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({ data }),
      });
      if (isAuthFailure(res)) throw new AuthError();
      if (!res.ok) {
        logger.warn(TAG, 'sendMessage failed', res.status);
        throw new Error('Failed to send message');
      }
      logger.debug(TAG, 'sendMessage ok');
    });
  }
  const deviceToken = getDeviceAccessToken();
  if (!deviceToken) throw new Error('Not authenticated');
  const res = await fetch(`${getApiUrl()}/api/messages/device-send`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${deviceToken}` },
    body: JSON.stringify({ data }),
  });
  const quota = await readQuotaFromResponse(res);
  if (quota) publishDeviceSendQuota(quota);
  if (res.status === 429) {
    logger.warn(TAG, 'sendMessage device-send 429');
    throw new DeviceSendRateLimitedError(quota ?? { message: { used: 90, limit: 90, remaining: 0, retryAfterMs: 1000 }, signaling: { used: 0, limit: 600, remaining: 600, retryAfterMs: 0 }, kind: 'message', limited: true });
  }
  if (!res.ok) {
    logger.warn(TAG, 'sendMessage device-send failed', res.status);
    throw new Error('Failed to send message');
  }
  logger.debug(TAG, 'sendMessage device-send ok');
}

export async function pairDevice(peerDeviceId: string): Promise<void> {
  const deviceToken = getDeviceAccessToken();
  if (!peerDeviceId || !deviceToken) return;
  const res = await fetch(`${getApiUrl()}/api/devices/pair`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${deviceToken}` },
    body: JSON.stringify({ peerDeviceId }),
  });
  if (!res.ok) {
    logger.warn(TAG, 'pairDevice failed', res.status);
  }
}
