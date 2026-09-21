'use client';

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { useWukongim, type WukongimLifecycle } from '@/hooks/useWukongim';
import { getMailboxPending, type MessageEnvelope } from '@/lib/api';
import { getOrCreateDeviceId, getOrCreatePresenceSessionId } from '@/lib/deviceId';
import { logger } from '@/lib/logger';
import { getDeviceAccessToken } from '@/lib/api/client';

const TAG = 'Realtime';

type Handler = (data: MessageEnvelope) => void;

type RealtimeContextValue = {
  connected: boolean;
  subscribe: (handler: Handler) => () => void;
  presenceSessionId: string;
};

const RealtimeContext = createContext<RealtimeContextValue | null>(null);

export function RealtimeProvider({ children }: { children: ReactNode }) {
  const handlersRef = useRef(new Set<Handler>());
  const recentRef = useRef<MessageEnvelope[]>([]);
  const afterIdRef = useRef(0);
  const pollTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const [presenceSessionId] = useState(() => getOrCreatePresenceSessionId());

  const dispatch = useCallback((data: MessageEnvelope) => {
    recentRef.current = [...recentRef.current, data].slice(-50);
    handlersRef.current.forEach((h) => {
      try {
        h(data);
      } catch (e) {
        logger.warn(TAG, 'handler failed', e);
      }
    });
  }, []);

  const subscribe = useCallback((handler: Handler) => {
    recentRef.current.forEach((item) => {
      try {
        handler(item);
      } catch (e) {
        logger.warn(TAG, 'replay handler failed', e);
      }
    });
    handlersRef.current.add(handler);
    return () => {
      handlersRef.current.delete(handler);
    };
  }, []);

  const pollMailbox = useCallback(async () => {
    if (!getDeviceAccessToken()) return;
    try {
      const items = await getMailboxPending(getOrCreateDeviceId(), afterIdRef.current);
      for (const item of items) {
        if (item.id > afterIdRef.current) afterIdRef.current = item.id;
        if (item.data && typeof item.data === 'object') {
          dispatch(item.data);
        }
      }
    } catch (e) {
      logger.warn(TAG, 'mailbox poll failed', e);
    }
  }, [dispatch]);

  const lifecycle = useMemo<WukongimLifecycle>(
    () => ({
      onConnected: () => {
        void pollMailbox();
      },
    }),
    [pollMailbox],
  );

  const { connected } = useWukongim(
    true,
    dispatch,
    lifecycle,
    { deviceId: getOrCreateDeviceId() },
  );

  useEffect(() => {
    void pollMailbox();
    if (connected) return;
    pollTimerRef.current = setInterval(() => {
      void pollMailbox();
    }, 2000);
    return () => {
      if (pollTimerRef.current) {
        clearInterval(pollTimerRef.current);
        pollTimerRef.current = null;
      }
    };
  }, [connected, pollMailbox]);

  const value = useMemo<RealtimeContextValue>(
    () => ({ connected, subscribe, presenceSessionId }),
    [connected, subscribe, presenceSessionId],
  );

  return <RealtimeContext.Provider value={value}>{children}</RealtimeContext.Provider>;
}

export function useRealtime(): RealtimeContextValue {
  const ctx = useContext(RealtimeContext);
  if (!ctx) {
    throw new Error('useRealtime must be used within RealtimeProvider');
  }
  return ctx;
}
