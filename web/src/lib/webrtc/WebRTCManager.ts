import { createReceiveSink, type ReceiveSink } from '@/lib/receiveFiles';
import { TransferAcknowledgements } from './TransferAcknowledgements';
import { logger } from '@/lib/logger';
import { getOrCreateDeviceId, generateUUID } from '@/lib/deviceId';
import { sendSignal } from './SignalingChannel';
import type { WebRTCSignal, WebRTCOffer, WebRTCAnswer, WebRTCIceCandidate, WebRTCTransferCancel } from './SignalingChannel';

const TAG = 'WebRTCManager';
const ICE_TIMEOUT_MS = 15_000;
const CHUNK_SIZE = 16 * 1024;
const HIGH_WATER_MARK = 1024 * 1024;
const LOW_WATER_MARK = 256 * 1024;
const MAX_IN_FLIGHT_BYTES = 4 * 1024 * 1024;

const RTC_CONFIG: RTCConfiguration = {
  iceServers: [
    { urls: 'stun:stun.miwifi.com:3478' },
    { urls: 'stun:stun.qq.com:3478' },
    { urls: 'stun:stun.l.google.com:19302' },
  ],
};

export type FileMetadata = {
  fileId: string;
  fileName: string;
  fileSize: number;
  mimeType: string;
  /**
   * Sender-assigned per-transfer local id (UUID). Mirrored into the WebRTC
   * offer + `file_start` control message so the receiver can dedup the
   * Centrifugo `file` publication (whose payload also carries `localId`)
   * against its local receiver-side bubble. Optional for backward compat
   * with older peers.
   */
  senderLocalId?: string;
};

export type TransferProgressCallback = (fileId: string, received: number, total: number) => void;
export type FileReceivedCallback = (fileId: string, fileName: string, blob: Blob | null) => void;
export type FileSentCallback = (fileId: string, fileName: string) => void;
export type FileFailedCallback = (fileId: string, fileName: string, error: string) => void;
export type ConnectionStateCallback = (state: 'connecting' | 'connected' | 'disconnected' | 'failed') => void;

type PendingSend = {
  file: File;
  meta: FileMetadata;
};

type ReceiveState = {
  meta: FileMetadata;
  chunks: ArrayBuffer[];
  received: number;
  pendingFinalize: boolean;
  sink?: ReceiveSink;
  pendingWrite?: Promise<void>;
  writeError?: unknown;
  finalizing?: boolean;
};

export class WebRTCSession {
  readonly sessionId: string;
  readonly remoteDeviceId: string;
  readonly localDeviceId: string;
  private pc: RTCPeerConnection;
  private controlChannel: RTCDataChannel | null = null;
  private iceCandidateBuffer: RTCIceCandidateInit[] = [];
  private remoteDescriptionSet = false;
  private sendingStarted = false;
  private closed = false;
  private connectionTimeout: ReturnType<typeof setTimeout> | null = null;

  private pendingSends: PendingSend[] = [];
  private receiveStates = new Map<string, ReceiveState>();
  private fileDataChannels = new Map<string, RTCDataChannel>();
  private acknowledgements = new TransferAcknowledgements();
  private receiverConfirmed = new Map<string, number>();
  private flowControlResolvers = new Map<string, () => void>();
  private cancelledFiles = new Set<string>();
  private resumeOffsets = new Map<string, number>();
  private resumeResolvers = new Map<string, (offset: number) => void>();

  onProgress: TransferProgressCallback | null = null;
  onFileReceived: FileReceivedCallback | null = null;
  onFileSent: FileSentCallback | null = null;
  onFileFailed: FileFailedCallback | null = null;
  onStateChange: ConnectionStateCallback | null = null;

  private _resolveConnected: (() => void) | null = null;
  private _rejectConnected: ((err: Error) => void) | null = null;
  readonly connected: Promise<void>;

  /** Resolves when outbound file sends finish (or session closes / send pipeline ends). */
  private _resolveSendsFinished: (() => void) | null = null;
  private _rejectSendsFinished: ((error: Error) => void) | null = null;
  readonly sendsFinished: Promise<void>;

