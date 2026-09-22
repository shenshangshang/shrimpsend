import type { DeviceDto } from './api/devices';

/** Prevent late snapshots or replayed notifications from undoing fresh state. */
export function mergePeerSnapshot(current: DeviceDto[], incoming: DeviceDto[]): DeviceDto[] {
  return incoming.map(device => {
    const previous = current.find(d => d.deviceId === device.deviceId);
    return previous && (previous.presenceUpdatedAt ?? 0) > (device.presenceUpdatedAt ?? 0) ? previous : device;
  });
}
