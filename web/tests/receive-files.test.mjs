import test from 'node:test';
import assert from 'node:assert/strict';
import { createDirectoryReceiveSink } from '../src/lib/receiveFiles.ts';

function folder({ permission = 'granted', failWrite = false } = {}) {
  const files = new Map([['keep.txt', [new Blob(['original'])]]]);
  let closed = 0;
  return {
    files, get closed() { return closed; },
    async queryPermission() { return permission; },
    async getFileHandle(name, options) {
      if (!options?.create && !files.has(name)) throw new DOMException('missing', 'NotFoundError');
      return { async createWritable() {
        const chunks = [];
        return {
          async write(data) { if (failWrite) throw new Error('disk full'); chunks.push(data); },
          async close() { files.set(name, chunks); closed++; },
          async abort() { chunks.length = 0; },
        };
      } };
    },
  };
}
test('selected folder streams chunks, preserves existing names and finishes empty files', async () => {
  const dir = folder();
  const [first, second] = await Promise.all([
    createDirectoryReceiveSink(dir, 'keep.txt'), createDirectoryReceiveSink(dir, 'keep.txt'),
  ]);
  await first.write(new Blob(['中文']));
  await first.write(new Blob(['🦐']));
  await first.finish();
  await second.finish();
  assert.equal(await new Blob(dir.files.get('keep.txt')).text(), 'original');
  const copies = await Promise.all(['keep (1).txt', 'keep (2).txt'].map(name => new Blob(dir.files.get(name)).text()));
  assert.deepEqual(copies.sort(), ['', '中文🦐']);
  assert.equal(dir.closed, 2);
});
test('permission loss and disk errors cannot report successful saves', async () => {
  await assert.rejects(createDirectoryReceiveSink(folder({ permission: 'prompt' }), 'a.bin'), /Select/);
  const dir = folder({ failWrite: true });
  const sink = await createDirectoryReceiveSink(dir, 'a.bin');
  await assert.rejects(sink.write(new Uint8Array([1])), /disk full/);
  await sink.abort();
  assert.equal(dir.closed, 0);
});
