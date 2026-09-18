import { BusinessError } from '@ohos.base';
import webSocket from '@ohos.net.webSocket';
import util from '@ohos.util';
import { Log } from '../common/Logger';

const TAG = 'WukongimWs';

export class WukongimClient {
  private ws: webSocket.WebSocket | null = null;
  private connectDone: boolean = false;
  private rpcId: number = 0;
  private pingTimer: number = -1;
  private onPublication: (dataUtf8: string) => void = () => {
  };
  private onClose: () => void = () => {
  };
  private stopping: boolean = false;

  connect(
    wsUrl: string,
    uid: string,
    token: string,
    deviceId: string,
    deviceFlag: number,
    onPublication: (dataUtf8: string) => void,
    onClose?: () => void
  ): void {
    this.disconnect();
    this.stopping = false;
    this.connectDone = false;
    this.onPublication = onPublication;
    if (onClose !== undefined) {
      this.onClose = onClose;
    }
    this.ws = webSocket.createWebSocket();
    this.ws.on('open', (err: BusinessError | null) => {
      if (err != null) {
        Log.error(TAG, 'open error %{public}s', JSON.stringify(err));
        return;
      }
      this.rpcId = this.rpcId + 1;
      this.sendJson({
        'method': 'connect',
        'id': `c-${this.rpcId}`,
        'params': {
          'uid': uid,
          'token': token,
          'deviceId': deviceId,
          'deviceFlag': deviceFlag,
          'clientTimestamp': Date.now()
        } as Record<string, Object>
      } as Record<string, Object>);
    });
    this.ws.on('message', (err: BusinessError | null, value: string | ArrayBuffer) => {
      if (err != null || value === undefined || value === null) {
        return;
      }
      const text = typeof value === 'string' ? value : WukongimClient.bufferToUtf8(value as ArrayBuffer);
      this.handleIncoming(text);
    });
    this.ws.on('close', () => {
      this.connectDone = false;
      this.stopPing();
      if (!this.stopping) {
        this.onClose();
      }
    });
    this.ws.connect(wsUrl, (err: BusinessError | null) => {
      if (err != null) {
        Log.error(TAG, 'connect failed %{public}s', JSON.stringify(err));
        if (!this.stopping) {
          this.onClose();
        }
      }
    });
  }

  disconnect(): void {
    this.stopping = true;
    this.stopPing();
    if (this.ws !== null) {
      try {
        this.ws.close();
      } catch (_) {
        // ignore
      }
      this.ws = null;
    }
    this.connectDone = false;
  }

  private sendJson(obj: Record<string, Object>): void {
    if (this.ws === null) {
      return;
    }
    try {
      this.ws.send(JSON.stringify(obj));
    } catch (e) {
      Log.error(TAG, 'send fail %{public}s', JSON.stringify(e));
    }
  }

  private handleIncoming(text: string): void {
    try {
      const j = JSON.parse(text) as Record<string, Object>;
      if (j['error'] !== undefined) {
        Log.error(TAG, 'rpc error %{public}s', JSON.stringify(j['error']));
        return;
      }
      if (j['result'] !== undefined && j['id'] !== undefined && !this.connectDone) {
        this.connectDone = true;
        this.startPing();
        Log.info(TAG, 'connected');
        return;
      }
      if ((`${j['method']}` === 'recv' || `${j['method']}` === 'message') && j['params'] !== undefined) {
        const params = j['params'] as Record<string, Object>;
        const envelope = WukongimClient.unwrapPayload(params['payload']);
        if (envelope.length > 0) {
          this.onPublication(envelope);
        }
      }
    } catch (e) {
      Log.warn(TAG, 'parse frame %{public}s', JSON.stringify(e));
    }
  }

  private startPing(): void {
    this.stopPing();
    this.pingTimer = setInterval(() => {
      this.rpcId = this.rpcId + 1;
      this.sendJson({ 'method': 'ping', 'id': `p-${this.rpcId}` } as Record<string, Object>);
    }, 60000);
  }

  private stopPing(): void {
    if (this.pingTimer !== -1) {
      clearInterval(this.pingTimer);
      this.pingTimer = -1;
    }
  }

  static unwrapPayload(payload: Object | undefined): string {
    if (payload === undefined || payload === null) {
      return '';
    }
    let decoded: Object = payload;
    if (typeof payload === 'string') {
      const s = payload as string;
      try {
        if (s.length > 0 && s.charAt(0) === '{') {
          decoded = JSON.parse(s) as Object;
        } else {
          const bytes = new util.Base64Helper().decodeSync(s);
          decoded = JSON.parse(WukongimClient.uint8ToUtf8(new Uint8Array(bytes))) as Object;
        }
      } catch (_) {
        return typeof payload === 'string' ? s : '';
      }
    }
    const map = decoded as Record<string, Object>;
    const type = map['type'];
    if (typeof type === 'number' && type === 200 && map['envelope'] !== undefined) {
      try {
        return JSON.stringify(map['envelope']);
      } catch (_) {
        return '';
      }
    }
    if (typeof type === 'string') {
      try {
        return JSON.stringify(map);
      } catch (_) {
        return '';
      }
    }
    return '';
  }

  private static bufferToUtf8(buf: ArrayBuffer): string {
    return WukongimClient.uint8ToUtf8(new Uint8Array(buf));
  }

  private static uint8ToUtf8(u8: Uint8Array): string {
    try {
      const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
      return decoder.decodeWithStream(u8);
    } catch (_) {
      let s = '';
      for (let i = 0; i < u8.length; i++) {
        s += String.fromCharCode(u8[i]);
      }
      return s;
    }
  }
}
