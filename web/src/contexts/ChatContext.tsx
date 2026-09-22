'use client';
import { rememberPeerProfiles } from '@/lib/guestPeers';
import { publishDevicePresence, mergePeerSnapshot } from '@/lib/devicePresence';
import { DEVICE_NAME_CHANGED } from '@/lib/deviceId';

import { loadDeviceHistory, saveDeviceHistory, historyKey } from '@/lib/deviceHistory';
import { listPairedDevices } from '@/lib/api/devices';

import { createContext, useContext, useState, useCallback, useEffect, useMemo, useRef, type ReactNode } from 'react';
import { usePathname } from 'next/navigation';
import { useAuth } from '@/contexts/AuthContext';
import { useRealtime } from '@/contexts/RealtimeContext';
import { useSendTargetProbes, type DeviceReachEntry } from '@/hooks/useSendTargetProbes';
import { registerDevice, updateDevicePresence, sendMessage, pairDevice, getMessageHistory, deleteMessage, deleteThreadMessages, hasS3Config, checkS3Online, updateDevice, DeviceSendRateLimitedError } from '@/lib/api';
import type { DeviceDto, MessageEnvelope, ChatMessage } from '@/lib/api';
import { getOrCreateDeviceId, getDeviceName, getOrCreatePresenceSessionId, generateUUID } from '@/lib/deviceId';
import { logger } from '@/lib/logger';
import { belongsToConversation, mergeMessageHistory } from '@/lib/conversationMessages';
import {
  S3_VIRTUAL_DEVICE_ID,
  accountPartLoggedIn,
  outboundForWebChat,
  outboundForGuestChat,
  threadKeyForS3WebPersist,
  threadKeyOneToOne,
} from '@/lib/threadKey';

export { S3_VIRTUAL_DEVICE_ID };
import { trySendFileViaLan, probeHttpWeb, TRANSFER_STALL_TIMEOUT_MESSAGE } from '@/lib/fileTransfer';
import { isLikelyNetworkOrCorsError, reportCorsLikely } from '@/lib/network/corsAlert';
import { SpeedTracker } from '@/lib/speedTracker';
import { WebRTCManager, isWebRTCSignal } from '@/lib/webrtc';
import type { WebRTCSignal, FileMetadata } from '@/lib/webrtc';
import { S3TransferService } from '@/lib/services/s3Transfer';
import type { CloudTransferService } from '@/lib/services/cloudTransfer';
import { transferStateManager } from '@/lib/services/transferStateManager';
import { runWithConcurrency, AsyncSemaphore } from '@/lib/concurrency';
import {
  loadSelectedTargets,
  persistSelectedTargets,
} from '@/lib/sendTargetStorage';
import {
  applicableTransferHops,
  isLanFileOfferForMe,
  TransferHopSkipCache,
  type TransferPhase,
  type TransferChannel,
} from '@/lib/transferPathCascade';
import { normalizeMessageLocalId, rowMatchesLocalId } from '@/lib/chatMessageDedupe';
import { loadAutoCopyIncomingText } from '@/lib/autoCopyPreferences';
import {
  loadGuestPeers,
  upsertGuestPeer,
  guestPeerToDeviceDto,
  mergeDeviceRosters,
} from '@/lib/guestPeers';
import { normalizePeerDeviceId, shortDeviceLabel } from '@/lib/devicePair';
import { toast } from 'sonner';

/** Single-line preview capped at 20 chars (ellipsised when longer) for the auto-copy toast. */
function autoCopyPreview(text: string): string {
  const oneLine = text.replace(/\s+/g, ' ').trim();
  return oneLine.length <= 20 ? oneLine : `${oneLine.slice(0, 20)}…`;
}
import { useI18n } from '@/contexts/I18nContext';
import { analyticsLengthBucket, analyticsTrack } from '@/lib/analytics';
import { AnalyticsEvents } from '@/lib/analyticsEvents';
import { isWebPeer } from '@/lib/peerPlatform';
import { filePayloadTransferChannel } from '@/lib/filePayload';
import { createReceiveSink, saveReceivedBlob, type ReceiveSink } from '@/lib/receiveFiles';
import { downloadS3FileAsBrowserSave } from '@/lib/downloadS3File';
import { classifyDevice } from '@/lib/probePriority';
import {
  type ConnectionDiagnosticState,
  buildDiagnosticSummary,
  diagnosticStepOrder,
  diagnosticStepTitle,
  peerLabelForDevice,
  isPeerWebDevice,
  runConnectionDiagnostic,
} from '@/lib/connectionDiagnostic';

const TAG = 'ChatContext';
const MAX_PARALLEL_FILE_SENDS = 3;
const cloudTransfer: CloudTransferService = new S3TransferService();
const CHAT_PAGE_SIZE = 20;
const EPHEMERAL_TYPES = new Set([
  'lan_file_offer', 'lan_pull_probe', 'lan_pull_probe_result',
  'lan_http_probe', 'lan_http_probe_result', 'lan_pull_cancelled',
  'webrtc_probe', 'webrtc_probe_result',
  'webrtc_offer', 'webrtc_answer', 'webrtc_ice_candidate', 'webrtc_transfer_cancel',
  'device_pair_hello',
]);

function isProgressOnlyPatch(patch: Partial<ChatMessage>): boolean {
  const ks = Object.keys(patch);
  if (ks.length === 0) return false;
  return ks.every((k) => k === '_progress' || k === '_speed');
}

export type ChatContextValue = {
  // Connection
  connected: boolean;

  // Devices
  devices: DeviceDto[];
  currentDeviceId: string;
  otherDevices: DeviceDto[];
  lanDevices: DeviceDto[];
  refreshDevices: () => void;

  // Selected device for conversation
  selectedDeviceId: string | null;
  setSelectedDeviceId: (id: string | null) => void;

  // Targets
  selectedTargets: Set<string>;
  toggleTarget: (deviceId: string) => void;

  // Probes
  deviceReach: Record<string, DeviceReachEntry>;
  targetsProbing: boolean;
  refreshSendTargets: () => void;
  probeSingleDevice: (deviceId: string) => void;
  runSessionConnectionDiagnostic: (deviceId: string) => void;

  // Connection diagnostic sheet
  connectionDiagnostic: ConnectionDiagnosticState | null;
  diagnosticSheetOpen: boolean;
  setDiagnosticSheetOpen: (open: boolean) => void;

  // Messages
  messages: ChatMessage[];
  sendTextMessage: (text: string) => Promise<void>;
  sending: boolean;
  sendError: string | null;
  setSendError: (e: string | null) => void;
  fileError: string | null;
  setFileError: (e: string | null) => void;

  // File sending
  pendingFiles: File[];
  setPendingFiles: React.Dispatch<React.SetStateAction<File[]>>;
  handleSendFiles: () => void;
  handleFileSelect: (e: React.ChangeEvent<HTMLInputElement>) => void;
  addPendingFiles: (files: File[]) => void;
  removePendingFile: (index: number) => void;

  // Message management
  handleDeleteMessage: (msg: ChatMessage) => Promise<void>;
  cancelTransfer: (localId: string) => void;
  handleRetryText: (localId: string) => void;
  handleRetryFile: (localId: string) => void;

  // Message list scroll
  loadMoreMessages: () => Promise<void>;
  loadingMore: boolean;

  // Multi-select
  selectMode: boolean;
  selectedKeys: Set<string>;
  toggleMessageSelect: (key: string) => void;
  exitSelectMode: () => void;
  toggleSelectAllMessages: () => void;
  enterSelectWithKey: (key: string) => void;
  handleBulkDelete: () => Promise<void>;
  clearCurrentThreadMessages: () => Promise<void>;

  // WebRTC availability
  webrtcAvailable: boolean;

  /** True when the browser has no user JWT (guest transfer). */
  isGuest: boolean;
  addPeerByDeviceId: (raw: string) => Promise<void>;

  // S3 cloud relay
  s3Configured: boolean;
  s3Online: boolean;
  s3Checking: boolean;
  checkS3Config: () => Promise<void>;
};

const ChatContext = createContext<ChatContextValue | null>(null);

export function useChatContext(): ChatContextValue {
  const ctx = useContext(ChatContext);
  if (!ctx) throw new Error('useChatContext must be used within ChatProvider');
  return ctx;
}

const S3_CONFIG_RETRY_DELAY_MS = 500;