  constructor(sessionId: string, remoteDeviceId: string) {
    this.sessionId = sessionId;
    this.remoteDeviceId = remoteDeviceId;
    this.localDeviceId = getOrCreateDeviceId();
    this.pc = new RTCPeerConnection(RTC_CONFIG);

    this.connected = new Promise<void>((resolve, reject) => {
      this._resolveConnected = resolve;
      this._rejectConnected = reject;
    });

    void this.connected.catch(() => {});

    this.sendsFinished = new Promise<void>((resolve, reject) => {
      this._resolveSendsFinished = resolve;
      this._rejectSendsFinished = reject;
    });
    // Receiving sessions have no caller awaiting this promise.
    void this.sendsFinished.catch(() => {});

    this.pc.onicecandidate = (e) => {
      if (e.candidate) {
        sendSignal({
          type: 'webrtc_ice_candidate',
          sessionId: this.sessionId,
          senderDeviceId: this.localDeviceId,
          targetDeviceId: this.remoteDeviceId,
          candidate: e.candidate.toJSON(),
        }).catch((err) => logger.warn(TAG, 'sendIceCandidate failed', err));
      }
    };

    this.pc.onconnectionstatechange = () => {
      const state = this.pc.connectionState;
      logger.info(TAG, `connectionState=${state} session=${this.sessionId}`);
      if (state === 'connected') {
        this.clearConnectionTimeout();
        this.onStateChange?.('connected');
        this._resolveConnected?.();
      } else if (state === 'failed' || state === 'closed') {
        this.clearConnectionTimeout();
        this.onStateChange?.('failed');
        this._rejectConnected?.(new Error(`Connection ${state}`));
        this.close();
      } else if (state === 'disconnected') {
        this.onStateChange?.('disconnected');
      }
    };

    this.pc.ondatachannel = (e) => {
      const dc = e.channel;
      logger.info(TAG, `ondatachannel label=${dc.label}`);
      if (dc.label === 'control') {
        this.controlChannel = dc;
        this.setupControlChannel(dc);
      } else if (dc.label.startsWith('file-')) {
        const fileId = dc.label.substring(5);
        this.fileDataChannels.set(fileId, dc);
        this.setupFileReceiveChannel(dc, fileId);
      }
    };
  }

  private startConnectionTimeout(): void {
    this.connectionTimeout = setTimeout(() => {
      if (this.pc.connectionState !== 'connected') {
        logger.warn(TAG, `ICE timeout after ${ICE_TIMEOUT_MS}ms session=${this.sessionId}`);
        this.onStateChange?.('failed');
        this._rejectConnected?.(new Error('ICE connection timeout'));
        this.close();
      }
    }, ICE_TIMEOUT_MS);
  }

  private clearConnectionTimeout(): void {
    if (this.connectionTimeout) {
      clearTimeout(this.connectionTimeout);
      this.connectionTimeout = null;
    }
  }

  private fileChannelReadyPromises = new Map<string, Promise<void>>();

  async createOffer(files: PendingSend[]): Promise<void> {
    this.pendingSends = files;
    this.onStateChange?.('connecting');

    const dc = this.pc.createDataChannel('control');
    this.controlChannel = dc;
    this.setupControlChannel(dc);

    for (const f of files) {
      const fdc = this.pc.createDataChannel(`file-${f.meta.fileId}`, { ordered: true });
      this.fileDataChannels.set(f.meta.fileId, fdc);
      const ready = new Promise<void>((resolve, reject) => {
        const timeout = setTimeout(() => reject(new Error('File DataChannel open timeout')), ICE_TIMEOUT_MS + 5_000);
        if (fdc.readyState === 'open') {
          clearTimeout(timeout);
          resolve();
        } else {
          fdc.onopen = () => { clearTimeout(timeout); resolve(); };
        }
      });
      ready.catch(() => {});
      this.fileChannelReadyPromises.set(f.meta.fileId, ready);
    }

    const offer = await this.pc.createOffer();
    await this.pc.setLocalDescription(offer);
    this.remoteDescriptionSet = false;

    await sendSignal({
      type: 'webrtc_offer',
      sessionId: this.sessionId,
      senderDeviceId: this.localDeviceId,
      targetDeviceId: this.remoteDeviceId,
      sdp: offer.sdp!,
      files: files.map((f) => f.meta),
    });

    this.startConnectionTimeout();
  }

