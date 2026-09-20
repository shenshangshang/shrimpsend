/** Send-time transfer hops, ordered by expected speed. */
export type TransferHop = 'httpPush' | 'httpPull' | 'webrtc' | 's3';

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
