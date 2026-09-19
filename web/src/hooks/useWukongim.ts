'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { getRealtimeToken } from '@/lib/api';
import type { MessageEnvelope } from '@/lib/api';
import { logger } from '@/lib/logger';
import { getApiUrl } from '@/lib/config';
import { unwrapWukongimPayload, rewriteLoopbackRealtimeWs } from '@/lib/wukongim';

const TAG = 'useWukongim';

export type WukongimLifecycle = {
  onConnected?: () => void;
  onDisconnected?: () => void;
};

export function useWukongim(
  enabled: boolean,
  onMessage: (data: MessageEnvelope) => void,
  lifecycle?: WukongimLifecycle,
  connectMeta?: { deviceId: string },
) {
  const [connected, setConnected] = useState(false);
  const [reconnectTick, setReconnectTick] = useState(0);
  const wsRef = useRef<WebSocket | null>(null);
  const onMessageRef = useRef(onMessage);
  const lifecycleRef = useRef(lifecycle);
  const mountedRef = useRef(true);
  const pingRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const rpcIdRef = useRef(0);
  const seenRef = useRef(new Set<string>());

  useEffect(() => {
    onMessageRef.current = onMessage;
  }, [onMessage]);
  useEffect(() => {
    lifecycleRef.current = lifecycle;
  }, [lifecycle]);

  const clearTimers = useCallback(() => {
    if (pingRef.current) {
      clearInterval(pingRef.current);
      pingRef.current = null;
    }
    if (reconnectTimerRef.current) {
      clearTimeout(reconnectTimerRef.current);
      reconnectTimerRef.current = null;
    }
  }, []);

  useEffect(() => {
    mountedRef.current = true;
    if (!enabled) return () => {};

    let cancelled = false;
    const prev = wsRef.current;
    if (prev) {
      prev.close();
      wsRef.current = null;
    }
    clearTimers();

    async function bootstrap() {
      let tokens;
      try {
        tokens = await getRealtimeToken(connectMeta?.deviceId ?? 'web', 'web');
      } catch (e) {
        logger.warn(TAG, 'getRealtimeToken failed, cannot connect:', e);
        if (!cancelled && mountedRef.current) {
          reconnectTimerRef.current = setTimeout(() => {
            if (mountedRef.current) setReconnectTick((n) => n + 1);
          }, 3000);
        }
        return;
      }
      if (cancelled || !mountedRef.current) return;

      const wsUrl = rewriteLoopbackRealtimeWs(tokens.websocketUrl, getApiUrl());
      const ws = new WebSocket(wsUrl);
      wsRef.current = ws;
      ws.onopen = () => {
        ws.send(JSON.stringify({
          method: 'connect',
          id: `c-${++rpcIdRef.current}`,
          params: {
            uid: tokens.uid,
            token: tokens.token,
            deviceId: connectMeta?.deviceId,
            deviceFlag: tokens.deviceFlag,
            clientTimestamp: Date.now(),
          },
        }));
      };
      ws.onmessage = (ev) => {
        let msg: Record<string, unknown>;
        try {
          msg = JSON.parse(String(ev.data)) as Record<string, unknown>;
        } catch {
          return;
        }
        if (msg.error) {
          logger.warn(TAG, 'rpc error', msg.error);
          return;
        }
        if (msg.result && msg.id) {
          logger.info(TAG, 'connected');
          if (mountedRef.current) setConnected(true);
          lifecycleRef.current?.onConnected?.();
          pingRef.current = setInterval(() => {
            if (ws.readyState === WebSocket.OPEN) {
              ws.send(JSON.stringify({ method: 'ping', id: `p-${++rpcIdRef.current}` }));
            }
          }, 60000);
          return;
        }
        if ((msg.method === 'recv' || msg.method === 'message') && msg.params && typeof msg.params === 'object') {
          const params = msg.params as { messageId?: unknown; payload?: unknown };
          const mid = params.messageId != null ? String(params.messageId) : '';
          if (mid) {
            if (seenRef.current.has(mid)) return;
            seenRef.current.add(mid);
            if (seenRef.current.size > 256) {
              const first = seenRef.current.values().next().value;
              if (first) seenRef.current.delete(first);
            }
          }
          const envelope = unwrapWukongimPayload(params.payload);
          if (envelope && typeof envelope === 'object') {
            onMessageRef.current(envelope as MessageEnvelope);
          }
        }
      };
      ws.onclose = () => {
        logger.info(TAG, 'disconnected');
        if (cancelled) return;
        if (mountedRef.current) setConnected(false);
        lifecycleRef.current?.onDisconnected?.();
        clearTimers();
        reconnectTimerRef.current = setTimeout(() => {
          if (mountedRef.current) setReconnectTick((n) => n + 1);
        }, 3000);
      };
      ws.onerror = () => logger.warn(TAG, 'ws error');
    }

    void bootstrap();

    function handleVisibilityChange() {
      if (document.visibilityState !== 'visible' || !mountedRef.current) return;
      const ws = wsRef.current;
      if (ws && ws.readyState === WebSocket.OPEN) return;
      logger.info(TAG, 'tab visible, reconnecting');
      setReconnectTick((n) => n + 1);
    }
    document.addEventListener('visibilitychange', handleVisibilityChange);

    return () => {
      cancelled = true;
      mountedRef.current = false;
      clearTimers();
      document.removeEventListener('visibilitychange', handleVisibilityChange);
      lifecycleRef.current?.onDisconnected?.();
      wsRef.current?.close();
      wsRef.current = null;
      setConnected(false);
    };
  }, [enabled, clearTimers, connectMeta?.deviceId, reconnectTick]);

  return { connected };
}