  async handleOffer(signal: WebRTCOffer): Promise<void> {
    this.onStateChange?.('connecting');

    for (const fileMeta of signal.files) {
      this.receiveStates.set(fileMeta.fileId, {
        meta: fileMeta,
        chunks: [],
        received: 0,
        pendingFinalize: false,
      });
    }

    await this.pc.setRemoteDescription({ type: 'offer', sdp: signal.sdp });
    this.remoteDescriptionSet = true;
    await this.flushIceCandidateBuffer();

    const answer = await this.pc.createAnswer();
    await this.pc.setLocalDescription(answer);

    await sendSignal({
      type: 'webrtc_answer',
      sessionId: this.sessionId,
      senderDeviceId: this.localDeviceId,
      targetDeviceId: this.remoteDeviceId,
      sdp: answer.sdp!,
    });

    this.startConnectionTimeout();
  }

  async handleAnswer(signal: WebRTCAnswer): Promise<void> {
    await this.pc.setRemoteDescription({ type: 'answer', sdp: signal.sdp });
    this.remoteDescriptionSet = true;
    await this.flushIceCandidateBuffer();
  }

  async handleIceCandidate(signal: WebRTCIceCandidate): Promise<void> {
    if (this.remoteDescriptionSet) {
      await this.pc.addIceCandidate(new RTCIceCandidate(signal.candidate));
    } else {
      this.iceCandidateBuffer.push(signal.candidate);
    }
  }

  handleTransferCancel(signal: WebRTCTransferCancel): void {
    if (signal.sessionId !== this.sessionId) return;
    logger.info(TAG, `transfer cancelled by remote session=${this.sessionId}`);
    this.close();
  }

  hasFile(fileId: string): boolean {
    return this.receiveStates.has(fileId) || this.pendingSends.some(item => item.meta.fileId === fileId);
  }

  cancelFile(fileId: string, notifyRemote = true): void {
    if (this.cancelledFiles.has(fileId)) return;
    this.cancelledFiles.add(fileId);
    if (notifyRemote) this.sendControlMessage({ type: 'file_cancel', fileId });
    this.acknowledgements.settle(fileId, false, 'Transfer cancelled');
    this.flowControlResolvers.get(fileId)?.();
    this.flowControlResolvers.delete(fileId);
    this.resumeResolvers.get(fileId)?.(0);
    this.resumeResolvers.delete(fileId);
    this.fileDataChannels.get(fileId)?.close();
    const receiving = this.receiveStates.get(fileId);
    if (receiving) {
      this.receiveStates.delete(fileId);
      void (receiving.pendingWrite ?? Promise.resolve()).then(() => receiving.sink?.abort()).catch(() => {});
      this.onFileFailed?.(fileId, receiving.meta.fileName, 'Transfer cancelled');
    }
  }

  private async flushIceCandidateBuffer(): Promise<void> {
    for (const c of this.iceCandidateBuffer) {
      await this.pc.addIceCandidate(new RTCIceCandidate(c));
    }
    this.iceCandidateBuffer = [];
  }

  private setupControlChannel(dc: RTCDataChannel): void {
    dc.onopen = () => {
      logger.info(TAG, 'control channel open');
      this.tryStartSending();
    };
    dc.onmessage = (e) => {
      try {
        const msg = JSON.parse(e.data);
        this.handleControlMessage(msg);
      } catch (err) {
        logger.warn(TAG, 'control message parse error', err);
      }
    };
    dc.onclose = () => {
      logger.info(TAG, 'control channel closed');
      if (!this.sendingStarted) this.finishSendsLifecycle();
    };
    if (dc.readyState === 'open') {
      this.tryStartSending();
    }
  }

  private finishSendsLifecycle(error?: Error): void {
    if (!this._resolveSendsFinished) return;
    const r = this._resolveSendsFinished;
    this._resolveSendsFinished = null;
    if (error) this._rejectSendsFinished?.(error);
    else r();
    this._rejectSendsFinished = null;
  }

  private tryStartSending(): void {
    if (this.sendingStarted) return;
    if (this.pendingSends.length === 0) {
      this.finishSendsLifecycle();
      return;
    }
    this.sendingStarted = true;
    logger.info(TAG, `starting file sends (${this.pendingSends.length} files)`);
    void this.startSendingFiles()
      .then(() => this.finishSendsLifecycle())
      .catch((err) => this.finishSendsLifecycle(err instanceof Error ? err : new Error(String(err))));
  }

