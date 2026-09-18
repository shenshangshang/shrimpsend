export type WukongimEnvelope = Record<string, unknown> & { type?: string };

export function unwrapWukongimPayload(payload: unknown): WukongimEnvelope | null {
  let decoded: unknown = payload;
  if (typeof payload === 'string') {
    try {
      if (payload.startsWith('{') || payload.startsWith('[')) {
        decoded = JSON.parse(payload);
      } else {
        const bytes = Uint8Array.from(atob(payload), (c) => c.charCodeAt(0));
        decoded = JSON.parse(new TextDecoder().decode(bytes));
      }
    } catch {
      return null;
    }
  }
  if (!decoded || typeof decoded !== 'object') return null;
  const map = decoded as Record<string, unknown>;
  if (map.type === 200 && map.envelope && typeof map.envelope === 'object') {
    return map.envelope as WukongimEnvelope;
  }
  if (typeof map.type === 'string') {
    return map as WukongimEnvelope;
  }
  return null;
}

export function rewriteLoopbackRealtimeWs(websocketUrl: string, apiUrl: string): string {
  try {
    const ws = new URL(websocketUrl);
    if (ws.hostname !== '127.0.0.1' && ws.hostname !== 'localhost') return websocketUrl;
    const api = new URL(apiUrl);
    if (!api.hostname || api.hostname === '127.0.0.1' || api.hostname === 'localhost') {
      return websocketUrl;
    }
    ws.hostname = api.hostname;
    return ws.toString().replace(/\/$/, '');
  } catch {
    return websocketUrl;
  }
}

export function getWukongimWsUrl(): string {
  if (typeof window === 'undefined') {
    return 'ws://localhost:5200';
  }
  const host = window.location.hostname;
  const local = host === 'localhost' || host === '127.0.0.1' || host.startsWith('192.168.') || host.startsWith('10.');
  if (local) {
    return `ws://${host}:5200`;
  }
  const proto = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  return `${proto}//api.${window.location.host}/wkws`;
}
