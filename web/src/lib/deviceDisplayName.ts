/** Retain user names; replace legacy ID placeholders with a recognizable device label. */
export function deviceDisplayName(device: { deviceId: string; name: string; platform?: string | null }): string {
  const { deviceId, name, platform } = device;
  if (name && name !== deviceId && !/^[a-z]+_[a-f\d-]+(?:…|\.\.\.)?$/i.test(name)) return name;
  const kind = `${platform ?? ''} ${deviceId}`.toLowerCase();
  const label = /macos/.test(kind) ? 'Mac' : /windows/.test(kind) ? 'Windows'
    : /iphone|ios/.test(kind) ? 'iPhone' : /android/.test(kind) ? 'Android'
    : /linux/.test(kind) ? 'Linux' : /chrome/.test(kind) ? 'Chrome'
    : /safari/.test(kind) ? 'Safari' : /edge/.test(kind) ? 'Edge' : 'Web';
  const suffix = deviceId.split('_')[1]?.replaceAll('-', '').slice(-4).toUpperCase();
  return suffix ? `${label} · ${suffix}` : label;
}