  private handleControlMessage(msg: {
    type: string;
    fileId?: string;
    fileName?: string;
    fileSize?: number;
    mimeType?: string;
    checksum?: string;
    success?: boolean;
    received?: number;
    receivedBytes?: number;
    error?: string;
    senderLocalId?: string;
  }): void {
    switch (msg.type) {
      case 'file_start': {
        if (!msg.fileId) break;
        if (!this.receiveStates.has(msg.fileId)) {
          this.receiveStates.set(msg.fileId, {
            meta: {
              fileId: msg.fileId,
              fileName: msg.fileName ?? 'unknown',
              fileSize: msg.fileSize ?? 0,
              mimeType: msg.mimeType ?? 'application/octet-stream',
              senderLocalId: msg.senderLocalId,
            },
            chunks: [],
            received: 0,
            pendingFinalize: false,
          });
        }
        break;
      }
      case 'file_end': {
        if (!msg.fileId) break;
        const state = this.receiveStates.get(msg.fileId);
        if (state) {
          if (state.received >= state.meta.fileSize) {
            this.finalizeReceivedFile(msg.fileId, state);
          } else {
            logger.info(TAG, `file_end received but data incomplete: ${state.received}/${state.meta.fileSize}, deferring finalize`);
            state.pendingFinalize = true;
          }
        }
        break;
      }
      case 'file_cancel': {
        if (msg.fileId) this.cancelFile(msg.fileId, false);
        break;
      }
      case 'file_ack': {
        logger.info(TAG, `file_ack fileId=${msg.fileId} success=${msg.success}`);
        this.acknowledgements.settle(msg.fileId ?? '', msg.success === true, msg.error);

        break;
      }
      case 'progress': {
        if (msg.fileId) {
          this.receiverConfirmed.set(msg.fileId, msg.received ?? 0);
          const resolver = this.flowControlResolvers.get(msg.fileId);
          if (resolver) {
            this.flowControlResolvers.delete(msg.fileId);
            resolver();
          }
        }
        logger.debug(TAG, `receiver progress fileId=${msg.fileId} received=${msg.received}`);
        break;
      }
      case 'file_resume_request': {
        if (msg.fileId) {
          const receivedBytes = msg.receivedBytes ?? 0;
          logger.info(TAG, `file_resume_request fileId=${msg.fileId} receivedBytes=${receivedBytes}`);
          this.resumeOffsets.set(msg.fileId, receivedBytes);
          this.sendControlMessage({
            type: 'file_resume_accept',
            fileId: msg.fileId,
            offset: receivedBytes,
          });
          const resolver = this.resumeResolvers.get(msg.fileId);
          if (resolver) {
            resolver(receivedBytes);
            this.resumeResolvers.delete(msg.fileId);
          }
        }
        break;
      }
      case 'file_resume_accept': {
        if (msg.fileId) {
          const offset = (msg as { offset?: number }).offset ?? 0;
          logger.info(TAG, `file_resume_accept fileId=${msg.fileId} offset=${offset}`);
          this.resumeOffsets.set(msg.fileId, offset);
        }
        break;
      }
      case 'session_complete': {
        logger.info(TAG, 'session complete');
        break;
      }
    }
  }

  private sendControlMessage(msg: Record<string, unknown>): void {
    if (this.controlChannel?.readyState === 'open') {
      this.controlChannel.send(JSON.stringify(msg));
    } else {
      logger.warn(TAG, `control channel not open, dropping message type=${msg.type}`);
    }
  }

  private async startSendingFiles(): Promise<void> {
    const queue = [...this.pendingSends];
    const failures: unknown[] = [];
    await Promise.all(Array.from({ length: Math.min(4, queue.length) }, async () => {
      while (queue.length) {
        const pending = queue.shift()!;
        try { await this.sendSingleFile(pending); }
        catch (error) { failures.push(error); }
      }
    }));
    if (failures.length) throw new Error(`${failures.length} file transfer(s) failed: ${failures[0]}`);
    this.sendControlMessage({ type: 'session_complete' });
  }

