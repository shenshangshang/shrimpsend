'use client';

import { useCallback, useEffect, useMemo, useRef, useState, type MutableRefObject } from 'react';
import type { DeviceDto } from '@/lib/api';
import { logger } from '@/lib/logger';
import {
  partitionForProbe,
  runWithConcurrency,
  shouldSkipAutoProbe,
} from '@/lib/probePriority';

const TAG = 'useSendTargetProbes';

/** UI display status (checking is probe progress, not device state). */
export type ReachStatus = 'checking' | 'online' | 'offline';

export type DeviceReachDetail = {
  directHttp: boolean;
  /** Peer HTTP self-check via signaling. */
  peerHttpHealthy: boolean;
  /** Reverse pull direction (peer can reach this device). */
  pullReachable: boolean;
  /** `null` = not probed (e.g. WebRTC skipped when LAN direct works). */
  webrtc: boolean | null;
  /** @deprecated use peerHttpHealthy */
  lanSignaling: boolean;
};

export type DeviceReachEntry = {
  methods: DeviceReachDetail;
  probing: boolean;
  checkedAt?: number;
};

const offlineMethods: DeviceReachDetail = {
  directHttp: false,
  peerHttpHealthy: false,
  pullReachable: false,
  webrtc: null,
  lanSignaling: false,
};
const offlineEntry: DeviceReachEntry = { methods: offlineMethods, probing: false };

export function isReachOnline(entry?: DeviceReachEntry): boolean {
  const m = entry?.methods;
  return !!(
    m?.directHttp ||
    m?.pullReachable ||
    m?.peerHttpHealthy ||
    m?.lanSignaling ||
    m?.webrtc === true
  );
}

export function isPullOnlyReach(entry?: DeviceReachEntry): boolean {
  const m = entry?.methods;
  return !!(m?.pullReachable && !m?.directHttp);
}

export function getReachDisplayStatus(entry?: DeviceReachEntry): ReachStatus {
  if (isReachOnline(entry)) return 'online';
  if (entry?.probing) return 'checking';
  return 'offline';
}

export function reachSortPriority(entry?: DeviceReachEntry): number {
  return isReachOnline(entry) ? 0 : 1;
}

function initialReachEntry(): DeviceReachEntry {
  return offlineEntry;
}

function toProbingEntry(prev?: DeviceReachEntry, quiet = false): DeviceReachEntry {
  return {
    methods: prev?.methods ?? offlineMethods,
    probing: quiet && !!prev?.checkedAt ? false : true,
    checkedAt: prev?.checkedAt,
  };
}

function toResolvedEntry(methods: DeviceReachDetail): DeviceReachEntry {
  return { methods, probing: false, checkedAt: Date.now() };
}

function buildFromDevicePresence(devices: DeviceDto[]): Record<string, DeviceReachEntry> {
  const m: Record<string, DeviceReachEntry> = {};
  for (const device of devices) m[device.deviceId] = initialReachEntry();
  return m;
}

function mergeReachOnListChange(
  prev: Record<string, DeviceReachEntry>,
  devices: DeviceDto[],
  connected: boolean,
): Record<string, DeviceReachEntry> {

  const next: Record<string, DeviceReachEntry> = {};
  for (const device of devices) {
    const old = prev[device.deviceId] ?? offlineEntry;
    next[device.deviceId] = !connected || device.presenceStatus === 'offline'
      ? { methods: { ...offlineMethods, directHttp: old.methods.directHttp }, probing: old.probing, checkedAt: old.checkedAt }
      : old;
  }
  return next;
}

/** Probe HTTP direct + LAN signaling. WebRTC transfer is not pre-probed. */
async function probeDeviceAllMethods(
  device: DeviceDto,
  nearbyIds: Set<string>,
  onDirectHttpProbe: (url: string) => Promise<boolean>,
  onLanHttpProbe: (deviceId: string) => Promise<{ success: boolean; lanHttpUrl?: string; senderReachable?: boolean }>,
  { forceFull = false }: { forceFull?: boolean } = {},
): Promise<{ methods: DeviceReachDetail; freshLanUrl?: string }> {
  if (!forceFull && shouldSkipAutoProbe(device, nearbyIds)) {
    return { methods: offlineMethods };
  }

  const lanUrl = device.lanHttpUrl?.trim();
  if (lanUrl) {
    try {
      const ok = await onDirectHttpProbe(lanUrl);
      if (ok) {
        return {
          methods: {
            directHttp: true,
            peerHttpHealthy: false,
            pullReachable: false,
            webrtc: null,
            lanSignaling: false,
          },
          freshLanUrl: lanUrl,
        };
      }
    } catch {
      // fall through to signaling
    }
  }

  const results = await Promise.allSettled([
    (async () => {
      const result = await onLanHttpProbe(device.deviceId);
      return {
        peerOk: result.success,
        pullOk: result.senderReachable === true,
        url: result.lanHttpUrl,
      };
    })(),
  ]);

  const lanResult = results[0].status === 'fulfilled'
    ? results[0].value
    : { peerOk: false, pullOk: false, url: undefined as string | undefined };

  const freshLanUrl = lanResult.url;
  const peerHttpHealthy = lanResult.peerOk;
  const pullReachable = lanResult.pullOk;

  return {
    methods: {
      directHttp: false,
      peerHttpHealthy,
      pullReachable,
      webrtc: null,
      lanSignaling: peerHttpHealthy,
    },
    freshLanUrl,
  };
}

