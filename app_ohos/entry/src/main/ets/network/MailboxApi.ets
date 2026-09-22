import http from '@ohos.net.http';
import {
  apiUrl, checkAuthOk, requestWithAuthRetry
} from './HttpHelper';
import { getOrCreateDeviceId } from '../storage/DeviceIdentity';

export interface MailboxPendingItem {
  id: number;
  data: Record<string, Object>;
}

export class MailboxApi {
  static async pending(afterId: number = 0): Promise<MailboxPendingItem[]> {
    const deviceId = await getOrCreateDeviceId();
    let q = `deviceId=${encodeURIComponent(deviceId)}`;
    if (afterId > 0) {
      q += `&afterId=${afterId}`;
    }
    const url = apiUrl(`/api/mailbox/pending?${q}`);
    const res = await requestWithAuthRetry(http.RequestMethod.GET, url, {
      'Content-Type': 'application/json'
    });
    await checkAuthOk(res, '加载待收信令失败');
    const arr = JSON.parse(res.body) as Object[];
    const out: MailboxPendingItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const item = arr[i] as Record<string, Object>;
      const idRaw = item['id'];
      let idNum = 0;
      if (typeof idRaw === 'number') {
        idNum = idRaw as number;
      }
      const dataRaw = item['data'];
      const data = (dataRaw !== undefined && typeof dataRaw === 'object')
        ? dataRaw as Record<string, Object>
        : {} as Record<string, Object>;
      out.push({ id: idNum, data: data });
    }
    return out;
  }
}
