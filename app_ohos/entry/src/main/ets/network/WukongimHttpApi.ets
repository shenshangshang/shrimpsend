import http from '@ohos.net.http';
import {
  apiUrl,
  checkAuthOk,
  requestWithAuthRetry
} from './HttpHelper';

export interface RealtimeTokenBundle {
  uid: string;
  token: string;
  websocketUrl: string;
  deviceFlag: number;
  channelId: string;
  channelType: number;
}

export class WukongimHttpApi {
  static async getToken(deviceId: string, platform: string = 'harmonyos'): Promise<RealtimeTokenBundle> {
    const q = `deviceId=${encodeURIComponent(deviceId)}&platform=${encodeURIComponent(platform)}`;
    const url = apiUrl(`/api/realtime/token?${q}`);
    const res = await requestWithAuthRetry(http.RequestMethod.GET, url, {
      'Content-Type': 'application/json'
    });
    await checkAuthOk(res, '获取连接凭证失败');
    const j = JSON.parse(res.body) as Record<string, Object>;
    const flagRaw = j['deviceFlag'];
    let flag = 0;
    if (typeof flagRaw === 'number') {
      flag = flagRaw as number;
    }
    return {
      uid: `${j['uid']}`,
      token: `${j['token']}`,
      websocketUrl: `${j['websocketUrl']}`,
      deviceFlag: flag,
      channelId: `${j['channelId']}`,
      channelType: 1
    };
  }
}
