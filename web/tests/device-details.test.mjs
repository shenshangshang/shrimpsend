import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import ts from 'typescript';
import { mergePeerSnapshot } from '../src/lib/peerRoster.ts';

const moduleUrl = source => `data:text/javascript;base64,${Buffer.from(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText).toString('base64')}`;
const pairUrl = moduleUrl(await fs.readFile(new URL('../src/lib/devicePair.ts', import.meta.url), 'utf8'));
const peers = await import(moduleUrl((await fs.readFile(new URL('../src/lib/guestPeers.ts', import.meta.url), 'utf8')).replace("'./devicePair'", JSON.stringify(pairUrl))));

test('duplicated tabs share the transfer identity but have independent connection sessions', async () => {
  globalThis.window = {};
  const first = await import('../src/lib/deviceId.ts?tab=one');
  const second = await import('../src/lib/deviceId.ts?tab=two');
  assert.equal(first.getOrCreatePresenceSessionId(), first.getOrCreatePresenceSessionId());
  assert.notEqual(first.getOrCreatePresenceSessionId(), second.getOrCreatePresenceSessionId());
  delete globalThis.window;
});

test('stored peers start unknown and device rename wins unless explicitly nicknamed', () => {
  const old = { deviceId: 'a', name: 'Old Mac', platform: 'macos' };
  assert.equal(peers.guestPeerToDeviceDto(old).presenceStatus, null);
  const fresh = { deviceId: 'a', name: '新 Mac', presenceStatus: 'online', presenceUpdatedAt: 2 };
  assert.equal(peers.mergeDeviceRosters([fresh], [old])[0].name, '新 Mac');
  assert.equal(peers.mergeDeviceRosters([fresh], [{ ...old, alias: '工作电脑' }])[0].name, '工作电脑');
  assert.equal(peers.mergeDeviceRosters([fresh], [{ ...old, alias: '' }])[0].name, '新 Mac');
});

test('pair hello preserves explicit nickname, and clearing it restores advertised name', () => {
  const values = new Map(); globalThis.window = {};
  globalThis.localStorage = { getItem: key => values.get(key), setItem: (key, value) => values.set(key, value) };
  peers.setGuestPeerAlias({ deviceId: 'a', name: 'Mac' }, 'Work');
  peers.upsertGuestPeer({ deviceId: 'a', name: 'New Mac', platform: 'macos' });
  assert.equal(peers.loadGuestPeers()[0].alias, 'Work');
  peers.rememberPeerProfiles([{ deviceId: 'a', name: 'Newest Mac' }]);
  assert.equal(peers.loadGuestPeers()[0].alias, 'Work');
  peers.setGuestPeerAlias({ ...peers.loadGuestPeers()[0], name: 'Work' }, '');
  assert.equal(peers.guestPeerToDeviceDto(peers.loadGuestPeers()[0]).name, 'Newest Mac');
  delete globalThis.window; delete globalThis.localStorage;
});

test('older snapshot cannot revive an offline peer or undo a live rename', () => {
  const current = [{ deviceId: 'a', name: 'New', presenceStatus: 'offline', presenceUpdatedAt: 10 }];
  const stale = [{ deviceId: 'a', name: 'Old', presenceStatus: 'online', presenceUpdatedAt: 8 }];
  assert.deepEqual(mergePeerSnapshot(current, stale), current);
  assert.deepEqual(mergePeerSnapshot(current, [{ ...stale[0], presenceUpdatedAt: 11 }]), [{ ...stale[0], presenceUpdatedAt: 11 }]);
  assert.deepEqual(mergePeerSnapshot(current, []), []);
});
