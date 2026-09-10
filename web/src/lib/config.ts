/**
 * 统一的服务地址推导。
 *
 * 规则：
 *   SSR（服务端渲染）→ 后端在同一台机器，统一用 localhost
 *   浏览器-本地网络 → 始终连接同 hostname 的本机服务端口
 *   非局域网（公网 Web）→ 始终 api.{当前 host}（WSS/HTTP-stream 也走 API 同域，由 nginx 反代 Centrifugo）
 */

const BACKEND_PORT = 9000;
const CENTRIFUGO_PORT = 8000;

function isLocalNetwork(): boolean {
  if (typeof window === 'undefined') return true;
  const h = window.location.hostname;
  return h === 'localhost' || h === '127.0.0.1' || h.startsWith('192.168.') || h.startsWith('10.');
}

export function getApiUrl(): string {
  if (typeof window === 'undefined') {
    return `http://localhost:${BACKEND_PORT}`;
  }
  if (isLocalNetwork()) {
    return `${window.location.protocol}//${window.location.hostname}:${BACKEND_PORT}`;
  }
  // 公网 Web：服务地址由当前部署域名决定，不再用本地存储的国家码覆盖。
  return `${window.location.protocol}//api.${window.location.host}`;
}

export type CentrifugeEndpoint = {
  transport: 'websocket' | 'http_stream';
  endpoint: string;
};

export function wsUrlFromHttpApi(apiUrl: string): string {
  try {
    const u = new URL(apiUrl);
    u.protocol = u.protocol === 'https:' ? 'wss:' : 'ws:';
    u.pathname = '/connection/websocket';
    u.search = '';
    u.hash = '';
    return u.toString();
  } catch {
    return `ws://localhost:${CENTRIFUGO_PORT}/connection/websocket`;
  }
}

export function httpStreamUrlFromHttpApi(apiUrl: string): string {
  try {
    const u = new URL(apiUrl);
    u.pathname = '/connection/http_stream';
    u.search = '';
    u.hash = '';
    return u.toString();
  } catch {
    return `http://localhost:${CENTRIFUGO_PORT}/connection/http_stream`;
  }
}

export function getCentrifugoWsUrl(): string {
  if (typeof window === 'undefined' || isLocalNetwork()) {
    const host = typeof window === 'undefined' ? 'localhost' : window.location.hostname;
    return `ws://${host}:${CENTRIFUGO_PORT}/connection/websocket`;
  }
  return wsUrlFromHttpApi(getApiUrl());
}

/** WebSocket first, HTTP-stream fallback (Centrifugo). Local dev is WS-only on :8000. */
export function getCentrifugoEndpoints(): Array<string | CentrifugeEndpoint> {
  if (typeof window === 'undefined' || isLocalNetwork()) {
    return [getCentrifugoWsUrl()];
  }
  const api = getApiUrl();
  return [
    { transport: 'websocket', endpoint: wsUrlFromHttpApi(api) },
    { transport: 'http_stream', endpoint: httpStreamUrlFromHttpApi(api) },
  ];
}

/** 当前环境下解析出的 HTTP API 根 URL */
export function resolveBackendApiUrl(): string {
  return getApiUrl();
}
