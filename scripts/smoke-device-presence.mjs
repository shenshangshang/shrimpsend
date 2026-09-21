// Disposable local devices only; no account or membership required.
import { randomUUID } from 'node:crypto';
const base = process.env.PRESENCE_QA_API || 'http://localhost:9000';
const makeDevice = async name => {
  const id = `presence-qa-${randomUUID()}`;
  const response = await fetch(`${base}/api/realtime/device-session`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ deviceId: id, deviceSecret: randomUUID(), platform: 'web' }) });
  if (!response.ok) throw new Error(`session ${response.status}`);
  return { id, name, ...(await response.json()) };
};
const request = async (device, path, body, method = 'POST') => {
  const response = await fetch(`${base}${path}`, { method, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${device.deviceAccessToken}` }, body: body === undefined ? undefined : JSON.stringify(body) });
  if (!response.ok) throw new Error(`${path}: ${response.status}`);
  return response.status === 204 ? null : response.json();
};
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const assert = (condition, label) => { if (!condition) throw new Error(label); };
const observer = await makeDevice('Observer'); const subject = await makeDevice('Test Mac');
const events = [];
const ws = new WebSocket(observer.websocketUrl);
await new Promise((resolve, reject) => {
  const timeout = setTimeout(() => reject(new Error('ws connect timeout')), 10000);
  ws.onopen = () => ws.send(JSON.stringify({ method: 'connect', id: 'connect', params: { uid: observer.uid, token: observer.token, deviceFlag: observer.deviceFlag, deviceId: observer.id, clientTimestamp: Date.now() } }));
  ws.onmessage = event => {
    const message = JSON.parse(event.data);
    if (message.id === 'connect' && message.result) { clearTimeout(timeout); resolve(); }
    if (message.method === 'recv' || message.method === 'message') {
      const p = message.params; ws.send(JSON.stringify({ method: 'recvack', params: { messageId: p.messageId, messageSeq: p.messageSeq } }));
      let data = p.payload;
      if (typeof data === 'string') { try { data = JSON.parse(data); } catch { data = JSON.parse(Buffer.from(data, 'base64').toString()); } }
      if (data?.type === 200 && data.envelope) data = data.envelope;
      events.push({ data, at: Date.now() });
    }
  };
});
const ping = setInterval(() => { if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ method: 'ping', id: `ping-${Date.now()}` })); }, 10000);
let seq = 0;
const heartbeat = (status, tab = 'tab-a') => request(subject, '/api/devices/self/presence', { sessionId: tab, sequence: ++seq, status, name: subject.name, platform: 'web' });
const eventAfter = async (started, predicate, timeout = 5000) => {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const event = events.find(e => e.at >= started && e.data?.type === 'peer_device_patch' && predicate(e.data.device));
    if (event) return event.at - started;
    await delay(50);
  }
  throw new Error('peer event timeout');
};
try {
  await request(observer, '/api/devices/pair', { peerDeviceId: subject.id });
  let started = Date.now(); await heartbeat('online');
  console.log(JSON.stringify({ check: 'online notification', ms: await eventAfter(started, d => d.presenceStatus === 'online') }));
  started = Date.now(); await request(subject, '/api/devices/self/profile', { name: ' Renamed Mac ' }, 'PATCH');
  console.log(JSON.stringify({ check: 'rename notification', ms: await eventAfter(started, d => d.name === 'Renamed Mac') }));
  await heartbeat('online', 'tab-b'); await heartbeat('offline');
  let peers = await request(observer, '/api/devices/paired', undefined, 'GET');
  assert(peers[0].presenceStatus === 'online', 'other tab must keep device online');
  assert(peers[0].name === 'Renamed Mac', 'heartbeat must not overwrite rename');
  started = Date.now(); await heartbeat('offline', 'tab-b');
  console.log(JSON.stringify({ check: 'last tab offline notification', ms: await eventAfter(started, d => d.presenceStatus === 'offline') }));
  await request(subject, '/api/devices/self/presence', { sessionId: 'tab-a', sequence: 1, status: 'online', name: 'Old', platform: 'web' });
  peers = await request(observer, '/api/devices/paired', undefined, 'GET');
  assert(peers[0].presenceStatus === 'offline', 'late request must not revive closed tab');
  await heartbeat('online'); await delay(400); started = Date.now();
  console.log('Waiting for abrupt-stop lease expiry (no further heartbeat).');
  const elapsed = await eventAfter(started, d => d.presenceStatus === 'offline', 52000);
  assert(elapsed >= 43000 && elapsed <= 51000, 'lease expiry window');
  console.log(JSON.stringify({ check: 'abrupt stop expiry', ms: elapsed }));
  console.log('PASS: guest presence, rename, realtime fanout, multiple tabs, request ordering, lease expiry');
} finally {
  await request(observer, `/api/devices/paired/${encodeURIComponent(subject.id)}`, undefined, 'DELETE');
  clearInterval(ping); ws.close();
}
