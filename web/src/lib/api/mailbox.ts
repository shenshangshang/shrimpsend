import { logger } from '../logger';
import { getApiUrl, TAG, getDeviceAccessToken, fetchWithDeviceAuth } from './client';
import type { MessageEnvelope } from './messages';

export type MailboxPendingItem = {
  id: number;
  data: MessageEnvelope;
};

export async function getMailboxPending(deviceId: string, afterId = 0): Promise<MailboxPendingItem[]> {
  if (!getDeviceAccessToken()) throw new Error('Not authenticated');
  const run = async () => {
    const params = new URLSearchParams({ deviceId });
    if (afterId > 0) params.set('afterId', String(afterId));
    const url = `${getApiUrl()}/api/mailbox/pending?${params}`;
    const res = await fetchWithDeviceAuth(url);
    if (!res.ok) {
      logger.warn(TAG, 'getMailboxPending failed', res.status);
      throw new Error('Failed to load mailbox');
    }
    const list = (await res.json()) as MailboxPendingItem[];
    logger.info(TAG, 'getMailboxPending success count=', list.length);
    return list;
  };
  return run();
}
