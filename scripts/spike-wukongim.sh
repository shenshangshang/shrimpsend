#!/usr/bin/env bash
# Phase 0 spike: start WuKongIM and prove token + fan-out over JSON-RPC.
# Usage: ./scripts/spike-wukongim.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API="${WUKONGIM_API_URL:-http://127.0.0.1:5001}"
WS="${WUKONGIM_WS_URL:-ws://127.0.0.1:5200}"
WK_UID="${SPIKE_UID:-spike-user-1}"
SYS_UID="${WUKONGIM_SYSTEM_UID:-ultrasend}"
MANAGER_TOKEN="${WUKONGIM_MANAGER_TOKEN:-dev-wukongim-manager-token}"

cd "$ROOT"

if ! command -v docker >/dev/null 2>&1; then
  echo "[错误] 需要 docker 才能拉起悟空 IM" >&2
  exit 1
fi

echo "==> docker compose up wukongim"
if ! docker compose up -d wukongim; then
  echo "==> 阿里云镜像失败，改用 Docker Hub wukongim/wukongim:v2"
  WUKONGIM_IMAGE=wukongim/wukongim:v2 docker compose up -d wukongim
fi

echo "==> 等待 /health"
ok=0
for i in $(seq 1 30); do
  if curl -sf -H "token: $MANAGER_TOKEN" "$API/health" >/dev/null 2>&1; then
    ok=1
    break
  fi
  sleep 2
done
if [ "$ok" -ne 1 ]; then
  echo "[错误] 悟空 IM 未就绪: $API/health" >&2
  docker compose logs --tail=80 wukongim >&2 || true
  exit 1
fi
echo "  health OK"

echo "==> 注册系统号 $SYS_UID"
curl -sf -X POST "$API/user/systemuids_add" \
  -H "Content-Type: application/json" \
  -H "token: $MANAGER_TOKEN" \
  -d "{\"uids\":[\"$SYS_UID\"]}" >/dev/null || true

token_a="spike-shared-$RANDOM"
echo "==> 签发 App 次设备共享 token（悟空同一 uid+flag 共用一个 CONNECT token）"
curl -sf -X POST "$API/user/token" \
  -H "Content-Type: application/json" \
  -H "token: $MANAGER_TOKEN" \
  -d "{\"uid\":\"$WK_UID\",\"token\":\"$token_a\",\"device_flag\":0,\"device_level\":0}" >/dev/null
echo "  token ok"

payload_json='{"type":200,"v":1,"envelope":{"type":"text","payload":{"text":"spike-fanout"},"fromDeviceId":"phone-a"}}'
payload_b64="$(printf '%s' "$payload_json" | python3 -c 'import sys,base64; print(base64.b64encode(sys.stdin.buffer.read()).decode())')"

if ! command -v node >/dev/null 2>&1; then
  echo "==> 无 node，只验证 HTTP send"
  curl -sf -X POST "$API/message/send" \
    -H "Content-Type: application/json" \
    -H "token: $MANAGER_TOKEN" \
    -d "{\"header\":{\"no_persist\":0,\"red_dot\":0,\"sync_once\":0},\"from_uid\":\"$SYS_UID\",\"channel_id\":\"$WK_UID\",\"channel_type\":1,\"expire\":120,\"client_msg_no\":\"spike-$RANDOM\",\"payload\":\"$payload_b64\"}"
  echo ""
  echo "HTTP send OK。请安装 Node 后再跑双连接 JSON-RPC 验收。"
  exit 0
fi

echo "==> 双连接 JSON-RPC（同 flag=0 / level=0）"
export SPIKE_API="$API" SPIKE_WS="$WS" SPIKE_UID="$WK_UID" SPIKE_SYS="$SYS_UID"
export SPIKE_TOKEN_A="$token_a" SPIKE_TOKEN_B="$token_a" SPIKE_PAYLOAD_B64="$payload_b64"
export SPIKE_MANAGER_TOKEN="$MANAGER_TOKEN"
node <<'NODE'
const WS = globalThis.WebSocket;
if (!WS) {
  console.error('Node WebSocket 不可用，请使用 Node 21+');
  process.exit(1);
}

const uid = process.env.SPIKE_UID;
const wsUrl = process.env.SPIKE_WS;
const api = process.env.SPIKE_API;
const sys = process.env.SPIKE_SYS;
const payloadB64 = process.env.SPIKE_PAYLOAD_B64;

function openDevice(deviceId, token) {
  return new Promise((resolve, reject) => {
    const ws = new WS(wsUrl);
    const got = [];
    const timer = setTimeout(() => reject(new Error(deviceId + ' connect timeout')), 8000);
    ws.addEventListener('open', () => {
      ws.send(JSON.stringify({
        method: 'connect',
        id: 'c1',
        params: {
          uid,
          token,
          deviceId,
          deviceFlag: 0,
          clientTimestamp: Date.now(),
        },
      }));
    });
    ws.addEventListener('message', (ev) => {
      let msg;
      try { msg = JSON.parse(ev.data); } catch { return; }
      if (msg.id === 'c1') {
        if (msg.error) {
          clearTimeout(timer);
          reject(new Error(deviceId + ' auth: ' + JSON.stringify(msg.error)));
          return;
        }
        clearTimeout(timer);
        resolve({ ws, got, deviceId });
        return;
      }
      if ((msg.method === 'recv' || msg.method === 'message') && msg.params) {
        got.push(msg.params);
      }
    });
    ws.addEventListener('error', () => {
      clearTimeout(timer);
      reject(new Error(deviceId + ' ws error'));
    });
  });
}

(async () => {
  const a = await openDevice('phone-a', process.env.SPIKE_TOKEN_A);
  const b = await openDevice('phone-b', process.env.SPIKE_TOKEN_B);
  console.log('  both connected');
  const res = await fetch(api + '/message/send', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', token: process.env.SPIKE_MANAGER_TOKEN || '' },
    body: JSON.stringify({
      header: { no_persist: 0, red_dot: 0, sync_once: 0 },
      from_uid: sys,
      channel_id: uid,
      channel_type: 1,
      expire: 120,
      client_msg_no: 'spike-' + Date.now(),
      payload: payloadB64,
    }),
  });
  if (!res.ok) {
    throw new Error('send failed ' + res.status + ' ' + await res.text());
  }
  const deadline = Date.now() + 8000;
  while (Date.now() < deadline) {
    if (a.got.length && b.got.length) break;
    await new Promise((r) => setTimeout(r, 200));
  }
  a.ws.close();
  b.ws.close();
  if (!a.got.length || !b.got.length) {
    throw new Error('fanout failed a=' + a.got.length + ' b=' + b.got.length);
  }
  console.log('  fanout OK a=' + a.got.length + ' b=' + b.got.length);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
NODE

echo ""
echo "Spike 通过：健康检查、双次设备在线、系统号扇出。"
echo "Web/桌面/鸿蒙连通在客户端接入后用真机验收；ICE DataChannel 走现有 sendMessage 路径。"