  private async sendSingleFile(pending: PendingSend): Promise<void> {
    const { file, meta } = pending;

    try {
      if (this.cancelledFiles.has(meta.fileId)) throw new Error('Transfer cancelled');
      logger.info(TAG, `sendSingleFile start fileId=${meta.fileId} name=${meta.fileName}`);

      this.sendControlMessage({
        type: 'file_start',
        fileId: meta.fileId,
        fileName: meta.fileName,
        fileSize: meta.fileSize,
        mimeType: meta.mimeType,
        senderLocalId: meta.senderLocalId,
      });

      const dc = this.fileDataChannels.get(meta.fileId);
      if (!dc) throw new Error(`File DataChannel not found for fileId=${meta.fileId}`);

      const readyPromise = this.fileChannelReadyPromises.get(meta.fileId);
      if (readyPromise) {
        await readyPromise;
      }

      logger.info(TAG, `file channel ready state=${dc.readyState} fileId=${meta.fileId}`);

      // Wait briefly for a possible resume request from the receiver.
      let resumeOffset = this.resumeOffsets.get(meta.fileId) ?? 0;
      if (resumeOffset === 0) {
        resumeOffset = await new Promise<number>((resolve) => {
          this.resumeResolvers.set(meta.fileId, resolve);
          setTimeout(() => {
            this.resumeResolvers.delete(meta.fileId);
            resolve(0);
          }, 500);
        });
      }
      if (resumeOffset > 0) {
        logger.info(TAG, `WebRTC resume from offset=${resumeOffset} fileId=${meta.fileId}`);
      }

      dc.bufferedAmountLowThreshold = LOW_WATER_MARK;
      let offset = resumeOffset;
      let chunkCount = 0;
      let readStart = resumeOffset;
      let readBuffer = new ArrayBuffer(0);
      let channelClosed = false;

      dc.onclose = () => {
        channelClosed = true;
        const fcResolver = this.flowControlResolvers.get(meta.fileId);
        if (fcResolver) {
          this.flowControlResolvers.delete(meta.fileId);
          fcResolver();
        }
      };

      while (offset < file.size) {
        if (this.cancelledFiles.has(meta.fileId)) throw new Error('Transfer cancelled');
        if (channelClosed || dc.readyState !== 'open') {
          throw new Error('DataChannel closed during send');
        }

        // Read in bounded 1 MiB blocks; keep 16 KiB wire frames for peers
        // with small SCTP limits. Avoid one asynchronous disk read per frame.
        if (offset >= readStart + readBuffer.byteLength) {
          readStart = offset;
          readBuffer = await file.slice(offset, Math.min(offset + 1024 * 1024, file.size)).arrayBuffer();
        }
        const end = Math.min(offset + CHUNK_SIZE, file.size);
        dc.send(new Uint8Array(readBuffer, offset - readStart, end - offset));
        offset = end;
        chunkCount++;

        if (chunkCount % 4 === 0) {
          // Blob reads already yield to the event loop. Timer-based yielding
          // is throttled in background tabs and needlessly caps throughput.
          // 本地 bufferedAmount 背压
          if (dc.bufferedAmount > HIGH_WATER_MARK) {
            logger.info(TAG, `backpressure: pausing send, buffered=${dc.bufferedAmount}`);
            await new Promise<void>((resolve, reject) => {
              const drainTimeout = setTimeout(() => {
                reject(new Error(`Buffer drain timeout fileId=${meta.fileId}`));
              }, 30_000);
              dc.onbufferedamountlow = () => {
                clearTimeout(drainTimeout);
                resolve();
              };
              const prevOnClose = dc.onclose;
              dc.onclose = () => {
                clearTimeout(drainTimeout);
                channelClosed = true;
                prevOnClose?.call(dc, new Event('close'));
                reject(new Error('DataChannel closed while waiting for drain'));
              };
            });
            logger.info(TAG, `backpressure: resumed, buffered=${dc.bufferedAmount}`);
          }

          // 端到端流控：限制在途数据量，防止远端 SCTP 缓冲区溢出
          const confirmed = this.receiverConfirmed.get(meta.fileId) ?? 0;
          const inFlight = offset - confirmed;
          if (inFlight > MAX_IN_FLIGHT_BYTES) {
            logger.info(TAG, `flow control: pausing, sent=${offset} confirmed=${confirmed} inFlight=${inFlight}`);
            await new Promise<void>((resolve, reject) => {
              const fcTimeout = setTimeout(() => {
                this.flowControlResolvers.delete(meta.fileId);
                reject(new Error(`Receiver stopped acknowledging data fileId=${meta.fileId}`));
              }, 30_000);
              this.flowControlResolvers.set(meta.fileId, () => {
                clearTimeout(fcTimeout);
                resolve();
              });
            });
            logger.info(TAG, `flow control: resumed, confirmed=${this.receiverConfirmed.get(meta.fileId) ?? 0}`);
          }

          if (channelClosed) {
            throw new Error('DataChannel closed during send');
          }

          this.onProgress?.(meta.fileId, offset, meta.fileSize);
        }
      }
      this.onProgress?.(meta.fileId, offset, meta.fileSize);

      const acknowledgement = this.acknowledgements.wait(meta.fileId);
      this.sendControlMessage({ type: 'file_end', fileId: meta.fileId });
      await acknowledgement;

      logger.info(TAG, `file ack received fileId=${meta.fileId} name=${meta.fileName}`);
      this.onFileSent?.(meta.fileId, meta.fileName);
    } catch (err) {
      logger.warn(TAG, `sendSingleFile failed fileId=${meta.fileId}`, err);
      const failure = this.cancelledFiles.has(meta.fileId) ? new Error('Transfer cancelled') : err;
      this.onFileFailed?.(meta.fileId, meta.fileName, String(failure));
      throw failure;
    } finally {
      this.fileChannelReadyPromises.delete(meta.fileId);
    }
  }

