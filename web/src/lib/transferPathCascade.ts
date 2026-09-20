/** Send-time transfer hops, ordered by expected speed. */
export type TransferHop = 'httpPush' | 'httpPull' | 'webrtc' | 's3';

export type TransferChannel = 'lan' | 'webrtc' | 's3';

/** Runtime UI phase while the send cascade probes and then transfers. */
export type TransferPhase =
  | 'tryingHttp'
  | 'waitingPull'
  | 'connectingWebrtc'
  | 'connectingWebrtcFallback'
  | 'tryingS3'
  | 'tryingS3Fallback'
  | 'sendingHttp'
  | 'sendingWebrtc'
  | 'sendingS3';

export function isConnectingTransferPhase(phase?: string | null): boolean {
  return (
    phase === 'tryingHttp' ||
    phase === 'waitingPull' ||
    phase === 'connectingWebrtc' ||
    phase === 'connectingWebrtcFallback' ||
    phase === 'tryingS3' ||
    phase === 'tryingS3Fallback'
  );
}

export function channelOfTransferPhase(phase?: string | null): TransferChannel | undefined {
  switch (phase) {
    case 'tryingHttp':
    case 'waitingPull':
    case 'sendingHttp':
      return 'lan';
    case 'connectingWebrtc':
    case 'connectingWebrtcFallback':
    case 'sendingWebrtc':
      return 'webrtc';
    case 'tryingS3':
    case 'tryingS3Fallback':
    case 'sendingS3':
      return 's3';
    default:
      return undefined;
  }
}

export function fileTransferTypeFromPayload(payload: unknown): TransferChannel | undefined {
  if (!payload || typeof payload !== 'object') return undefined;
  const p = payload as {
    lan?: boolean;
    webrtc?: boolean;
    key?: string;
    targetDeviceIds?: unknown;
  };
  if (p.lan === true) return 'lan';
  if (p.webrtc === true) return 'webrtc';
  if (typeof p.key === 'string' && p.key.length > 0) return 's3';
  if (Array.isArray(p.targetDeviceIds) && p.targetDeviceIds.length > 0) return 'lan';
  return undefined;
}

export type TransferPathInput = {
  localIsWeb: boolean;
  peerIsWeb: boolean;
  isLoggedIn: boolean;
  webrtcAvailable: boolean;
  s3Configured: boolean;
  s3Online: boolean;
  isS3VirtualSession?: boolean;
};

/**
 * Hops that can be attempted for this pair, fastest first.
 *
 * Direction rules:
 * - Web → App: httpPush only (browser cannot serve reverse-pull)
 * - App → Web: httpPull only (browser cannot receive POST /transfer)
 * - Web → Web: skip HTTP
 * - Guest: same HTTP direction; S3 omitted
 */
export function applicableTransferHops(input: TransferPathInput): TransferHop[] {
  if (input.isS3VirtualSession) {
    if (input.isLoggedIn && input.s3Configured && input.s3Online) return ['s3'];
    return [];
  }

  const hops: TransferHop[] = [];
  if (!input.peerIsWeb) hops.push('httpPush');
  if (!input.localIsWeb) hops.push('httpPull');
  if (input.webrtcAvailable) hops.push('webrtc');
  if (input.isLoggedIn && input.s3Configured && input.s3Online) hops.push('s3');
  return hops;
}

export function transferChannelLabel(type?: string | null): string {
  switch (type) {
    case 'lan':
      return 'HTTP';
    case 'webrtc':
      return 'WebRTC';
    case 's3':
      return 'S3';
    default:
      return '';
  }
}

export function transferPhaseMessageKey(phase?: string | null): string | undefined {
  switch (phase) {
    case 'tryingHttp':
      return 'chat.bubble.phaseTryingHttp';
    case 'waitingPull':
      return 'chat.bubble.phaseWaitingPull';
    case 'connectingWebrtc':
      return 'chat.bubble.phaseConnectingWebrtc';
    case 'connectingWebrtcFallback':
      return 'chat.bubble.phaseConnectingWebrtcFallback';
    case 'tryingS3':
      return 'chat.bubble.phaseTryingS3';
    case 'tryingS3Fallback':
      return 'chat.bubble.phaseTryingS3Fallback';
    default:
      return undefined;
  }
}

/** Directed `toDeviceId` wins; otherwise match `payload.targetDeviceIds`. */
export function isLanFileOfferForMe(opts: {
  me: string;
  toDeviceId?: string | null;
  targetDeviceIds?: unknown;
}): boolean {
  const { me, toDeviceId, targetDeviceIds } = opts;
  if (typeof toDeviceId === 'string' && toDeviceId.length > 0) {
    return toDeviceId === me;
  }
  return Array.isArray(targetDeviceIds) && targetDeviceIds.includes(me);
}

export function hopsIncludeHttp(hops: TransferHop[]): boolean {
  return hops.includes('httpPush') || hops.includes('httpPull');
}

export class TransferHopSkipCache {
  private readonly failedAt = new Map<string, Map<TransferHop, number>>();

  constructor(private readonly ttlMs = 20_000) {}

  markFailed(peerId: string, hop: TransferHop): void {
    let byHop = this.failedAt.get(peerId);
    if (!byHop) {
      byHop = new Map();
      this.failedAt.set(peerId, byHop);
    }
    byHop.set(hop, Date.now());
  }

  markSucceeded(peerId: string, hop: TransferHop): void {
    this.failedAt.get(peerId)?.delete(hop);
  }

  shouldSkip(peerId: string, hop: TransferHop): boolean {
    const at = this.failedAt.get(peerId)?.get(hop);
    if (at == null) return false;
    if (Date.now() - at > this.ttlMs) {
      this.failedAt.get(peerId)?.delete(hop);
      return false;
    }
    return true;
  }

  filter(peerId: string, hops: TransferHop[]): TransferHop[] {
    return hops.filter((hop) => !this.shouldSkip(peerId, hop));
  }
}