export function useSendTargetProbes(
  otherDevices: DeviceDto[],
  lanDevices: DeviceDto[],
  connected: boolean,
  probeToken: number,
  probeForceAll: boolean,
  onLanHttpProbe: (
    targetDeviceId: string,
  ) => Promise<{ success: boolean; lanHttpUrl?: string; senderReachable?: boolean }>,
  onDirectHttpProbe: (url: string) => Promise<boolean>,
): {
  deviceReach: Record<string, DeviceReachEntry>;
  freshLanUrlsRef: MutableRefObject<Record<string, string>>;
  probing: boolean;
  probeSingleDevice: (deviceId: string) => void;
  applyDeviceReach: (deviceId: string, entry: DeviceReachEntry, freshLanUrl?: string) => void;
} {
  const deviceFingerprint = useMemo(
    () =>
      otherDevices
        .map(
          (d) =>
            `${d.deviceId}:${d.presenceStatus ?? ''}:${d.presenceUpdatedAt ?? ''}:${d.lanHttpUrl ?? ''}`,
        )
        .join(','),
    [otherDevices],
  );

  const myDeviceIds = useMemo(
    () => new Set(otherDevices.map((d) => d.deviceId)),
    [otherDevices],
  );
  const nearbyIds = useMemo(() => {
    const ids = new Set(lanDevices.map((d) => d.deviceId));
    for (const d of otherDevices) {
      if (d.lanHttpUrl?.trim()) ids.add(d.deviceId);
    }
    return ids;
  }, [otherDevices, lanDevices]);

  const [deviceReach, setDeviceReach] = useState<Record<string, DeviceReachEntry>>(() =>
    buildFromDevicePresence(otherDevices),
  );
  const [probing, setProbing] = useState(false);

  const freshLanUrlsRef = useRef<Record<string, string>>({});
  const probeVersions = useRef<Record<string, number>>({});
  const inFlight = useRef(new Set<string>());
  const connectedRef = useRef(connected);
  connectedRef.current = connected;
  const deviceSnapshotRef = useRef(otherDevices);
  deviceSnapshotRef.current = otherDevices;
  const nearbyIdsRef = useRef(nearbyIds);
  nearbyIdsRef.current = nearbyIds;
  const myDeviceIdsRef = useRef(myDeviceIds);
  myDeviceIdsRef.current = myDeviceIds;

  useEffect(() => {
    for (const id of Object.keys(probeVersions.current)) probeVersions.current[id]++;
    const ids = otherDevices.map((d) => d.deviceId);
    setDeviceReach((prev) => mergeReachOnListChange(prev, otherDevices, connected));

    const allowed = new Set(ids);
    const urls = { ...freshLanUrlsRef.current };
    for (const k of Object.keys(urls)) {
      if (!allowed.has(k)) delete urls[k];
    }
    freshLanUrlsRef.current = urls;
  }, [deviceFingerprint, connected]);

  useEffect(() => {
    const cancelledRef = { current: false };
    if (probeToken === 0) {
      return () => { cancelledRef.current = true; };
    }

    const snap = deviceSnapshotRef.current;
    const partition = partitionForProbe(
      snap,
      nearbyIdsRef.current,
      myDeviceIdsRef.current,
    );
    const toProbe = probeForceAll
      ? snap
      : [...partition.lanDiscovered, ...partition.presenceOnline];

    logger.info(
      TAG,
      'probe run token=',
      probeToken,
      'forceAll=',
      probeForceAll,
      'auto=',
      toProbe.length,
      'lazy=',
      partition.lazy.length,
    );

    setDeviceReach((prev) => {
      const next = { ...prev };
      for (const d of toProbe) next[d.deviceId] = toProbingEntry(prev[d.deviceId], !probeForceAll);
      if (!probeForceAll) {
        for (const d of partition.lazy) next[d.deviceId] = offlineEntry;
      }
      return next;
    });

    if (toProbe.length === 0) {
      setProbing(false);
      return () => { cancelledRef.current = true; };
    }

    setProbing(true);

    const applyResult = (
      deviceId: string,
      methods: DeviceReachDetail,
      freshLanUrl?: string,
    ) => {
      if (cancelledRef.current) return;
      if (freshLanUrl) {
        freshLanUrlsRef.current = { ...freshLanUrlsRef.current, [deviceId]: freshLanUrl };
      }
      setDeviceReach((prev) => ({
        ...prev,
        [deviceId]: toResolvedEntry(methods),
      }));
    };

    const probeOne = async (d: DeviceDto, forceFull: boolean) => {
      if (cancelledRef.current || inFlight.current.has(d.deviceId)) return;
      const version = (probeVersions.current[d.deviceId] ?? 0) + 1;
      probeVersions.current[d.deviceId] = version;
      inFlight.current.add(d.deviceId);
      try {
        const { methods, freshLanUrl } = await probeDeviceAllMethods(
          d,
          nearbyIdsRef.current,
          onDirectHttpProbe,
          connectedRef.current ? onLanHttpProbe : async () => ({ success: false }),
          { forceFull },
        );
        if (probeVersions.current[d.deviceId] === version) applyResult(d.deviceId, methods, freshLanUrl);
      } catch {
        if (probeVersions.current[d.deviceId] === version) applyResult(d.deviceId, offlineMethods);
      } finally { inFlight.current.delete(d.deviceId); }
    };

    void (async () => {
      try {
        if (probeForceAll) {
          await runWithConcurrency(toProbe, 3, (d) => probeOne(d, true));
        } else {
          await runWithConcurrency(partition.lanDiscovered, 6, (d) => probeOne(d, false));
          if (cancelledRef.current) return;
          await runWithConcurrency(partition.presenceOnline, 3, (d) => probeOne(d, false));
        }
      } finally {
        if (!cancelledRef.current) setProbing(false);
      }
    })();

    return () => { cancelledRef.current = true; };
  }, [probeToken, probeForceAll, connected, deviceFingerprint, onLanHttpProbe, onDirectHttpProbe]);

  const probeSingleDevice = useCallback((deviceId: string) => {
    if (inFlight.current.has(deviceId)) return;
    const device = deviceSnapshotRef.current.find((d) => d.deviceId === deviceId);
    if (!device) return;
    const version = (probeVersions.current[deviceId] ?? 0) + 1;
    probeVersions.current[deviceId] = version;
    inFlight.current.add(deviceId);

    setDeviceReach((prev) => ({
      ...prev,
      [deviceId]: toProbingEntry(prev[deviceId]),
    }));
    void (async () => {
      const { methods, freshLanUrl } = await probeDeviceAllMethods(
        device,
        nearbyIdsRef.current,
        onDirectHttpProbe,
        connectedRef.current ? onLanHttpProbe : async () => ({ success: false }),
        { forceFull: true },
      );
      inFlight.current.delete(deviceId);
      if (probeVersions.current[deviceId] !== version || !deviceSnapshotRef.current.some(d => d.deviceId === deviceId)) return;
      if (freshLanUrl) {
        freshLanUrlsRef.current = { ...freshLanUrlsRef.current, [deviceId]: freshLanUrl };
      }
      setDeviceReach((prev) => ({
        ...prev,
        [deviceId]: toResolvedEntry(methods),
      }));
    })().catch(() => { inFlight.current.delete(deviceId); setDeviceReach(prev => ({ ...prev, [deviceId]: offlineEntry })); });
  }, [connected, onDirectHttpProbe, onLanHttpProbe]);

  const applyDeviceReach = useCallback(
    (deviceId: string, entry: DeviceReachEntry, freshLanUrl?: string) => {
      probeVersions.current[deviceId] = (probeVersions.current[deviceId] ?? 0) + 1;
      if (freshLanUrl) {
        freshLanUrlsRef.current = { ...freshLanUrlsRef.current, [deviceId]: freshLanUrl };
      }
      setDeviceReach((prev) => ({
        ...prev,
        [deviceId]: entry,
      }));
    },
    [],
  );

  return { deviceReach, freshLanUrlsRef, probing, probeSingleDevice, applyDeviceReach };
}

export function sortDevicesByReach(
  devices: DeviceDto[],
  statusMap: Record<string, DeviceReachEntry>,
): DeviceDto[] {
  return [...devices].sort(
    (a, b) => reachSortPriority(statusMap[a.deviceId]) - reachSortPriority(statusMap[b.deviceId]),
  );
}
