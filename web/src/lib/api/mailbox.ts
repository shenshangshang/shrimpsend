import { logger } from '../logger';
import { getApiUrl, TAG, AuthError, getToken, isAuthFailure, withAuthRetry } from './client';
import type { MessageEnvelope } from './messages';

export type MailboxPendingItem = {
  id: number;
  data: MessageEnvelope;
};

export async function getMailboxPending(deviceId: string, afterId = 0): Promise<MailboxPendingItem[]> {
  return withAuthRetry(async () => {
    const token = getToken();
    if (!token) throw new Error('Not authenticated');
    const params = new URLSearchParams({ deviceId });
    if (afterId > 0) params.set('afterId', String(afterId));
    const res = await fetch(`${getApiUrl()}/api/mailbox/pending?${params}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (isAuthFailure(res)) throw new AuthError();
    if (!res.ok) {
      logger.warn(TAG, 'getMailboxPending failed', res.status);
      throw new Error('Failed to load mailbox');
    }
    const list = (await res.json()) as MailboxPendingItem[];
    logger.info(TAG, 'getMailboxPending success count=', list.length);
    return list;
  });
}
