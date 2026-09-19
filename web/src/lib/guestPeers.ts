import type { DeviceDto } from '@/lib/api/devices';
import { shortDeviceLabel } from '@/lib/devicePair';

const KEY = 'ultrasend_guest_peers';

export type GuestPeer = {
  deviceId: string;
  name: string;
  platform?: string | null;
};

function readRaw(): unknown {
  if (typeof window === 'undefined') return [];
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return [];
    return JSON.parse(raw);
  } catch {
    return [];
  }
}

export function loadGuestPeers(): GuestPeer[] {
  const parsed = readRaw();
  if (!Array.isArray(parsed)) return [];
  const out: GuestPeer[] = [];
  const seen = new Set<string>();
  for (const item of parsed) {
    if (!item || typeof item !== 'object') continue;
    const deviceId = typeof (item as GuestPeer).deviceId === 'string'
      ? (item as GuestPeer).deviceId.trim()
      : '';
    if (!deviceId || seen.has(deviceId)) continue;
    seen.add(deviceId);
    const name =
      typeof (item as GuestPeer).name === 'string' && (item as GuestPeer).name.trim()
        ? (item as GuestPeer).name.trim()
        : shortDeviceLabel(deviceId);
    const platform =
      typeof (item as GuestPeer).platform === 'string' ? (item as GuestPeer).platform : null;
    out.push({ deviceId, name, platform });
  }
  return out;
}

function persist(peers: GuestPeer[]): void {
  if (typeof window === 'undefined') return;
  try {
    localStorage.setItem(KEY, JSON.stringify(peers));
  } catch {
    // Ignore quota / private-mode failures; roster still lives in memory.
  }
}

export function upsertGuestPeer(peer: GuestPeer): GuestPeer[] {
  const deviceId = peer.deviceId.trim();
  if (!deviceId) return loadGuestPeers();
  const next = loadGuestPeers().filter((p) => p.deviceId !== deviceId);
  next.push({
    deviceId,
    name: peer.name.trim() || shortDeviceLabel(deviceId),
    platform: peer.platform ?? null,
  });
  persist(next);
  return next;
}

export function guestPeerToDeviceDto(peer: GuestPeer): DeviceDto {
  return {
    deviceId: peer.deviceId,
    name: peer.name,
    platform: peer.platform ?? null,
    presenceStatus: 'online',
  };
}

export function mergeDeviceRosters(account: DeviceDto[], guests: GuestPeer[]): DeviceDto[] {
  const byId = new Map<string, DeviceDto>();
  for (const g of guests) {
    byId.set(g.deviceId, guestPeerToDeviceDto(g));
  }
  for (const d of account) {
    byId.set(d.deviceId, d);
  }
  return [...byId.values()];
}