  private flushReceivedChunks(fileId: string, state: ReceiveState): Promise<void> {
    const chunks = state.chunks.splice(0);
    const received = state.received;
    state.pendingWrite = (state.pendingWrite ?? Promise.resolve()).then(async () => {
      if (state.writeError) return;
      state.sink ??= await createReceiveSink(state.meta.fileName, state.meta.mimeType);
      if (chunks.length) await state.sink.write(new Blob(chunks));
      this.sendControlMessage({ type: 'progress', fileId, received });
    }).catch((error: unknown) => { state.writeError = error; });
    return state.pendingWrite;
  }

  private async finalizeReceivedFile(fileId: string, state: ReceiveState): Promise<void> {
    if (state.finalizing) return;
    state.finalizing = true;
    try {
      await this.flushReceivedChunks(fileId, state);
      if (state.writeError) throw state.writeError;
      if (this.cancelledFiles.has(fileId)) throw new Error('Transfer cancelled');
      if (this.closed) throw new Error('Connection closed during receive');
      if (state.received !== state.meta.fileSize) throw new Error('File size mismatch');
      await state.sink!.finish();
      this.onFileReceived?.(fileId, state.meta.fileName, null);
      this.sendControlMessage({ type: 'file_ack', fileId, success: true });
    } catch (error) {
      await state.sink?.abort().catch(() => {});
      this.sendControlMessage({ type: 'file_ack', fileId, success: false, error: String(error) });
      this.onFileFailed?.(fileId, state.meta.fileName, String(error));
    } finally {
      this.receiveStates.delete(fileId);
    }
  }

  private setupFileReceiveChannel(dc: RTCDataChannel, fileId: string): void {
    dc.binaryType = 'arraybuffer';
    dc.onmessage = (e) => {
      const state = this.receiveStates.get(fileId);
      if (!state) return;
      const data = e.data as ArrayBuffer;
      state.chunks.push(data);
      state.received += data.byteLength;
      this.onProgress?.(fileId, state.received, state.meta.fileSize);

      // Confirm every ~256KB to stay well under sender's 4MB flow-control threshold.
      const progressInterval = 256 * 1024;
      if (state.received >= state.meta.fileSize || state.received % progressInterval < data.byteLength) {
        void this.flushReceivedChunks(fileId, state);
      }

      if (state.pendingFinalize && state.received >= state.meta.fileSize) {
        this.finalizeReceivedFile(fileId, state);
      }
    };
    dc.onclose = () => {
      logger.debug(TAG, `file channel closed fileId=${fileId}`);
    };
  }

