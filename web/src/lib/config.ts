/**
 * 统一的服务地址推导。
 *
 * 规则：
 *   SSR（服务端渲染）→ 后端在同一台机器，统一用 localhost
 *   浏览器-本地网络 → 始终连接同 hostname 的本机服务端口
 *   非局域网（公网 Web）→ 始终 api.{当前 host}（WSS 走 API 同域 /wkws，由 nginx 反代悟空 IM）
 */

const BACKEND_PORT = 9000;
const WUKONGIM_WS_PORT = 5200;

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
  return `${window.location.protocol}//api.${window.location.host}`;
}

export function getWukongimWsUrl(): string {
  if (typeof window === 'undefined' || isLocalNetwork()) {
    const host = typeof window === 'undefined' ? 'localhost' : window.location.hostname;
    return `ws://${host}:${WUKONGIM_WS_PORT}`;
  }
  try {
    const u = new URL(getApiUrl());
    u.protocol = u.protocol === 'https:' ? 'wss:' : 'ws:';
    u.pathname = '/wkws';
    u.search = '';
    u.hash = '';
    return u.toString();
  } catch {
    return `ws://localhost:${WUKONGIM_WS_PORT}`;
  }
}

/** 当前环境下解析出的 HTTP API 根 URL */
export const apiUrl = getApiUrl();
