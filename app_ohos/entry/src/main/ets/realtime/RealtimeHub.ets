import { Env } from '../common/Env';
import { Log } from '../common/Logger';
import { ApiSession } from '../network/ApiSession';
import { CentrifugoHttpApi } from '../network/CentrifugoHttpApi';
import { MailboxApi } from '../network/MailboxApi';
import { CentrifugoClient } from './CentrifugoClient';

const TAG = 'RealtimeHub';

/** 登录后常驻的 Centrifugo 连接：断线退避重连 + mailbox 短轮询。 */
export class RealtimeHub {
  private static client: CentrifugoClient | null = null;
  private static wantConnected: boolean = false;
  private static reconnectAttempt: number = 0;
  private static reconnectTimer: number = -1;
  private static mailboxTimer: number = -1;
  private static mailboxAfterId: number = 0;
  private static connecting: boolean = false;
  private static listeners: Array<(channel: string, dataUtf8: string) => void> = [];

  static addListener(onPublication: (channel: string, dataUtf8: string) => void): void {
    RealtimeHub.listeners.push(onPublication);
  }

  static removeListener(onPublication: (channel: string, dataUtf8: string) => void): void {
    const next: Array<(channel: string, dataUtf8: string) => void> = [];
    for (let i = 0; i < RealtimeHub.listeners.length; i++) {
      if (RealtimeHub.listeners[i] !== onPublication) {
        next.push(RealtimeHub.listeners[i]);
      }
    }
    RealtimeHub.listeners = next;
  }

  static async connect(onPublication?: (channel: string, dataUtf8: string) => void): Promise<void> {
    if (onPublication !== undefined) {
      RealtimeHub.addListener(onPublication);
    }
    RealtimeHub.wantConnected = true;
    await RealtimeHub.openSocket();
    RealtimeHub.startMailboxPolling();
    await RealtimeHub.pollMailbox();
  }

  static async ensureConnected(): Promise<void> {
    if (!ApiSession.hasLogin()) {
      return;
    }
    RealtimeHub.wantConnected = true;
    if (RealtimeHub.client === null) {
      await RealtimeHub.openSocket();
    }
    await RealtimeHub.pollMailbox();
  }

  static disconnect(): void {
    RealtimeHub.wantConnected = false;
    RealtimeHub.clearReconnect();
    RealtimeHub.stopMailboxPolling();
    if (RealtimeHub.client !== null) {
      RealtimeHub.client.disconnect();
      RealtimeHub.client = null;
    }
  }

  private static dispatch(channel: string, dataUtf8: string): void {
    const copy = RealtimeHub.listeners;
    for (let i = 0; i < copy.length; i++) {
      try {
        copy[i](channel, dataUtf8);
      } catch (e) {
        Log.warn(TAG, 'listener fail %{public}s', JSON.stringify(e));
      }
    }
  }

  private static async openSocket(): Promise<void> {
    if (!RealtimeHub.wantConnected || RealtimeHub.connecting) {
      return;
    }
    if (!ApiSession.hasLogin()) {
      return;
    }
    RealtimeHub.connecting = true;
    try {
      const bundle = await CentrifugoHttpApi.getToken();
      if (!RealtimeHub.wantConnected) {
        return;
      }
      if (RealtimeHub.client !== null) {
        RealtimeHub.client.disconnect();
        RealtimeHub.client = null;
      }
      const c = new CentrifugoClient();
      RealtimeHub.client = c;
      c.connect(
        Env.centrifugoWs,
        bundle.connectionToken,
        bundle.channel,
        bundle.subscriptionToken,
        (channel: string, dataUtf8: string) => {
          RealtimeHub.dispatch(channel, dataUtf8);
        },
        () => {
          RealtimeHub.client = null;
          RealtimeHub.scheduleReconnect();
        }
      );
      RealtimeHub.reconnectAttempt = 0;
    } catch (e) {
      Log.warn(TAG, 'openSocket fail %{public}s', JSON.stringify(e));
      RealtimeHub.scheduleReconnect();
    } finally {
      RealtimeHub.connecting = false;
    }
  }

  private static scheduleReconnect(): void {
    if (!RealtimeHub.wantConnected) {
      return;
    }
    RealtimeHub.clearReconnect();
    const exp = RealtimeHub.reconnectAttempt > 4 ? 4 : RealtimeHub.reconnectAttempt;
    let delay = 500;
    for (let i = 0; i < exp; i++) {
      delay = delay * 2;
    }
    if (delay > 8000) {
      delay = 8000;
    }
    RealtimeHub.reconnectAttempt = RealtimeHub.reconnectAttempt + 1;
    Log.info(TAG, 'reconnect in %{public}d ms', delay);
    RealtimeHub.reconnectTimer = setTimeout(() => {
      RealtimeHub.reconnectTimer = -1;
      void RealtimeHub.openSocket();
    }, delay);
  }

  private static clearReconnect(): void {
    if (RealtimeHub.reconnectTimer !== -1) {
      clearTimeout(RealtimeHub.reconnectTimer);
      RealtimeHub.reconnectTimer = -1;
    }
  }

  private static startMailboxPolling(): void {
    if (RealtimeHub.mailboxTimer !== -1) {
      return;
    }
    RealtimeHub.mailboxTimer = setInterval(() => {
      void RealtimeHub.pollMailbox();
    }, 2000);
  }

  private static stopMailboxPolling(): void {
    if (RealtimeHub.mailboxTimer !== -1) {
      clearInterval(RealtimeHub.mailboxTimer);
      RealtimeHub.mailboxTimer = -1;
    }
  }

  private static async pollMailbox(): Promise<void> {
    if (!RealtimeHub.wantConnected || !ApiSession.hasLogin()) {
      return;
    }
    try {
      const items = await MailboxApi.pending(RealtimeHub.mailboxAfterId);
      for (let i = 0; i < items.length; i++) {
        const item = items[i];
        if (item.id > RealtimeHub.mailboxAfterId) {
          RealtimeHub.mailboxAfterId = item.id;
        }
        RealtimeHub.dispatch('', JSON.stringify(item.data));
      }
    } catch (e) {
      Log.warn(TAG, 'mailbox poll %{public}s', JSON.stringify(e));
    }
  }
}
