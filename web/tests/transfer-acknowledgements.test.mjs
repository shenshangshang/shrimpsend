import test from 'node:test';
import assert from 'node:assert/strict';
import { TransferAcknowledgements } from '../src/lib/webrtc/TransferAcknowledgements.ts';

test('receiver must explicitly confirm success', async () => {
  const a = new TransferAcknowledgements();
  const saved = a.wait('saved');
  a.settle('saved', true);
  await saved;
  const failed = a.wait('failed');
  a.settle('failed', false, 'disk full');
  await assert.rejects(failed, /disk full/);
});
test('timeout and disconnect never become a successful send', async () => {
  const a = new TransferAcknowledgements();
  await assert.rejects(a.wait('timeout', 5), /timed out/);
  const disconnected = a.wait('disconnect');
  a.close();
  await assert.rejects(disconnected, /Connection closed/);
});