export function ChatProvider({ children }: { children: ReactNode }) {
  const { userId, accessToken } = useAuth();
  const { t } = useI18n();
  const pathname = usePathname();
  const prevOnS3SettingsRef = useRef(false);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const pendingPatchesRef = useRef<Map<string, Partial<ChatMessage>>>(new Map());
  const rafFlushingRef = useRef<number | null>(null);
  const pullSemaphoreRef = useRef(new AsyncSemaphore(3));
  const cancelledTransferIdsRef = useRef(new Set<string>());
  const hopSkipCacheRef = useRef(new TransferHopSkipCache());
  const sendSingleFileRef = useRef<(file: File, useLan: boolean, targetDevices: DeviceDto[], opts?: { reportTerminalFailure?: boolean; reuseLocalId?: string }) => Promise<boolean>>(async () => false);
  const sendFilesViaWebRTCRef = useRef<(files: File[], targetDeviceId: string, opts?: { fallbackS3?: boolean; reportTerminalFailure?: boolean; reuseLocalId?: string }) => Promise<boolean>>(async () => false);

  const [devices, setDevices] = useState<DeviceDto[]>([]);
  const [selectedTargets, setSelectedTargets] = useState<Set<string>>(() => new Set());
  const [selectedDeviceId, setSelectedDeviceId] = useState<string | null>(null);
  const userIdRef = useRef<string | null>(null);
  const selectedDeviceIdRef = useRef<string | null>(null);
  const selectedPeerReachSnapshotRef = useRef<{
    presence: string;
    lanHttpUrl: string;
  } | null>(null);
  userIdRef.current = userId;
  selectedDeviceIdRef.current = selectedDeviceId;
  const [targetProbeToken, setTargetProbeToken] = useState(0);
  const [probeForceAll, setProbeForceAll] = useState(false);
  const storageHydratedRef = useRef(false);
  const presenceSessionId = useMemo(() => getOrCreatePresenceSessionId(), []);
  const activeTransfersRef = useRef<Map<string, AbortController>>(new Map());
  const speedTrackersRef = useRef<Map<string, SpeedTracker>>(new Map());
  const webrtcManagerRef = useRef<WebRTCManager | null>(null);
  const webrtcFileLocalIdMap = useRef<Map<string, string>>(new Map());
  const webrtcFileSizeMap = useRef<Map<string, number>>(new Map());
  const pendingLanHttpProbesRef = useRef<Map<string, (result: { success: boolean; lanHttpUrl?: string; senderReachable?: boolean }) => void>>(new Map());
  const pendingPullProbesRef = useRef<Map<string, (success: boolean) => void>>(new Map());
  const seenLanOfferIdsRef = useRef(new Set<string>());
  const diagnosticSessionRef = useRef(0);

  const [connectionDiagnostic, setConnectionDiagnostic] = useState<ConnectionDiagnosticState | null>(null);
  const [diagnosticSheetOpen, setDiagnosticSheetOpen] = useState(false);

  type RetryInfo = { file: File; channel: 'lan' | 's3' | 'webrtc'; targetDevices: DeviceDto[]; webrtcTargetDeviceId?: string };
  const retryInfoRef = useRef<Map<string, RetryInfo>>(new Map());
  /** Server row ids (`${ts}_${fromDeviceId}`) that already triggered realtime S3 auto-download. */
  const autoDownloadedS3Ref = useRef(new Set<string>());

  const [sending, setSending] = useState(false);
  const [sendError, setSendError] = useState<string | null>(null);
  const [fileError, setFileError] = useState<string | null>(null);
  const [pendingFiles, setPendingFiles] = useState<File[]>([]);
  const [loadingMore, setLoadingMore] = useState(false);
  const loadingMoreRef = useRef(false);
  const hasNoMoreRef = useRef(false);
  const [selectMode, setSelectMode] = useState(false);
  const [selectedKeys, setSelectedKeys] = useState<Set<string>>(() => new Set());
  const [s3Configured, setS3Configured] = useState(false);
  const [s3Online, setS3Online] = useState(false);
  const [s3Checking, setS3Checking] = useState(false);
  const checkS3SeqRef = useRef(0);
  const s3OnlineRef = useRef(false);
  s3OnlineRef.current = s3Online;

  const currentDeviceId = getOrCreateDeviceId();

  if (!webrtcManagerRef.current) {
    webrtcManagerRef.current = new WebRTCManager();
  }

  const [historyLoaded, setHistoryLoaded] = useState(false);
  const historySnapshot = useRef(new Map<string,string>());
  const historyWrites = useRef(Promise.resolve());
  useEffect(() => {
    let cancelled = false;
    void loadDeviceHistory(currentDeviceId).then(saved => {
      if (cancelled) return;
      historySnapshot.current = new Map(saved.map(m => [historyKey(m),JSON.stringify(m)]));
      setMessages(current => {
        const map = new Map(saved.map(m => [historyKey(m),m]));
        for (const m of current) map.set(historyKey(m),m);
        return [...map.values()].sort((a,b) => a.ts-b.ts);
      });
    }).catch(error => logger.warn(TAG,'local history unavailable',error))
      .finally(() => { if (!cancelled) setHistoryLoaded(true); });
    return () => { cancelled = true; };
  }, [currentDeviceId]);
  useEffect(() => {
    if (!historyLoaded) return;
    // Start the transaction promptly, so navigating away after sending does not lose the row.
    historyWrites.current = historyWrites.current.then(async () => {
      historySnapshot.current = await saveDeviceHistory(currentDeviceId,messages,historySnapshot.current);
    }).catch(error => logger.warn(TAG,'local history save failed',error));
  }, [messages,historyLoaded,currentDeviceId]);

  // ─── Message update helpers ───────────────────────────────────────────

  const flushProgressPatches = useCallback(() => {
    rafFlushingRef.current = null;
    const pending = pendingPatchesRef.current;
    if (pending.size === 0) return;
    pendingPatchesRef.current = new Map();
    setMessages((prev) => {
      let changed = false;
      const next = [...prev];
      for (const [localId, patch] of pending) {
        const idx = next.findIndex((m) => rowMatchesLocalId(m, localId));
        if (idx < 0) continue;
        changed = true;
        next[idx] = { ...next[idx], ...patch };
      }
      return changed ? next : prev;
    });
  }, []);

  const updateMessageByLocalId = useCallback(
    (localId: string, patch: Partial<ChatMessage>) => {
      if (!isProgressOnlyPatch(patch)) {
        if (rafFlushingRef.current != null) {
          cancelAnimationFrame(rafFlushingRef.current);
          rafFlushingRef.current = null;
        }
        const snap = pendingPatchesRef.current;
        pendingPatchesRef.current = new Map();
        snap.delete(localId);
        setMessages((prev) => {
          const next = [...prev];
          let changed = false;
          const apply = (id: string, p: Partial<ChatMessage>) => {
            const idx = next.findIndex((m) => rowMatchesLocalId(m, id));
            if (idx < 0) return;
            next[idx] = { ...next[idx], ...p };
            changed = true;
          };
          for (const [id, p] of snap) apply(id, p);
          apply(localId, patch);
          return changed ? next : prev;
        });
        return;
      }
      pendingPatchesRef.current.set(localId, { ...pendingPatchesRef.current.get(localId), ...patch });
      if (rafFlushingRef.current == null) {
        rafFlushingRef.current = requestAnimationFrame(() => flushProgressPatches());
      }
    },
    [flushProgressPatches],
  );

  // ─── WebRTC Manager callbacks ─────────────────────────────────────────

  useEffect(() => {
    const mgr = webrtcManagerRef.current;
    if (!mgr) return;

    mgr.onProgress = (fileId, received, total) => {
      const localId = webrtcFileLocalIdMap.current.get(fileId);
      if (!localId) return;
      const pct = total > 0 ? Math.min(Math.round((received / total) * 100), 100) : 0;
      const tracker = speedTrackersRef.current.get(localId);
      if (tracker) tracker.update(received);
      updateMessageByLocalId(localId, { _progress: pct, _speed: tracker?.formatted });
    };

    mgr.onFileReceived = (fileId, fileName, blob) => {
      const localId = webrtcFileLocalIdMap.current.get(fileId) ?? generateUUID();
      webrtcFileLocalIdMap.current.delete(fileId);
      const fileSize = webrtcFileSizeMap.current.get(fileId);
      webrtcFileSizeMap.current.delete(fileId);
      speedTrackersRef.current.delete(localId);
      if (blob) void saveReceivedBlob(blob, fileName);
      updateMessageByLocalId(localId, {
        _status: 'sent',
        _progress: undefined,
        _speed: undefined,
        _phase: undefined,
        _transferType: 'webrtc',
        payload: { fileName, webrtc: true, ...(fileSize != null && fileSize > 0 ? { size: fileSize } : {}) },
      });
      logger.info(TAG, 'WebRTC file received', fileName);
    };

    mgr.onFileSent = (fileId, fileName) => {
      const localId = webrtcFileLocalIdMap.current.get(fileId);
      if (!localId) return;
      webrtcFileLocalIdMap.current.delete(fileId);
      const fileSize = webrtcFileSizeMap.current.get(fileId);
      webrtcFileSizeMap.current.delete(fileId);
      speedTrackersRef.current.delete(localId);
      const targetDeviceId = retryInfoRef.current.get(localId)?.webrtcTargetDeviceId;
      retryInfoRef.current.delete(localId);
      updateMessageByLocalId(localId, {
        _status: 'sent',
        _progress: undefined,
        _speed: undefined,
        _phase: undefined,
        _transferType: 'webrtc',
        payload: { fileName, webrtc: true, ...(fileSize != null && fileSize > 0 ? { size: fileSize } : {}) },
      });
      const uid = userIdRef.current;
      const me = getOrCreateDeviceId();
      let threadKey: string;
      let toDeviceId: string | undefined;
      if (targetDeviceId) {
        if (!uid) return;
        threadKey = threadKeyOneToOne(accountPartLoggedIn(uid), me, targetDeviceId);
        toDeviceId = targetDeviceId;
      } else {
        const peer = selectedDeviceIdRef.current;
        if (!uid || !peer) return;
        const o = outboundForWebChat(uid, peer, me);
        if (!o) return;
        threadKey = o.threadKey;
        toDeviceId = o.toDeviceId;
      }
      sendMessage({
        type: 'file',
        payload: { fileName, webrtc: true, localId, ...(fileSize != null && fileSize > 0 ? { size: fileSize } : {}), ...(targetDeviceId ? { targetDeviceId } : {}) },
        fromDeviceId: me,
        ts: Date.now(),
        threadKey,
        ...(toDeviceId != null ? { toDeviceId } : {}),
      }).catch((e) => logger.warn(TAG, 'WebRTC sendMessage persist failed', e));
      logger.info(TAG, 'WebRTC file sent', fileName);
    };

    mgr.onFileFailed = (fileId, fileName, error) => {
      const localId = webrtcFileLocalIdMap.current.get(fileId);
      if (!localId) return;
      webrtcFileLocalIdMap.current.delete(fileId);
      webrtcFileSizeMap.current.delete(fileId);
      speedTrackersRef.current.delete(localId);
      if (error.includes('Transfer cancelled')) cancelledTransferIdsRef.current.add(localId);
      updateMessageByLocalId(localId, { _status: error.includes('Transfer cancelled') ? 'cancelled' : 'failed', _progress: undefined, _speed: undefined });
      logger.warn(TAG, 'WebRTC file failed', fileName, error);
    };

    mgr.onStateChange = (sessionId, state) => {
      logger.info(TAG, `WebRTC session=${sessionId} state=${state}`);
    };

    return () => {
      mgr.onProgress = null;
      mgr.onFileReceived = null;
      mgr.onFileSent = null;
      mgr.onFileFailed = null;
      mgr.onStateChange = null;
    };
  }, [updateMessageByLocalId]);

  // ─── Transfer helpers ─────────────────────────────────────────────────

  const cancelTransfer = useCallback((localId: string) => {
    cancelledTransferIdsRef.current.add(localId);
    const controller = activeTransfersRef.current.get(localId);
    if (controller) {
      controller.abort();
      activeTransfersRef.current.delete(localId);
    }
    for (const [fileId, mappedId] of webrtcFileLocalIdMap.current) {
      if (mappedId === localId) webrtcManagerRef.current?.cancelTransferByFileId(fileId);
    }
    updateMessageByLocalId(localId, { _status: 'cancelled', _progress: undefined, _speed: undefined });
  }, [updateMessageByLocalId]);

  const pullFileFromOffer = useCallback(async (
    pullUrl: string,
    fileName: string,
    fileSize?: number,
    opts?: { localId?: string; fromDeviceId?: string },
  ) => {
    const sem = pullSemaphoreRef.current;
    await sem.acquire();
    const localId = opts?.localId ?? generateUUID();
    const fromPeer = opts?.fromDeviceId;
    const placeholder: ChatMessage = {
      type: 'file',
      payload: { fileName, lan: true, localId },
      fromDeviceId: fromPeer ?? 'system',
      ts: Date.now(),
      _localId: localId,
      _status: 'downloading',
      _progress: 0,
    };
    setMessages((prev) => {
      const idx = prev.findIndex((m) => rowMatchesLocalId(m, localId));
      if (idx < 0) return [...prev, placeholder];
      const cur = prev[idx] as ChatMessage;
      const curPl =
        cur.payload && typeof cur.payload === 'object' ? (cur.payload as Record<string, unknown>) : {};
      const mergedPayload = {
        ...curPl,
        fileName: (curPl.fileName as string | undefined) ?? fileName,
        lan: true,
        localId,
      };
      const next = [...prev];
      next[idx] = {
        ...cur,
        type: 'file',
        payload: mergedPayload,
        fromDeviceId: fromPeer ?? cur.fromDeviceId,
        _localId: localId,
        _status: 'downloading',
        _progress: 0,
      };
      return next;
    });
    const pullTracker = new SpeedTracker();
    speedTrackersRef.current.set(localId, pullTracker);
    let receiveSink: ReceiveSink | undefined;
    let pullTimer: ReturnType<typeof setTimeout> | undefined;
    const pullAbort = new AbortController();
    activeTransfersRef.current.set(localId, pullAbort);
    try {
      pullTimer = setTimeout(() => pullAbort.abort(), 3_600_000);
      let resp: Response;
      try {
        resp = await fetch(pullUrl, { signal: pullAbort.signal });
      } catch (fetchErr) {
        if (isLikelyNetworkOrCorsError(fetchErr)) {
          reportCorsLikely({ url: pullUrl, mode: 'download', channel: 'lan', cause: fetchErr });
        }
        throw fetchErr;
      }
      if (!resp.ok) throw new Error(`Server returned ${resp.status}`);
      const respFileName = resp.headers.get('X-File-Name');
      const name = respFileName ? decodeURIComponent(respFileName) : fileName;
      const totalSize = parseInt(resp.headers.get('X-File-Size') ?? '0', 10) || fileSize || 0;
      const reader = resp.body?.getReader();
      if (!reader) throw new Error('No response body');
      receiveSink = await createReceiveSink(name);
      let received = 0;
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        await receiveSink.write(new Uint8Array(value));
        received += value.byteLength;
        if (totalSize > 0) {
          pullTracker.update(received);
          const pct = Math.min(Math.round((received / totalSize) * 100), 100);
          updateMessageByLocalId(localId, { _progress: pct, _speed: pullTracker.formatted });
        }
      }
      speedTrackersRef.current.delete(localId);
      if (totalSize > 0 && received !== totalSize) throw new Error(`Incomplete file: ${received}/${totalSize}`);
      await receiveSink.finish();
      updateMessageByLocalId(localId, {
        _status: 'sent',
        _progress: undefined,
        _speed: undefined,
        payload: { fileName: name, lan: true, ...(localId ? { localId } : {}) },
      });
      logger.info(TAG, 'pullFileFromOffer downloaded', name);
    } catch (e) {
      await receiveSink?.abort().catch(() => {});
      const msg = e instanceof Error ? e.message : t('chat.pullFailed');
      logger.warn(TAG, 'pullFileFromOffer failed', msg, 'pullUrl=', pullUrl);
      speedTrackersRef.current.delete(localId);
      updateMessageByLocalId(localId, { _status: pullAbort.signal.aborted ? 'cancelled' : 'failed', _progress: undefined });
    } finally {
      activeTransfersRef.current.delete(localId);
      clearTimeout(pullTimer);
      sem.release();
    }
  }, [updateMessageByLocalId, t]);

  const handlePullProbe = useCallback(async (probeUrl: string, probeId: string, fromDeviceId: string) => {
    const success = await probeHttpWeb(probeUrl, 3000);
    logger.info(TAG, 'handlePullProbe probeId=', probeId, 'success=', success);
    try {
      await sendMessage({ type: 'lan_pull_probe_result', payload: { probeId, success }, fromDeviceId: getOrCreateDeviceId(), toDeviceId: fromDeviceId, ts: Date.now() });
    } catch (e) {
      logger.warn(TAG, 'handlePullProbe sendResult failed', e);
    }
  }, []);

  const sendLanHttpProbe = useCallback(async (targetDeviceId: string): Promise<{ success: boolean; lanHttpUrl?: string; senderReachable?: boolean }> => {
    const probeId = generateUUID();
    const myId = getOrCreateDeviceId();
    const selfLanUrl = devices.find((d) => d.deviceId === myId)?.lanHttpUrl ?? null;
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        pendingLanHttpProbesRef.current.delete(probeId);
        resolve({ success: false });
      }, 5000);
      pendingLanHttpProbesRef.current.set(probeId, (result) => {
        clearTimeout(timer);
        pendingLanHttpProbesRef.current.delete(probeId);
        resolve(result);
      });
      sendMessage({ type: 'lan_http_probe', payload: { probeId, targetDeviceId, senderLanHttpUrl: selfLanUrl }, fromDeviceId: myId, toDeviceId: targetDeviceId, ts: Date.now() }).catch(() => {
        clearTimeout(timer);
        pendingLanHttpProbesRef.current.delete(probeId);
        resolve({ success: false });
      });
    });
  }, [devices]);

  const sendPullProbe = useCallback(async (targetDeviceId: string): Promise<boolean> => {
    const myId = getOrCreateDeviceId();
    const selfLanUrl = devices.find((d) => d.deviceId === myId)?.lanHttpUrl?.trim();
    if (!selfLanUrl) return false;
    const probeId = generateUUID();
    return new Promise<boolean>((resolve) => {
      const timer = setTimeout(() => {
        pendingPullProbesRef.current.delete(probeId);
        resolve(false);
      }, 8000);
      pendingPullProbesRef.current.set(probeId, (success) => {
        clearTimeout(timer);
        pendingPullProbesRef.current.delete(probeId);
        resolve(success);
      });
      sendMessage({
        type: 'lan_pull_probe',
        payload: { probeId, probeUrl: selfLanUrl, targetDeviceId },
        fromDeviceId: myId,
        toDeviceId: targetDeviceId,
        ts: Date.now(),
      }).catch(() => {
        clearTimeout(timer);
        pendingPullProbesRef.current.delete(probeId);
        resolve(false);
      });
    });
  }, [devices]);

  // ─── WebRTC signal handling ───────────────────────────────────────────

  const receivedOfferIdsRef = useRef(new Set<string>());
  const handleWebRTCSignal = useCallback((data: MessageEnvelope) => {
    const signal = data.payload as WebRTCSignal;
    if (!signal || !signal.sessionId) return;
    if (!window.isSecureContext) return;
    const mgr = webrtcManagerRef.current;
    if (!mgr) return;
    if (signal.type === 'webrtc_offer' && signal.senderDeviceId !== getOrCreateDeviceId() && signal.targetDeviceId === getOrCreateDeviceId()) {
      if (receivedOfferIdsRef.current.has(signal.sessionId)) return;
      receivedOfferIdsRef.current.add(signal.sessionId);
      if (receivedOfferIdsRef.current.size > 256) {
        receivedOfferIdsRef.current.delete(receivedOfferIdsRef.current.values().next().value!);
      }
      for (const fileMeta of signal.files) {
        const localId = fileMeta.senderLocalId ?? generateUUID();
        webrtcFileLocalIdMap.current.set(fileMeta.fileId, localId);
        if (fileMeta.fileSize > 0) webrtcFileSizeMap.current.set(fileMeta.fileId, fileMeta.fileSize);
        speedTrackersRef.current.set(localId, new SpeedTracker());
        const placeholder: ChatMessage = {
          type: 'file',
          payload: { fileName: fileMeta.fileName, size: fileMeta.fileSize, webrtc: true },
          fromDeviceId: data.fromDeviceId,
          ts: Date.now(),
          _localId: localId,
          _status: 'downloading',
          _progress: 0,
        };
        setMessages((prev) => [...prev, placeholder]);
      }
    }
    mgr.handleSignal(signal);
  }, []);

  const ingestGuestPeer = useCallback((peer: { deviceId: string; name?: string; platform?: string | null }) => {
    const deviceId = peer.deviceId.trim();
    if (!deviceId || deviceId === getOrCreateDeviceId()) return;
    const name = peer.name?.trim() || shortDeviceLabel(deviceId);
    const platform = peer.platform ?? null;
    upsertGuestPeer({ deviceId, name, platform });
    setDevices((prev) => {
      const dto = guestPeerToDeviceDto({ deviceId, name, platform });
      const idx = prev.findIndex((d) => d.deviceId === deviceId);
      if (idx < 0) return [...prev, dto];
      const next = [...prev];
      next[idx] = {
        ...next[idx],
        name: peer.name?.trim() ? name : next[idx].name,
        platform: platform ?? next[idx].platform,
      };
      return next;
    });
    void pairDevice(deviceId);
  }, []);

  // ─── Centrifugo message handler ───────────────────────────────────────

  const onMessage = useCallback(
    (data: MessageEnvelope) => {
      logger.debug(TAG, 'onMessage type=', data.type, 'fromDeviceId=', data.fromDeviceId);
      if (data.type === 'device_pair_hello') {
        const me = getOrCreateDeviceId();
        if (data.toDeviceId && data.toDeviceId !== me) return;
        const payload =
          data.payload && typeof data.payload === 'object'
            ? (data.payload as { deviceId?: unknown; name?: unknown; platform?: unknown })
            : {};
        const peerId =
          (typeof payload.deviceId === 'string' && payload.deviceId.trim()) || data.fromDeviceId;
        if (!peerId || peerId === me) return;
        ingestGuestPeer({
          deviceId: peerId,
          name: typeof payload.name === 'string' ? payload.name : undefined,
          platform: typeof payload.platform === 'string' ? payload.platform : null,
        });
        return;
      }
      if (data.type === 'device_roster_patch') return;
      if (data.type === 'peer_device_patch') {
        const patch = data as unknown as { device?: DeviceDto };
        if (patch.device?.deviceId) {
          const updated = patch.device;
          rememberPeerProfiles([updated]);
          setDevices(prev => {
            if (!prev.some(d => d.deviceId === updated.deviceId)) return prev;
            return mergeDeviceRosters(mergePeerSnapshot(prev, prev.map(d => d.deviceId === updated.deviceId ? updated : d)), loadGuestPeers());
          });
        }
        return;
      }
      if (isWebRTCSignal(data)) {
        handleWebRTCSignal(data);
        return;
      }
      if (data.type === 'lan_file_offer') {
        if (data.payload && typeof data.payload === 'object') {
          const payload = data.payload as {
            pullUrl?: string;
            fileName?: string;
            size?: number;
            offerId?: string;
            targetDeviceIds?: string[];
            localId?: string;
          };
          const me = getOrCreateDeviceId();
          if (
            isLanFileOfferForMe({
              me,
              toDeviceId: data.toDeviceId,
              targetDeviceIds: payload.targetDeviceIds,
            }) &&
            payload.pullUrl
          ) {
            const offerId = typeof payload.offerId === 'string' ? payload.offerId : '';
            if (offerId) {
              if (seenLanOfferIdsRef.current.has(offerId)) return;
              seenLanOfferIdsRef.current.add(offerId);
              if (seenLanOfferIdsRef.current.size > 64) {
                const first = seenLanOfferIdsRef.current.values().next().value;
                if (first) seenLanOfferIdsRef.current.delete(first);
              }
            }
            pullFileFromOffer(payload.pullUrl, payload.fileName ?? t('chat.bubble.fileFallback'), payload.size, {
              localId: typeof payload.localId === 'string' ? payload.localId : undefined,
              fromDeviceId: data.fromDeviceId,
            });
          } else {
            logger.debug(
              TAG,
              'drop lan_file_offer me=',
              me,
              'to=',
              data.toDeviceId,
              'targets=',
              payload.targetDeviceIds,
            );
          }
        }
        return;
      }
      if (data.type === 'lan_pull_probe' && data.payload && typeof data.payload === 'object') {
        const payload = data.payload as { probeUrl?: string; probeId?: string; targetDeviceId?: string };
        const me = getOrCreateDeviceId();
        if (payload.targetDeviceId === me && payload.probeUrl && payload.probeId) {
          handlePullProbe(payload.probeUrl, payload.probeId, data.fromDeviceId);
        }
        return;
      }
      if (data.type === 'lan_pull_probe_result' && data.payload && typeof data.payload === 'object') {
        const payload = data.payload as { probeId?: string; success?: boolean };
        if (payload?.probeId) {
          const resolve = pendingPullProbesRef.current.get(payload.probeId);
          if (resolve) resolve(payload.success === true);
        }
        return;
      }
      if (data.type === 'lan_http_probe' && data.payload && typeof data.payload === 'object') {
        const payload = data.payload as { probeId?: string; targetDeviceId?: string; senderLanHttpUrl?: string };
        const me = getOrCreateDeviceId();
        if (payload.targetDeviceId === me && payload.probeId) {
          (async () => {
            let senderReachable = false;
            if (payload.senderLanHttpUrl) {
              senderReachable = await probeHttpWeb(payload.senderLanHttpUrl, 3000);
            }
            sendMessage({ type: 'lan_http_probe_result', payload: { probeId: payload.probeId, success: true, lanHttpUrl: null, senderReachable }, fromDeviceId: me, toDeviceId: data.fromDeviceId, ts: Date.now() }).catch(e => logger.warn(TAG, 'lan_http_probe reply failed:', e));
          })();
        }
        return;
      }
      if (data.type === 'lan_http_probe_result' && data.payload && typeof data.payload === 'object') {
        const payload = data.payload as { probeId?: string; success?: boolean; lanHttpUrl?: string; senderReachable?: boolean };
        if (payload?.probeId) {
          const resolve = pendingLanHttpProbesRef.current.get(payload.probeId);
          if (resolve) resolve({ success: payload.success === true, lanHttpUrl: payload.lanHttpUrl ?? undefined, senderReachable: payload.senderReachable === true });
        }
        return;
      }
      if (data.type === 'webrtc_probe' && data.payload && typeof data.payload === 'object') {
        const payload = data.payload as { probeId?: string; targetDeviceId?: string };
        const me = getOrCreateDeviceId();
        if (payload.targetDeviceId === me && payload.probeId) {
          sendMessage({ type: 'webrtc_probe_result', payload: { probeId: payload.probeId, success: true, connectivity: 'online' }, fromDeviceId: me, toDeviceId: data.fromDeviceId, ts: Date.now() }).catch(e => logger.warn(TAG, 'webrtc_probe reply failed:', e));
        }
        return;
      }
      if (data.type === 'webrtc_probe_result') {
        return;
      }
      if (data.type === 'text') {
        const me = getOrCreateDeviceId();
        // Delivery is scoped to this device by the server, independent of
        // which conversation happens to be open in the UI.
        if (data.toDeviceId && data.toDeviceId !== me && data.fromDeviceId !== me) return;
      }
      if (data.type === 'text' && data.fromDeviceId !== getOrCreateDeviceId()) {
        const incomingText =
          data.payload && typeof data.payload === 'object'
            ? (data.payload as { text?: unknown }).text
            : undefined;
        if (typeof incomingText === 'string' && incomingText.length > 0 && loadAutoCopyIncomingText()) {
          // Optional chaining short-circuits when clipboard is unavailable
          // (non-secure context); failures are silently ignored.
          void navigator.clipboard
            ?.writeText(incomingText)
            .then(() => {
              toast.success(t('chat.autoCopiedToast', { preview: autoCopyPreview(incomingText) }));
            })
            .catch(() => {});
        }
      }
      const rawPayload = data.payload && typeof data.payload === 'object' ? (data.payload as { localId?: unknown }) : null;
      const incomingLocalId = rawPayload ? normalizeMessageLocalId(rawPayload.localId) : undefined;
      if (incomingLocalId) {
        const pl = data.payload as { webrtc?: boolean; lan?: boolean; fileName?: string; targetDeviceId?: string; targetDeviceIds?: string[] };
        const me = getOrCreateDeviceId();
        if (pl.lan && Array.isArray(pl.targetDeviceIds) && !pl.targetDeviceIds.includes(me)) return;
        if (pl.webrtc && pl.targetDeviceId && pl.targetDeviceId !== me) return;
        // Merge with the local LAN/WebRTC placeholder by per-transfer
        // localId (the only stable id). Never merge by fileName — that
        // collapsed re-sent same-named files into a single bubble.
        setMessages((prev) => {
          const idx = prev.findIndex((m) => rowMatchesLocalId(m, incomingLocalId));
          if (idx >= 0) {
            const updated = [...prev];
            updated[idx] = { ...data, _localId: incomingLocalId, _status: 'sent' } as ChatMessage;
            return updated;
          }
          return [...prev, { ...data, _localId: incomingLocalId, _status: 'sent' } as ChatMessage];
        });
        return;
      }
      if (data.type === 'file' && data.payload && typeof data.payload === 'object') {
        const me = getOrCreateDeviceId();
        const pl = data.payload as {
          key?: string;
          fileName?: string;
          webrtc?: boolean;
          lan?: boolean;
          targetDeviceIds?: string[];
        };
        const rowId = `${data.ts}_${data.fromDeviceId}`;
        const isIncomingS3 =
          data.fromDeviceId !== me &&
          filePayloadTransferChannel(pl) === 's3' &&
          !!pl.key;

        setMessages((prev) => [
          ...prev,
          {
            ...(data as ChatMessage),
            ...(isIncomingS3 ? { _status: 'downloading' as const, _progress: 0 } : {}),
          },
        ]);

        if (isIncomingS3 && !autoDownloadedS3Ref.current.has(rowId)) {
          autoDownloadedS3Ref.current.add(rowId);
          const displayName = pl.fileName ?? t('chat.bubble.fileFallback');
          const s3Key = pl.key!;
          void (async () => {
            try {
              await downloadS3FileAsBrowserSave(s3Key, displayName, (received, total) => {
                const pct = total > 0 ? Math.round((received / total) * 100) : 0;
                setMessages((prev) =>
                  prev.map((m) =>
                    `${m.ts}_${m.fromDeviceId}` === rowId
                      ? { ...m, _progress: pct, _status: 'downloading' }
                      : m,
                  ),
                );
              });
              setMessages((prev) =>
                prev.map((m) =>
                  `${m.ts}_${m.fromDeviceId}` === rowId
                    ? { ...m, _status: 'sent', _progress: undefined }
                    : m,
                ),
              );
            } catch (e) {
              logger.warn(TAG, 'incoming S3 auto-download failed', e);
              setMessages((prev) =>
                prev.map((m) =>
                  `${m.ts}_${m.fromDeviceId}` === rowId
                    ? { ...m, _status: 'failed', _progress: undefined }
                    : m,
                ),
              );
            }
          })();
        }
        return;
      }
      setMessages((prev) => [...prev, data as ChatMessage]);
    },
    [pullFileFromOffer, handlePullProbe, handleWebRTCSignal, ingestGuestPeer, t],
  );

  const loadDevices = useCallback(() => {
    const guests = loadGuestPeers();
    setDevices(prev => mergeDeviceRosters(prev, guests));
    listPairedDevices()
      .then((list) => { rememberPeerProfiles(list); setDevices(prev => mergeDeviceRosters(mergePeerSnapshot(prev, list), loadGuestPeers())); })
      .catch((e) => logger.warn(TAG, 'listPairedDevices failed', e));
  }, []);

  // ─── App-level realtime (survives leaving /chat) ──────────────────────

  const { connected, subscribe } = useRealtime();

  const messageHandlerRef = useRef(onMessage);
  useEffect(() => { messageHandlerRef.current = onMessage; }, [onMessage]);
  useEffect(() => subscribe(data => messageHandlerRef.current(data)), [subscribe]);

  useEffect(() => {
    if (!connected) return;
    void (async () => {
      try {
        if (userId) await registerDevice(getOrCreateDeviceId(), getDeviceName(), {
          platform: 'web',
          sessionId: presenceSessionId,
        });
      } catch (e) {
        logger.warn(TAG, 'registerDevice onConnected', e);
      }
      loadDevices();
    })();
  }, [connected, userId, loadDevices, presenceSessionId]);

  // ─── Device lists ─────────────────────────────────────────────────────

  const otherDevices = useMemo(
    () => devices.filter((d) => d.deviceId !== currentDeviceId),
    [devices, currentDeviceId],
  );
  const lanDevices = useMemo(
    () => otherDevices.filter((d) => d.platform !== 'web'),
    [otherDevices],
  );

  const directHttpProbe = useCallback((url: string) => probeHttpWeb(url, 3000), []);

  const { deviceReach, freshLanUrlsRef, probing: targetsProbing, probeSingleDevice, applyDeviceReach } = useSendTargetProbes(
    otherDevices,
    lanDevices,
    connected,
    targetProbeToken,
    probeForceAll,
    sendLanHttpProbe,
    directHttpProbe,
  );

  const pairedPeersRef = useRef(new Set<string>());
  const rememberLanPeer = useCallback((deviceId: string) => {
    if (!deviceId || pairedPeersRef.current.has(deviceId)) return;
    pairedPeersRef.current.add(deviceId);
    void pairDevice(deviceId);
  }, []);

  useEffect(() => {
    for (const [id, entry] of Object.entries(deviceReach)) {
      const methods = entry.methods;
      if (methods.directHttp || methods.peerHttpHealthy || methods.pullReachable || methods.lanSignaling) {
        rememberLanPeer(id);
      }
    }
  }, [deviceReach, rememberLanPeer]);

  // ─── Hydrate from localStorage ────────────────────────────────────────

  useEffect(() => {
    if (storageHydratedRef.current) return;
    storageHydratedRef.current = true;
    setSelectedTargets(loadSelectedTargets());
  }, []);

  const webrtcAvailable = typeof window !== 'undefined' && window.isSecureContext;

  const toggleTarget = useCallback((deviceId: string) => {
    setSelectedTargets((prev) => {
      const next = new Set(prev);
      if (next.has(deviceId)) next.delete(deviceId);
      else next.add(deviceId);
      persistSelectedTargets(next);
      return next;
    });
  }, []);

  const buildFreshLanDevices = useCallback(
    (lanSelectedIds: Set<string>) => {
      return lanDevices
        .filter((d) => lanSelectedIds.has(d.deviceId))
        .map((d) => {
          const freshUrl = freshLanUrlsRef.current[d.deviceId];
          return freshUrl ? { ...d, lanHttpUrl: freshUrl } : d;
        })
        .filter((d) => d.lanHttpUrl);
    },
    [lanDevices, freshLanUrlsRef],
  );

  // ─── Load initial data ────────────────────────────────────────────────

  useEffect(() => {
    if (!userId || selectedDeviceId !== S3_VIRTUAL_DEVICE_ID) {
      hasNoMoreRef.current = true;
      return;
    }
    const outbound = outboundForWebChat(userId, selectedDeviceId, getOrCreateDeviceId());
    if (!outbound) return;
    let cancelled = false;
    hasNoMoreRef.current = false;
    getMessageHistory(CHAT_PAGE_SIZE, undefined, outbound.threadKey)
      .then((list) => {
        if (cancelled) return;
        const filtered = list.filter((m) => !EPHEMERAL_TYPES.has(m.type));
        if (list.length < CHAT_PAGE_SIZE) hasNoMoreRef.current = true;
        setMessages(prev => mergeMessageHistory(prev, filtered as ChatMessage[]));
      })
      .catch((e) => logger.warn(TAG, 'loadHistory failed', e));
    transferStateManager.cleanExpired();
    return () => { cancelled = true; };
  }, [userId, selectedDeviceId]);

  useEffect(() => {
    if (!userId) {
      setS3Configured(false);
      setS3Online(false);
      setS3Checking(false);
      if (selectedDeviceIdRef.current === S3_VIRTUAL_DEVICE_ID) {
        setSelectedDeviceId(null);
      }
      setDevices(loadGuestPeers().map(guestPeerToDeviceDto));
      return;
    }
    let cancelled = false;
    void (async () => {
      try {
        await registerDevice(getOrCreateDeviceId(), getDeviceName(), {
          platform: 'web',
          sessionId: presenceSessionId,
        });
      } catch (e) {
        logger.warn(TAG, 'registerDevice on userId', e);
      }
      if (cancelled) return;
      try {
        const list = await listPairedDevices();
        if (!cancelled) setDevices(mergeDeviceRosters(list, loadGuestPeers()));
      } catch (e) {
        logger.warn(TAG, 'listDevices failed', e);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [userId, presenceSessionId]);

  useEffect(() => {
    if (!connected) return;
    let busy = false;
    const online = async () => {
      if (busy) return;
      busy = true;
      try { await publishDevicePresence('online'); } catch (e) { logger.warn(TAG, 'device heartbeat failed', e); }
      finally { busy = false; }
    };
    const offline = () => { void publishDevicePresence('offline').catch(() => {}); };
    const resume = () => {
      if (document.visibilityState === 'visible') { void online(); loadDevices(); }
    };
    const nameChanged = () => { void online(); loadDevices(); };
    const onStorage = (event: StorageEvent) => { if (event.key === 'ultrasend_device_name') nameChanged(); };
    void online();
    const heartbeat = setInterval(() => void online(), 15000);
    const fallback = setInterval(loadDevices, 30000);
    window.addEventListener('pagehide', offline);
    window.addEventListener('pageshow', resume);
    window.addEventListener('online', resume);
    window.addEventListener('storage', onStorage);
    window.addEventListener(DEVICE_NAME_CHANGED, nameChanged);
    document.addEventListener('visibilitychange', resume);
    return () => {
      clearInterval(heartbeat); clearInterval(fallback);
      window.removeEventListener('pagehide', offline);
      window.removeEventListener('pageshow', resume);
      window.removeEventListener('online', resume);
      window.removeEventListener('storage', onStorage);
      window.removeEventListener(DEVICE_NAME_CHANGED, nameChanged);
      document.removeEventListener('visibilitychange', resume);
      offline();
    };
  }, [connected, loadDevices]);

  // Config flag + connectivity (CUSTOM: presigned HEAD from client; HOSTED: configured only)
  const runS3ConfigCheck = useCallback(async (seq: number) => {
    try {
      const ok = await hasS3Config();
      if (seq !== checkS3SeqRef.current) return;
      setS3Configured(ok);
      let online = false;
      if (ok && userId) {
        online = await checkS3Online();
      }
      if (seq !== checkS3SeqRef.current) return;
      setS3Online(online);
      return ok;
    } catch {
      if (seq !== checkS3SeqRef.current) return false;
      setS3Configured(false);
      setS3Online(false);
      return false;
    }
  }, [userId]);

  const checkS3Config = useCallback(async () => {
    const seq = ++checkS3SeqRef.current;
    setS3Checking(true);
    try {
      let ok = await runS3ConfigCheck(seq);
      if (seq !== checkS3SeqRef.current) return;
      if (!ok) {
        await new Promise((r) => setTimeout(r, S3_CONFIG_RETRY_DELAY_MS));
        if (seq !== checkS3SeqRef.current) return;
        ok = await runS3ConfigCheck(seq);
      }
    } finally {
      if (seq === checkS3SeqRef.current) {
        setS3Checking(false);
      }
    }
  }, [runS3ConfigCheck]);

  const checkS3ForDiagnostic = useCallback(async (): Promise<{ configured: boolean; online: boolean }> => {
    try {
      const configured = await hasS3Config();
      if (!configured) return { configured: false, online: false };
      if (!userId) return { configured: true, online: false };
      const online = await checkS3Online();
      return { configured: true, online };
    } catch {
      return { configured: false, online: false };
    }
  }, [userId]);

  const runSessionConnectionDiagnostic = useCallback((deviceId: string) => {
    if (!deviceId || deviceId === S3_VIRTUAL_DEVICE_ID) {
      void checkS3Config();
      return;
    }

    const entry = deviceReach[deviceId];
    if (entry?.probing) return;

    const device = devices.find((d) => d.deviceId === deviceId);
    if (!device) return;

    const initialFreshLanUrl = freshLanUrlsRef.current[deviceId];
    const deviceForProbe = initialFreshLanUrl
      ? { ...device, lanHttpUrl: initialFreshLanUrl }
      : device;

    void checkS3Config();

    const nearbyIds = new Set(lanDevices.map((d) => d.deviceId));
    for (const d of otherDevices) {
      if (d.lanHttpUrl?.trim()) nearbyIds.add(d.deviceId);
    }
    const myDeviceIds = new Set(otherDevices.map((d) => d.deviceId));
    const priority = classifyDevice(deviceForProbe, nearbyIds, myDeviceIds);
    const orderedIds = diagnosticStepOrder(priority);

    setConnectionDiagnostic({
      peerId: deviceId,
      peerLabel: peerLabelForDevice(deviceForProbe),
      steps: orderedIds.map((id) => ({
        id,
        title: diagnosticStepTitle(t, id),
        status: 'pending',
      })),
      running: true,
    });
    setDiagnosticSheetOpen(true);

    applyDeviceReach(deviceId, {
      methods: entry?.methods ?? {
        directHttp: false,
        peerHttpHealthy: false,
        pullReachable: false,
        webrtc: null,
        lanSignaling: false,
      },
      probing: true,
    });

    const session = ++diagnosticSessionRef.current;

    void (async () => {
      let s3Available = s3Configured && s3Online;
      try {
        const { methods, freshLanUrl } = await runConnectionDiagnostic({
          device: deviceForProbe,
          initialFreshLanUrl,
          orderedStepIds: orderedIds,
          connected,
          isLoggedIn: !!userId,
          webrtcAvailable,
          onDirectHttpProbe: directHttpProbe,
          onLanHttpProbe: sendLanHttpProbe,
          onPullProbe: sendPullProbe,
          onCheckS3: async () => {
            const result = await checkS3ForDiagnostic();
            s3Available = result.configured && result.online;
            return result;
          },
          t,
          onStepUpdate: (steps) => {
            if (diagnosticSessionRef.current !== session) return;
            setConnectionDiagnostic((prev) =>
              prev && prev.peerId === deviceId ? { ...prev, steps } : prev,
            );
          },
          isCancelled: () => diagnosticSessionRef.current !== session,
        });

        if (diagnosticSessionRef.current !== session) return;

        applyDeviceReach(
          deviceId,
          { methods, probing: false },
          freshLanUrl,
        );

        const summary = buildDiagnosticSummary(t, methods, {
          peerIsWeb: isPeerWebDevice(deviceForProbe),
          webrtcAvailable,
          s3Available,
          guest: !userId,
        });

        setConnectionDiagnostic((prev) =>
          prev && prev.peerId === deviceId
            ? { ...prev, running: false, summary }
            : prev,
        );
      } catch (e) {
        logger.warn(TAG, 'runSessionConnectionDiagnostic failed', e);
        if (diagnosticSessionRef.current !== session) return;
        applyDeviceReach(deviceId, {
          methods: {
            directHttp: false,
            peerHttpHealthy: false,
            pullReachable: false,
            webrtc: false,
            lanSignaling: false,
          },
          probing: false,
        });
        setConnectionDiagnostic((prev) =>
          prev && prev.peerId === deviceId
            ? {
                ...prev,
                running: false,
                summary: t('chat.connectionDiag.summaryNoRoute'),
              }
            : prev,
        );
      }
    })();
  }, [
    deviceReach,
    devices,
    otherDevices,
    lanDevices,
    connected,
    userId,
    webrtcAvailable,
    directHttpProbe,
    sendLanHttpProbe,
    sendPullProbe,
    checkS3ForDiagnostic,
    checkS3Config,
    applyDeviceReach,
    freshLanUrlsRef,
    t,
    s3Configured,
    s3Online,
  ]);

  useEffect(() => {
    if (!userId || !accessToken) return;
    void checkS3Config();
  }, [userId, accessToken, checkS3Config]);

  useEffect(() => {
    const onS3Settings = pathname?.startsWith('/settings/s3') ?? false;
    if (prevOnS3SettingsRef.current && !onS3Settings && userId) {
      void checkS3Config();
    }
    prevOnS3SettingsRef.current = onS3Settings;
  }, [pathname, checkS3Config, userId]);

  const refreshSendTargets = useCallback(() => {
    void checkS3Config();
    setProbeForceAll(true);
    setTargetProbeToken((t) => t + 1);
    loadDevices();
  }, [loadDevices, checkS3Config]);

  const refreshDevices = loadDevices;

  // Refresh reachability without creating RTC sessions or touching file streams.
  useEffect(() => {
    const timer = setInterval(() => { setProbeForceAll(false); setTargetProbeToken(value => value + 1); }, 15000);
    return () => clearInterval(timer);
  }, []);

  // Initial probe when connected and devices available
  const initialTargetProbeForUserRef = useRef<string | undefined>(undefined);
  useEffect(() => {
    initialTargetProbeForUserRef.current = undefined;
    setProbeForceAll(false);
    setTargetProbeToken(0);
  }, [userId]);

  useEffect(() => {
    if (!connected || otherDevices.length === 0) return;
    const key = userId ?? `guest:${currentDeviceId}`;
    if (initialTargetProbeForUserRef.current === key) return;
    initialTargetProbeForUserRef.current = key;
    setProbeForceAll(false);
    setTargetProbeToken((t) => t + 1);
  }, [userId, connected, otherDevices.length, currentDeviceId]);

  // ─── Message loading ──────────────────────────────────────────────────

  const loadMoreMessages = useCallback(async () => {
    if (loadingMoreRef.current || hasNoMoreRef.current) return;
    if (!userId || selectedDeviceId !== S3_VIRTUAL_DEVICE_ID) return;
    const outbound = outboundForWebChat(userId, selectedDeviceId, getOrCreateDeviceId());
    if (!outbound) return;
    loadingMoreRef.current = true;
    setLoadingMore(true);
    try {
      const oldest = messages[0];
      if (!oldest) return;
      const before = (oldest as ChatMessage & { id?: number }).id;
      if (before == null) return;
      const list = await getMessageHistory(CHAT_PAGE_SIZE, before, outbound.threadKey);
      const filtered = list.filter((m) => !EPHEMERAL_TYPES.has(m.type));
      if (list.length < CHAT_PAGE_SIZE) hasNoMoreRef.current = true;
      if (filtered.length > 0) {
        setMessages(prev => mergeMessageHistory(prev, filtered as ChatMessage[]));
      }
    } catch (e) {
      logger.warn(TAG, 'loadMoreMessages failed', e);
    } finally {
      loadingMoreRef.current = false;
      setLoadingMore(false);
    }
  }, [messages, userId, selectedDeviceId]);

  // ─── Text sending ─────────────────────────────────────────────────────

  const sendTextMessage = useCallback(async (text: string) => {
    if (!text.trim() || sending) return;
    if (!selectedDeviceId) return;
    const deviceId = getOrCreateDeviceId();
    const outbound = userId
      ? outboundForWebChat(userId, selectedDeviceId, deviceId)
      : outboundForGuestChat(selectedDeviceId, deviceId);
    if (!outbound || (!userId && !outbound.toDeviceId)) return;
    setSending(true);
    const localId = generateUUID();
    const envelope: ChatMessage = {
      type: 'text',
      payload: { text, localId },
      fromDeviceId: deviceId,
      ts: Date.now(),
      toDeviceId: outbound.toDeviceId,
      threadKey: outbound.threadKey,
      _localId: localId,
      _status: 'sending',
    };
    setMessages((prev) => [...prev, envelope]);
    setSendError(null);
    const trimmed = text.trim();
    const lengthBucket = analyticsLengthBucket(trimmed.length);
    try {
      await sendMessage({
        type: envelope.type,
        payload: envelope.payload,
        fromDeviceId: envelope.fromDeviceId,
        ts: envelope.ts,
        threadKey: outbound.threadKey,
        ...(outbound.toDeviceId != null ? { toDeviceId: outbound.toDeviceId } : {}),
      });
      updateMessageByLocalId(localId, { _status: 'sent' });
      analyticsTrack(AnalyticsEvents.chatTextSend, {
        result: 'sent',
        offline: !userId,
        channel: 'api',
        length_bucket: lengthBucket,
      });
    } catch (e) {
      if (e instanceof DeviceSendRateLimitedError) {
        updateMessageByLocalId(localId, { _status: 'failed' });
        return;
      }
      const msg = e instanceof Error ? e.message : 'chat.sendFailed';
      logger.warn(TAG, 'sendMessage failed', msg);
      setSendError(msg);
      updateMessageByLocalId(localId, { _status: 'failed' });
      analyticsTrack(AnalyticsEvents.chatTextSend, {
        result: 'failed',
        offline: !userId,
        channel: 'api',
        length_bucket: lengthBucket,
      });
    } finally {
      setSending(false);
    }
  }, [sending, updateMessageByLocalId, userId, selectedDeviceId]);

  // ─── File sending ─────────────────────────────────────────────────────

  const sendSingleFile = useCallback(async (
    file: File,
    useLan: boolean,
    targetDevices: DeviceDto[],
    opts?: { reportTerminalFailure?: boolean; reuseLocalId?: string },
  ): Promise<boolean> => {
    const localId = opts?.reuseLocalId ?? generateUUID();
    const deviceId = getOrCreateDeviceId();
    const reportFailure = opts?.reportTerminalFailure !== false;
    if (!selectedDeviceId) {
      setFileError('chat.errors.needSessionDevice');
      return false;
    }
    const outbound = userId
      ? outboundForWebChat(userId, selectedDeviceId, deviceId)
      : outboundForGuestChat(selectedDeviceId, deviceId);
    if (!outbound || (!userId && !outbound.toDeviceId)) {
      setFileError('chat.errors.needSessionDevice');
      return false;
    }
    const abortController = new AbortController();
    activeTransfersRef.current.set(localId, abortController);

    if (useLan) {
      if (targetDevices.length === 0) {
        logger.warn(TAG, 'sendFile LAN no reachable devices', file.name);
        if (reportFailure) setFileError('chat.errors.deviceUnavailable');
        activeTransfersRef.current.delete(localId);
        return false;
      }
      retryInfoRef.current.set(localId, { file, channel: 'lan', targetDevices });
      const lanPayload = { fileName: file.name, size: file.size, lan: true, targetDeviceIds: targetDevices.map((d) => d.deviceId), localId };
      const placeholder: ChatMessage = {
        type: 'file',
        payload: lanPayload,
        toDeviceId: outbound.toDeviceId,
        threadKey: outbound.threadKey,
        fromDeviceId: deviceId,
        ts: Date.now(),
        _localId: localId,
        _status: 'uploading',
        _progress: 0,
        _phase: 'tryingHttp',
        _transferType: 'lan',
      };
      if (opts?.reuseLocalId) {
        updateMessageByLocalId(localId, {
          payload: lanPayload,
          _status: 'uploading',
          _progress: 0,
          _phase: 'tryingHttp',
          _transferType: 'lan',
        });
      } else {
        setMessages((prev) => [...prev, placeholder]);
      }
      const lanTracker = new SpeedTracker();
      speedTrackersRef.current.set(localId, lanTracker);
      try {
        const lanOk = await trySendFileViaLan(file, targetDevices, abortController, (pct) => {
          lanTracker.update(Math.round(file.size * pct / 100));
          updateMessageByLocalId(localId, { _progress: pct, _speed: lanTracker.formatted, _phase: 'sendingHttp', _transferType: 'lan' });
        }, localId);
        if (abortController.signal.aborted) return false;
        if (!lanOk) throw new Error('chat.httpSendFailed');
        try {
          await sendMessage({
            type: 'file',
            payload: lanPayload,
            fromDeviceId: deviceId,
            ts: Date.now(),
            threadKey: outbound.threadKey,
            ...(outbound.toDeviceId != null ? { toDeviceId: outbound.toDeviceId } : {}),
          });
        } catch (e) {
          if (userId) throw e;
          logger.warn(TAG, 'guest LAN file echo skipped', e);
        }
        retryInfoRef.current.delete(localId);
        updateMessageByLocalId(localId, { _status: 'sent', _progress: undefined, _speed: undefined, _phase: undefined, _transferType: 'lan' });
        return true;
      } catch (e) {
        if (e instanceof DOMException && e.name === 'AbortError') {
          updateMessageByLocalId(localId, { _status: 'cancelled', _progress: undefined, _speed: undefined });
          return false;
        }
        const errMsg = e instanceof Error ? e.message : String(e);
        if (
          reportFailure && (
            errMsg.includes(TRANSFER_STALL_TIMEOUT_MESSAGE) ||
            errMsg.includes('停滞') ||
            errMsg.includes('stall') ||
            errMsg.includes('timeout') ||
            errMsg.includes('Timeout')
          )
        ) {
          setFileError('chat.errors.httpStall');
        }
        if (reportFailure) {
          updateMessageByLocalId(localId, { _status: 'failed', _speed: undefined, _progress: undefined });
        }
        return false;
      } finally {
        activeTransfersRef.current.delete(localId);
        speedTrackersRef.current.delete(localId);
      }
    }

    if (!userId) {
      if (reportFailure) setFileError('chat.errors.guestTextNeedsLogin');
      activeTransfersRef.current.delete(localId);
      return false;
    }
    if (!s3Configured) {
      if (reportFailure) setFileError('chat.errors.configureS3First');
      activeTransfersRef.current.delete(localId);
      return false;
    }
    if (!s3Online) {
      if (reportFailure) setFileError('chat.errors.s3Unavailable');
      activeTransfersRef.current.delete(localId);
      return false;
    }
    retryInfoRef.current.set(localId, { file, channel: 's3', targetDevices: [] });
    const s3Payload = { fileName: file.name, size: file.size, localId };
    const placeholder: ChatMessage = {
      type: 'file',
      payload: s3Payload,
      toDeviceId: outbound.toDeviceId,
      threadKey: outbound.threadKey,
      fromDeviceId: deviceId,
      ts: Date.now(),
      _localId: localId,
      _status: 'uploading',
      _progress: 0,
      _phase: opts?.reuseLocalId ? 'tryingS3Fallback' : 'tryingS3',
      _transferType: 's3',
    };
    if (opts?.reuseLocalId) {
      updateMessageByLocalId(localId, {
        payload: s3Payload,
        _status: 'uploading',
        _progress: 0,
        _phase: 'tryingS3Fallback',
        _transferType: 's3',
      });
    } else {
      setMessages((prev) => [...prev, placeholder]);
    }
    const s3Tracker = new SpeedTracker();
    speedTrackersRef.current.set(localId, s3Tracker);
    let lastLoggedPct = 0;
    try {
      const result = await cloudTransfer.upload(
        file,
        (sent, total) => {
          s3Tracker.update(sent);
          const pct = total > 0 ? Math.min(Math.round((sent / total) * 100), 100) : 0;
          updateMessageByLocalId(localId, { _progress: pct, _speed: s3Tracker.formatted, _phase: 'sendingS3', _transferType: 's3' });
          if (pct >= lastLoggedPct + 10 || pct === 100) {
            lastLoggedPct = pct;
          }
        },
        abortController.signal,
      );
      const s3Tk = threadKeyForS3WebPersist(userId, deviceId, outbound.toDeviceId);
      await sendMessage({
        type: 'file',
        payload: { key: result.key, fileName: file.name, size: file.size, localId },
        fromDeviceId: deviceId,
        ts: Date.now(),
        threadKey: s3Tk,
        ...(outbound.toDeviceId != null ? { toDeviceId: outbound.toDeviceId } : {}),
      });
      retryInfoRef.current.delete(localId);
      updateMessageByLocalId(localId, { _status: 'sent', _progress: undefined, _speed: undefined, _phase: undefined, _transferType: 's3', payload: { key: result.key, fileName: file.name, size: file.size, localId } });
      return true;
    } catch (e) {
      if (e instanceof DOMException && e.name === 'AbortError') {
        updateMessageByLocalId(localId, { _status: 'cancelled', _progress: undefined, _speed: undefined });
        return false;
      }
      if (reportFailure) {
        setFileError(e instanceof Error ? e.message : 'chat.sendFailed');
        updateMessageByLocalId(localId, { _status: 'failed', _speed: undefined });
      }
      return false;
    } finally {
      activeTransfersRef.current.delete(localId);
      speedTrackersRef.current.delete(localId);
    }
  }, [updateMessageByLocalId, userId, selectedDeviceId, s3Configured, s3Online]);

  const sendFilesViaWebRTC = useCallback(async (
    files: File[],
    targetDeviceId: string,
    opts?: { fallbackS3?: boolean; reportTerminalFailure?: boolean; reuseLocalId?: string },
  ): Promise<boolean> => {
    const mgr = webrtcManagerRef.current;
    if (!mgr) return false;
    const fallbackS3 = opts?.fallbackS3 === true;
    const reportFailure = opts?.reportTerminalFailure !== false;
    const deviceId = getOrCreateDeviceId();
    const pendingWithMeta = files.map((file, index) => {
      const fileId = generateUUID();
      const localId = opts?.reuseLocalId && files.length === 1 && index === 0
        ? opts.reuseLocalId
        : generateUUID();
      const meta: FileMetadata = {
        fileId,
        fileName: file.name,
        fileSize: file.size,
        mimeType: file.type || 'application/octet-stream',
        senderLocalId: localId,
      };
      return { file, meta, localId };
    });
    for (const { file, meta, localId } of pendingWithMeta) {
      webrtcFileLocalIdMap.current.set(meta.fileId, localId);
      if (meta.fileSize > 0) webrtcFileSizeMap.current.set(meta.fileId, meta.fileSize);
      retryInfoRef.current.set(localId, { file, channel: 'webrtc', targetDevices: [], webrtcTargetDeviceId: targetDeviceId });
      speedTrackersRef.current.set(localId, new SpeedTracker());
      const placeholder: ChatMessage = {
        type: 'file',
        payload: { fileName: meta.fileName, size: meta.fileSize, webrtc: true, localId },
        toDeviceId: targetDeviceId,
        fromDeviceId: deviceId,
        ts: Date.now(),
        _localId: localId,
        _status: 'uploading',
        _progress: 0,
        _phase: 'connectingWebrtc',
        _transferType: 'webrtc',
      };
      setMessages((prev) => {
        const idx = prev.findIndex((m) => m._localId === localId);
        if (idx >= 0) {
          const next = [...prev];
          next[idx] = { ...next[idx], ...placeholder };
          return next;
        }
        return [...prev, placeholder];
      });
    }
    try {
      const session = await mgr.initiateTransfer(targetDeviceId, pendingWithMeta);
      await session.connected;
      for (const { localId } of pendingWithMeta) {
        updateMessageByLocalId(localId, { _phase: 'sendingWebrtc', _transferType: 'webrtc' });
      }
      await session.sendsFinished;
      return true;
    } catch (err) {
      if (String(err).includes('Transfer cancelled')) return false;
      if (err instanceof DeviceSendRateLimitedError) {
        for (const { meta } of pendingWithMeta) {
          const localId = webrtcFileLocalIdMap.current.get(meta.fileId);
          if (localId) {
            webrtcFileLocalIdMap.current.delete(meta.fileId);
            webrtcFileSizeMap.current.delete(meta.fileId);
            speedTrackersRef.current.delete(localId);
            updateMessageByLocalId(localId, { _status: 'failed', _progress: undefined, _speed: undefined });
          }
        }
        return false;
      }
      if (fallbackS3 && s3OnlineRef.current) {
        await runWithConcurrency(pendingWithMeta, MAX_PARALLEL_FILE_SENDS, async ({ file, meta }) => {
          const localId = webrtcFileLocalIdMap.current.get(meta.fileId);
          if (localId) {
            webrtcFileLocalIdMap.current.delete(meta.fileId);
            webrtcFileSizeMap.current.delete(meta.fileId);
            speedTrackersRef.current.delete(localId);
            updateMessageByLocalId(localId, { _status: 'uploading', _progress: 0, _speed: undefined, payload: { fileName: file.name, size: file.size } });
          }
          await sendSingleFile(file, false, []);
        });
        return true;
      }
      if (reportFailure) {
        const peer = devices.find((d) => d.deviceId === targetDeviceId);
        setFileError(
          !userIdRef.current
            ? 'chat.errors.webrtcTryLogin'
            : isWebPeer(peer?.platform)
            ? 'chat.errors.webrtcTryS3'
            : 'chat.errors.webrtcTryHttp',
        );
        for (const { meta } of pendingWithMeta) {
          const localId = webrtcFileLocalIdMap.current.get(meta.fileId);
          if (localId) {
            webrtcFileLocalIdMap.current.delete(meta.fileId);
            webrtcFileSizeMap.current.delete(meta.fileId);
            speedTrackersRef.current.delete(localId);
            updateMessageByLocalId(localId, { _status: 'failed', _progress: undefined, _speed: undefined });
          }
        }
      }
      return false;
    }
  }, [updateMessageByLocalId, sendSingleFile, devices]);

  useEffect(() => {
    sendSingleFileRef.current = sendSingleFile;
    sendFilesViaWebRTCRef.current = sendFilesViaWebRTC;
  });

  // ─── LAN verification ─────────────────────────────────────────────────

  const tryResolveLanUrl = useCallback(async (device: DeviceDto): Promise<string | null> => {
    const baseUrl = device.lanHttpUrl;
    if (!baseUrl) return null;
    let parsed: URL;
    try { parsed = new URL(baseUrl); } catch { return null; }
    if (await probeHttpWeb(baseUrl, 1500)) return baseUrl;
    if (await probeHttpWeb(baseUrl, 3000)) return baseUrl;
    const currentPort = parsed.port ? Number(parsed.port) : (parsed.protocol === 'https:' ? 443 : 80);
    const scanPorts: number[] = [];
    for (let p = 9080; p <= 9100; p++) { if (p !== currentPort) scanPorts.push(p); }
    const candidates = scanPorts.map((p) => `${parsed.protocol}//${parsed.hostname}:${p}`);
    const found = await Promise.all(candidates.map(async (url) => ({ url, ok: await probeHttpWeb(url, 900) })));
    const hit = found.find((x) => x.ok);
    return hit?.url ?? null;
  }, []);

  const verifyLanTargets = useCallback(async (targets: DeviceDto[]): Promise<DeviceDto[]> => {
    if (targets.length === 0) return [];
    const results = await Promise.all(targets.map(async (d) => {
      const resolvedUrl = await tryResolveLanUrl(d);
      if (!resolvedUrl) return null;
      if (resolvedUrl !== d.lanHttpUrl) {
        try { await updateDevice(d.deviceId, { lanHttpUrl: resolvedUrl }); } catch (e) { logger.warn(TAG, 'updateDevice lanHttpUrl failed:', d.deviceId, e); }
      }
      rememberLanPeer(d.deviceId);
      return { ...d, lanHttpUrl: resolvedUrl } as DeviceDto;
    }));
    return results.filter((d): d is DeviceDto => d !== null);
  }, [tryResolveLanUrl, rememberLanPeer]);

  // ─── File send orchestration ──────────────────────────────────────────

  const sendFilesViaCascade = useCallback(async (filesToSend: File[], targetId: string) => {
    const peer = devices.find((d) => d.deviceId === targetId);
    const hops = hopSkipCacheRef.current.filter(
      targetId,
      applicableTransferHops({
        localIsWeb: true,
        peerIsWeb: isWebPeer(peer?.platform),
        isLoggedIn: !!userId,
        webrtcAvailable,
        s3Configured,
        s3Online,
        isS3VirtualSession: targetId === S3_VIRTUAL_DEVICE_ID,
      }),
    );
    if (hops.length === 0) {
      setFileError(
        !userId
          ? 'chat.errors.guestTextNeedsLogin'
          : !s3Configured
            ? 'chat.errors.configureS3First'
            : 'chat.errors.selectOnlineTargets',
      );
      return;
    }

    await runWithConcurrency(filesToSend, MAX_PARALLEL_FILE_SENDS, async (file) => {
      const localId = generateUUID();
      const deviceId = getOrCreateDeviceId();
      const httpTried = hops.includes('httpPush');
      const firstHop = hops[0];
      const firstPhase: TransferPhase = firstHop === 's3'
        ? 'tryingS3'
        : firstHop === 'webrtc'
          ? 'connectingWebrtc'
          : 'tryingHttp';
      const firstType: TransferChannel = firstHop === 's3'
        ? 's3'
        : firstHop === 'webrtc'
          ? 'webrtc'
          : 'lan';
      setMessages((prev) => [...prev, {
        type: 'file',
        payload: { fileName: file.name, size: file.size, localId },
        toDeviceId: targetId,
        fromDeviceId: deviceId,
        ts: Date.now(),
        _localId: localId,
        _status: 'uploading',
        _progress: 0,
        _phase: firstPhase,
        _transferType: firstType,
      }]);

      let sent = false;
      if (hops.includes('httpPush')) {
        updateMessageByLocalId(localId, { _phase: 'tryingHttp', _transferType: 'lan' });
        const candidates = buildFreshLanDevices(new Set([targetId]));
        const withUrl = candidates.length > 0
          ? candidates
          : devices.filter((d) => d.deviceId === targetId && !!d.lanHttpUrl);
        const verified = await verifyLanTargets(withUrl);
        if (cancelledTransferIdsRef.current.has(localId)) return;
        if (verified.length > 0) {
          sent = await sendSingleFile(file, true, verified, { reportTerminalFailure: false, reuseLocalId: localId });
          if (cancelledTransferIdsRef.current.has(localId)) return;
          if (sent) {
            hopSkipCacheRef.current.markSucceeded(targetId, 'httpPush');
            return;
          }
        }
        hopSkipCacheRef.current.markFailed(targetId, 'httpPush');
      }
      if (!sent && hops.includes('webrtc')) {
        updateMessageByLocalId(localId, {
          _phase: httpTried ? 'connectingWebrtcFallback' : 'connectingWebrtc',
          _transferType: 'webrtc',
          _progress: 0,
          payload: { fileName: file.name, size: file.size, webrtc: true, localId },
        });
        sent = await sendFilesViaWebRTC([file], targetId, {
          fallbackS3: false,
          reportTerminalFailure: !hops.includes('s3'),
          reuseLocalId: localId,
        });
        if (cancelledTransferIdsRef.current.has(localId)) return;
        if (sent) {
          hopSkipCacheRef.current.markSucceeded(targetId, 'webrtc');
          return;
        }
        hopSkipCacheRef.current.markFailed(targetId, 'webrtc');
      }
      if (!sent && hops.includes('s3')) {
        updateMessageByLocalId(localId, {
          _phase: httpTried || hops.includes('webrtc') ? 'tryingS3Fallback' : 'tryingS3',
          _transferType: 's3',
          _progress: 0,
        });
        await sendSingleFile(file, false, [], { reuseLocalId: localId });
        return;
      }
      if (!sent) {
        updateMessageByLocalId(localId, { _status: 'failed', _progress: undefined, _speed: undefined, _phase: undefined });
        setFileError('chat.errors.selectOnlineTargets');
      }
    });
  }, [
    devices,
    userId,
    webrtcAvailable,
    s3Configured,
    s3Online,
    buildFreshLanDevices,
    verifyLanTargets,
    sendSingleFile,
    sendFilesViaWebRTC,
    updateMessageByLocalId,
  ]);

  const handleSendFiles = useCallback(() => {
    if (pendingFiles.length === 0) return;
    if (!selectedDeviceId) {
      setFileError('chat.errors.needSessionDevice');
      return;
    }
    const filesToSend = [...pendingFiles];
    setPendingFiles([]);
    setFileError(null);
    void sendFilesViaCascade(filesToSend, selectedDeviceId);
  }, [pendingFiles, selectedDeviceId, sendFilesViaCascade]);

  const addPendingFiles = useCallback((files: File[]) => {
    if (files.length === 0) return;
    setFileError(null);
    setPendingFiles((prev) => [...prev, ...files]);
  }, []);

  const handleFileSelect = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const fileList = e.target.files;
    if (!fileList || fileList.length === 0) return;
    const files = Array.from(fileList);
    e.target.value = '';
    addPendingFiles(files);
  }, [addPendingFiles]);

  const removePendingFile = useCallback((index: number) => {
    setPendingFiles((prev) => prev.filter((_, i) => i !== index));
  }, []);

  // ─── Retry handlers ───────────────────────────────────────────────────

  const handleRetryText = useCallback(
    (localId: string) => {
      const msg = messages.find((m) => m._localId === localId && m.type === 'text');
      if (!msg || msg._status !== 'failed') return;
      const text = (msg.payload as { text?: string })?.text;
      if (!text) return;
      if (!selectedDeviceId) return;
      const me = getOrCreateDeviceId();
      const outbound = userId
        ? outboundForWebChat(userId, selectedDeviceId, me)
        : outboundForGuestChat(selectedDeviceId, me);
      if (!outbound || (!userId && !outbound.toDeviceId)) return;
      updateMessageByLocalId(localId, { _status: 'sending' });
      const lengthBucket = analyticsLengthBucket(text.length);
      sendMessage({
        type: 'text',
        payload: msg.payload,
        fromDeviceId: msg.fromDeviceId,
        ts: Date.now(),
        threadKey: outbound.threadKey,
        ...(outbound.toDeviceId != null ? { toDeviceId: outbound.toDeviceId } : {}),
      })
        .then(() => {
          updateMessageByLocalId(localId, { _status: 'sent' });
          analyticsTrack(AnalyticsEvents.chatTextRetry, {
            result: 'sent',
            offline: !userId,
            channel: 'api',
            length_bucket: lengthBucket,
          });
        })
        .catch(() => {
          updateMessageByLocalId(localId, { _status: 'failed' });
          analyticsTrack(AnalyticsEvents.chatTextRetry, {
            result: 'failed',
            offline: !userId,
            channel: 'api',
            length_bucket: lengthBucket,
          });
        });
    },
    [messages, updateMessageByLocalId, userId, selectedDeviceId],
  );

  const handleRetryFile = useCallback((localId: string) => {
    cancelledTransferIdsRef.current.delete(localId);
    const info = retryInfoRef.current.get(localId);
    if (!info) return;
    switch (info.channel) {
      case 'lan':
        void sendSingleFileRef.current(info.file, true, info.targetDevices, { reuseLocalId: localId });
        break;
      case 'webrtc':
        if (info.webrtcTargetDeviceId) {
          void sendFilesViaWebRTCRef.current([info.file], info.webrtcTargetDeviceId, { reuseLocalId: localId });
        } else {
          const peerId = info.webrtcTargetDeviceId ?? selectedDeviceId;
          const peer = peerId ? devices.find((d) => d.deviceId === peerId) : undefined;
          setFileError(
            !userId
              ? 'chat.errors.webrtcRetryLogin'
              : isWebPeer(peer?.platform)
              ? 'chat.errors.webrtcRetryS3'
              : 'chat.errors.webrtcRetryHttp',
          );
        }
        break;
      default:
        void sendSingleFileRef.current(info.file, false, [], { reuseLocalId: localId });
    }
  }, [devices, selectedDeviceId, userId]);

  // ─── Message management ───────────────────────────────────────────────

  const handleDeleteMessage = useCallback(async (msg: ChatMessage) => {
    const msgId = msg.id;
    if (msgId != null) {
      try { await deleteMessage(msgId); } catch { logger.warn(TAG, 'deleteMessage failed', msgId); }
    }
    setMessages((prev) => prev.filter((m) => msg._localId ? m._localId !== msg._localId : m !== msg));
  }, []);

  // ─── Multi-select ─────────────────────────────────────────────────────

  const getMessageSelectKey = useCallback((msg: ChatMessage): string | null => {
    if (msg.id != null) return `id:${msg.id}`;
    if (msg._localId) return `local:${msg._localId}`;
    return null;
  }, []);

  const toggleMessageSelect = useCallback((key: string) => {
    setSelectedKeys((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }, []);

  const exitSelectMode = useCallback(() => {
    setSelectMode(false);
    setSelectedKeys(new Set());
  }, []);

  const toggleSelectAllMessages = useCallback(() => {
    setSelectedKeys((prev) => {
      const allKeys = messages.filter(m => belongsToConversation(m, currentDeviceId, selectedDeviceId)).map(getMessageSelectKey).filter(Boolean) as string[];
      const allSelected = allKeys.length > 0 && allKeys.every((k) => prev.has(k));
      if (allSelected) return new Set();
      return new Set(allKeys);
    });
  }, [messages, getMessageSelectKey, currentDeviceId, selectedDeviceId]);

  const enterSelectWithKey = useCallback((key: string) => {
    setSelectMode(true);
    setSelectedKeys(new Set([key]));
  }, []);

  const handleBulkDelete = useCallback(async () => {
    if (selectedKeys.size === 0) return;
    if (!window.confirm(t('chat.confirmBulkDelete', { count: selectedKeys.size }))) return;
    const keys = selectedKeys;
    for (const msg of messages) {
      const k = getMessageSelectKey(msg);
      if (!k || !keys.has(k)) continue;
      if (msg.id != null) {
        try { await deleteMessage(msg.id); } catch { logger.warn(TAG, 'bulk deleteMessage failed', msg.id); }
      }
    }
    setMessages((prev) => prev.filter((m) => { const k = getMessageSelectKey(m); return !k || !keys.has(k); }));
    exitSelectMode();
  }, [messages, selectedKeys, exitSelectMode, getMessageSelectKey, t]);

  const clearCurrentThreadMessages = useCallback(async () => {
    const uid = userIdRef.current;
    const peer = selectedDeviceIdRef.current;
    if (!peer) return;
    if (uid && peer === S3_VIRTUAL_DEVICE_ID) {
      const outbound = outboundForWebChat(uid, peer, getOrCreateDeviceId());
      if (outbound) await deleteThreadMessages(outbound.threadKey);
    }
    setMessages(prev => prev.filter(m => !belongsToConversation(m, getOrCreateDeviceId(), peer)));
    hasNoMoreRef.current = true;
  }, []);

  useEffect(() => {
    if (!selectMode) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') exitSelectMode(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [selectMode, exitSelectMode]);

  // ─── Auto-select device as target when selectedDeviceId changes ──────

  const probeSingleRef = useRef(probeSingleDevice);
  probeSingleRef.current = probeSingleDevice;

  useEffect(() => {
    if (!selectedDeviceId) return;
    if (selectedDeviceId === S3_VIRTUAL_DEVICE_ID) {
      return;
    }
    const peer = devices.find((d) => d.deviceId === selectedDeviceId);
    selectedPeerReachSnapshotRef.current = peer
      ? {
          presence: peer.presenceStatus ?? '',
          lanHttpUrl: peer.lanHttpUrl ?? '',
        }
      : null;
    setSelectedTargets((prev) => {
      if (prev.has(selectedDeviceId)) return prev;
      const next = new Set([selectedDeviceId]);
      persistSelectedTargets(next);
      return next;
    });
    probeSingleRef.current(selectedDeviceId);
  }, [selectedDeviceId, devices]);

  useEffect(() => {
    if (!selectedDeviceId || selectedDeviceId === S3_VIRTUAL_DEVICE_ID) return;
    const peer = devices.find((d) => d.deviceId === selectedDeviceId);
    if (!peer) return;

    const presence = peer.presenceStatus ?? '';
    const lanHttpUrl = peer.lanHttpUrl ?? '';
    const snap = selectedPeerReachSnapshotRef.current;
    if (!snap) return;

    let shouldProbe = false;
    if (snap.presence === 'offline' && presence !== 'offline') {
      shouldProbe = true;
    }
    if (lanHttpUrl.length > 0 && lanHttpUrl !== snap.lanHttpUrl) {
      shouldProbe = true;
    }

    selectedPeerReachSnapshotRef.current = { presence, lanHttpUrl };
    if (shouldProbe) {
      probeSingleRef.current(selectedDeviceId);
    }
  }, [selectedDeviceId, devices]);

  useEffect(() => {
    if (!selectedDeviceId) return;
    analyticsTrack(AnalyticsEvents.chatSessionOpen, {
      session_type: selectedDeviceId === S3_VIRTUAL_DEVICE_ID ? 's3' : 'peer',
    });
  }, [selectedDeviceId]);

  const addPeerByDeviceId = useCallback(async (raw: string) => {
    const peerId = normalizePeerDeviceId(raw);
    if (!peerId) {
      throw new Error('chat.errors.pairInvalid');
    }
    const me = getOrCreateDeviceId();
    if (peerId === me) {
      throw new Error('chat.errors.pairSelf');
    }
    try {
      await pairDevice(peerId);
      ingestGuestPeer({ deviceId: peerId, name: shortDeviceLabel(peerId) });
      loadDevices();
      await sendMessage({
        type: 'device_pair_hello',
        payload: { deviceId: me, name: getDeviceName(), platform: 'web' },
        fromDeviceId: me,
        toDeviceId: peerId,
        ts: Date.now(),
      });
    } catch (e) {
      logger.warn(TAG, 'addPeerByDeviceId failed', e);
      throw new Error('chat.errors.pairFailed');
    }
    setSelectedDeviceId(peerId);
    setProbeForceAll(false);
    setTargetProbeToken((x) => x + 1);
  }, [ingestGuestPeer, loadDevices]);

  // ─── Context value ────────────────────────────────────────────────────

  const value = useMemo<ChatContextValue>(() => ({
    connected,
    devices,
    currentDeviceId,
    otherDevices,
    lanDevices,
    refreshDevices,
    selectedDeviceId,
    setSelectedDeviceId,
    selectedTargets,
    toggleTarget,
    deviceReach,
    targetsProbing,
    refreshSendTargets,
    probeSingleDevice,
    runSessionConnectionDiagnostic,
    connectionDiagnostic,
    diagnosticSheetOpen,
    setDiagnosticSheetOpen,
    messages,
    sendTextMessage,
    sending,
    sendError,
    setSendError,
    fileError,
    setFileError,
    pendingFiles,
    setPendingFiles,
    handleSendFiles,
    handleFileSelect,
    addPendingFiles,
    removePendingFile,
    handleDeleteMessage,
    cancelTransfer,
    handleRetryText,
    handleRetryFile,
    loadMoreMessages,
    loadingMore,
    selectMode,
    selectedKeys,
    toggleMessageSelect,
    exitSelectMode,
    toggleSelectAllMessages,
    enterSelectWithKey,
    handleBulkDelete,
    clearCurrentThreadMessages,
    webrtcAvailable,
    isGuest: !userId,
    addPeerByDeviceId,
    s3Configured,
    s3Online,
    s3Checking,
    checkS3Config,
  }), [
    connected, devices, currentDeviceId, otherDevices, lanDevices, refreshDevices,
    selectedDeviceId, selectedTargets, toggleTarget,
    deviceReach, targetsProbing, refreshSendTargets, probeSingleDevice,
    runSessionConnectionDiagnostic, connectionDiagnostic, diagnosticSheetOpen, setDiagnosticSheetOpen,
    messages, sendTextMessage, sending, sendError, fileError,
    pendingFiles, handleSendFiles, handleFileSelect, addPendingFiles, removePendingFile,
    handleDeleteMessage, cancelTransfer, handleRetryText, handleRetryFile,
    loadMoreMessages, loadingMore,
    selectMode, selectedKeys, toggleMessageSelect, exitSelectMode, toggleSelectAllMessages, enterSelectWithKey, handleBulkDelete, clearCurrentThreadMessages,
    webrtcAvailable, userId, addPeerByDeviceId, s3Configured, s3Online, s3Checking, checkS3Config,
  ]);

  return <ChatContext.Provider value={value}>{children}</ChatContext.Provider>;
}
