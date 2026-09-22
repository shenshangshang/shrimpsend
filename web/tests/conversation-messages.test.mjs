import test from 'node:test';
import assert from 'node:assert/strict';
import { belongsToConversation, mergeMessageHistory } from '../src/lib/conversationMessages.ts';

test('guest messages belong to their peer regardless of the sender account prefix', () => {
  const received = { fromDeviceId: 'peer', toDeviceId: 'me', threadKey: 'o:peer|d1:me|d2:peer', ts: 1 };
  assert.equal(belongsToConversation(received, 'me', 'peer'), true);
  assert.equal(belongsToConversation(received, 'me', 'other'), false);
  assert.equal(belongsToConversation({ ...received, toDeviceId: 'other' }, 'me', 'peer'), false);
  assert.equal(belongsToConversation({ fromDeviceId: 'me', toDeviceId: 'peer', ts: 2 }, 'me', 'peer'), true);
});
test('history retains another conversation and an in-flight transfer, without duplicates', () => {
  const live = [
    { fromDeviceId: 'other', ts: 1 },
    { fromDeviceId: 'me', toDeviceId: 'peer', ts: 3, _localId: 'file', _status: 'downloading' },
  ];
  const history = [{ id: 42, fromDeviceId: 'me', toDeviceId: 'peer', ts: 3, payload: { localId: 'file' } }];
  const merged = mergeMessageHistory(live, history);
  assert.equal(merged.length, 2);
  assert.equal(merged[0].fromDeviceId, 'other');
  assert.equal(merged[1]._status, 'downloading');
  assert.equal(merged[1].id, 42);
  assert.equal(mergeMessageHistory(merged, history).length, 2);
});