  close(): void {
    if (this.closed) return;
    this.closed = true;
    this.pc.onconnectionstatechange = null;
    this.clearConnectionTimeout();
    this.acknowledgements.close();
    for (const dc of this.fileDataChannels.values()) {
      dc.close();
    }
    this.fileDataChannels.clear();
    this.controlChannel?.close();
    this.pc.close();
    for (const [fileId, state] of this.receiveStates) {
      if (state.finalizing) continue;
      void (state.pendingWrite ?? Promise.resolve()).then(() => state.sink?.abort()).catch(() => {});
      this.onFileFailed?.(fileId, state.meta.fileName, 'Connection closed during receive');
    }
    this.receiveStates.clear();
    this.finishSendsLifecycle(new Error('Connection closed during transfer'));
    logger.info(TAG, `session closed session=${this.sessionId}`);
  }
}

type SessionEntry = {
  session: WebRTCSession;
  remoteDeviceId: string;
};

export class WebRTCManager {
  private sessions = new Map<string, SessionEntry>();

  onProgress: TransferProgressCallback | null = null;
  onFileReceived: FileReceivedCallback | null = null;
  onFileSent: FileSentCallback | null = null;
  onFileFailed: ((fileId: string, fileName: string, error: string) => void) | null = null;
  onStateChange: ((sessionId: string, state: 'connecting' | 'connected' | 'disconnected' | 'failed') => void) | null = null;

  private createSession(sessionId: string, remoteDeviceId: string): WebRTCSession {
    const existing = this.sessions.get(sessionId);
    if (existing) {
      existing.session.close();
    }
    const session = new WebRTCSession(sessionId, remoteDeviceId);
    session.onProgress = (fileId, received, total) => this.onProgress?.(fileId, received, total);
    session.onFileReceived = (fileId, fileName, blob) => this.onFileReceived?.(fileId, fileName, blob);
    session.onFileSent = (fileId, fileName) => this.onFileSent?.(fileId, fileName);
    session.onFileFailed = (fileId, fileName, error) => this.onFileFailed?.(fileId, fileName, error);
    session.onStateChange = (state) => this.onStateChange?.(sessionId, state);
    this.sessions.set(sessionId, { session, remoteDeviceId });
    return session;
  }

  async initiateTransfer(
    targetDeviceId: string,
    files: Array<{ file: File; meta: FileMetadata }>,
  ): Promise<WebRTCSession> {
    const sessionId = generateUUID();
    const session = this.createSession(sessionId, targetDeviceId);
    await session.createOffer(files);
    return session;
  }

  handleSignal(signal: WebRTCSignal): void {
    const myDeviceId = getOrCreateDeviceId();
    if (signal.targetDeviceId !== myDeviceId) return;

    switch (signal.type) {
      case 'webrtc_offer': {
        const offer = signal as unknown as WebRTCOffer;
        const session = this.createSession(offer.sessionId, offer.senderDeviceId);
        session.handleOffer(offer).catch((err) => {
          logger.warn(TAG, 'handleOffer failed', err);
          session.close();
        });
        break;
      }
      case 'webrtc_answer': {
        const answer = signal as unknown as WebRTCAnswer;
        const entry = this.sessions.get(answer.sessionId);
        if (entry) {
          entry.session.handleAnswer(answer).catch((err) =>
            logger.warn(TAG, 'handleAnswer failed', err),
          );
        }
        break;
      }
      case 'webrtc_ice_candidate': {
        const ice = signal as unknown as WebRTCIceCandidate;
        const entry = this.sessions.get(ice.sessionId);
        if (entry) {
          entry.session.handleIceCandidate(ice).catch((err) =>
            logger.warn(TAG, 'handleIceCandidate failed', err),
          );
        }
        break;
      }
      case 'webrtc_transfer_cancel': {
        const cancel = signal as unknown as WebRTCTransferCancel;
        const entry = this.sessions.get(cancel.sessionId);
        if (entry) {
          entry.session.handleTransferCancel(cancel);
          this.sessions.delete(cancel.sessionId);
        }
        break;
      }
    }
  }

  cancelTransferByFileId(fileId: string): void {
    for (const { session } of this.sessions.values()) {
      if (session.hasFile(fileId)) { session.cancelFile(fileId); return; }
    }
  }

  removeSession(sessionId: string): void {
    const entry = this.sessions.get(sessionId);
    if (entry) {
      entry.session.close();
      this.sessions.delete(sessionId);
    }
  }

  closeAll(): void {
    for (const entry of this.sessions.values()) {
      entry.session.close();
    }
    this.sessions.clear();
  }
}
