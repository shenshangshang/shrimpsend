export const DEVICE_PAIR_URI_PREFIX = 'ultrasend://pair/';

export function devicePairUri(deviceId: string): string {
  return `${DEVICE_PAIR_URI_PREFIX}${deviceId}`;
}

export function parseDevicePairUri(text: string): string | null {
  const trimmed = text.trim();
  if (!trimmed.toLowerCase().startsWith(DEVICE_PAIR_URI_PREFIX)) return null;
  const rest = trimmed.slice(DEVICE_PAIR_URI_PREFIX.length).trim();
  const id = rest.split(/[?#]/)[0]?.trim() ?? '';
  return id.length > 0 ? id : null;
}

/** Accepts `ultrasend://pair/<id>` or a raw deviceId. */
export function normalizePeerDeviceId(raw: string): string | null {
  const trimmed = raw.trim();
  if (!trimmed) return null;
  return parseDevicePairUri(trimmed) ?? trimmed;
}

export function shortDeviceLabel(deviceId: string): string {
  if (deviceId.length <= 12) return deviceId;
  return `${deviceId.slice(0, 8)}…`;
}
