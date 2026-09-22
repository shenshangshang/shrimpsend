import type { DeviceDto } from '@/lib/api/devices';
import { shortDeviceLabel } from './devicePair';

const KEY = 'ultrasend_guest_peers';

export type GuestPeer = {
  deviceId: string;
  name: string;
  platform?: string | null;
  alias?: string;
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
    out.push({ deviceId, name, platform, alias: typeof (item as GuestPeer).alias === 'string' ? (item as GuestPeer).alias : undefined });
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
  const existing = loadGuestPeers().find(p => p.deviceId === deviceId);
  const next = loadGuestPeers().filter((p) => p.deviceId !== deviceId);
  next.push({
    deviceId,
    name: peer.name.trim() || shortDeviceLabel(deviceId),
    platform: peer.platform ?? existing?.platform ?? null,
    alias: peer.alias ?? existing?.alias,
  });
  persist(next);
  return next;
}

export function removeGuestPeer(deviceId: string): void { persist(loadGuestPeers().filter(p => p.deviceId !== deviceId)); }

export function guestPeerToDeviceDto(peer: GuestPeer): DeviceDto {
  return { deviceId: peer.deviceId, name: peer.alias || peer.name, platform: peer.platform ?? null, presenceStatus: null };
}

export function mergeDeviceRosters(account: DeviceDto[], guests: GuestPeer[]): DeviceDto[] {
  const byId = new Map<string, DeviceDto>();
  for (const g of guests) {
    byId.set(g.deviceId, guestPeerToDeviceDto(g));
  }
  for (const d of account) {
    const local = guests.find(g => g.deviceId === d.deviceId);
    byId.set(d.deviceId, { ...d, name: local?.alias || (d.name !== d.deviceId ? d.name : local?.name) || d.name, platform: d.platform ?? local?.platform });
  }
  return [...byId.values()];
}

export function setGuestPeerAlias(peer: GuestPeer, alias: string): void {
  const stored = loadGuestPeers().find(d => d.deviceId === peer.deviceId);
  upsertGuestPeer({ ...peer, name: stored?.name ?? peer.name, alias: alias.trim() });
}

/** Cache advertised names, never rendered nicknames or an online assumption. */
export function rememberPeerProfiles(devices: DeviceDto[]): void {
  const profiles = new Map(devices.map(d => [d.deviceId, d]));
  persist(loadGuestPeers().map(peer => {
    const profile = profiles.get(peer.deviceId);
    return profile ? { ...peer, name: profile.name !== peer.deviceId ? profile.name : peer.name, platform: profile.platform ?? peer.platform } : peer;
  }));
}
