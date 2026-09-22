import test from 'node:test';
import assert from 'node:assert/strict';
import { DeviceSessionRetry } from '../src/lib/api/DeviceSessionRetry.ts';

test('expired device sessions renew once across concurrent and late responses', async () => {
  let token = 'expired';
  let renewals = 0;
  const retry = new DeviceSessionRetry(() => token);
  retry.renew = async () => {
    renewals++;
    await new Promise(resolve => setTimeout(resolve, 5));
    token = 'fresh';
  };
  const run = delay => retry.run(async used => {
    if (used === 'expired') await new Promise(resolve => setTimeout(resolve, delay));
    return { status: used === 'fresh' ? 204 : 401 };
  });
  const results = await Promise.all([...Array.from({ length: 12 }, () => run(0)), run(25)]);
  assert.ok(results.every(r => r.status === 204));
  assert.equal(renewals, 1);
});

test('forbidden, throttled and delivered responses are never replayed', async () => {
  const retry = new DeviceSessionRetry(() => 'valid');
  retry.renew = async () => assert.fail('must not renew');
  for (const status of [204, 403, 429, 500]) {
    let calls = 0;
    assert.equal((await retry.run(async () => { calls++; return { status }; })).status, status);
    assert.equal(calls, 1);
  }
});

test('renewal failure can recover later, while a rejected renewed token stops after one retry', async () => {
  const retry = new DeviceSessionRetry(() => 'token');
  retry.renew = async () => { throw new Error('offline'); };
  await assert.rejects(retry.run(async () => ({ status: 401 })), /offline/);
  let calls = 0;
  retry.renew = async () => {};
  const result = await retry.run(async () => { calls++; return { status: 401 }; });
  assert.equal(result.status, 401);
  assert.equal(calls, 2);
});
