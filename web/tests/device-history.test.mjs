import test from 'node:test';
import assert from 'node:assert/strict';
import {historyRecord, historyKey} from '../src/lib/deviceHistory.ts';
import {threadKeyOneToOne} from '../src/lib/threadKey.ts';
test('device history never persists file bytes or stale object URLs', () => {
 const m={type:'file',fromDeviceId:'a',toDeviceId:'b',ts:1,_status:'downloading',payload:{name:'a.txt',blob:new Blob(['private']),bytes:new Uint8Array([1]),url:'blob:abc'}};
 const saved=historyRecord(m,'b');
 assert.deepEqual(saved.payload,{name:'a.txt'}); assert.equal(saved._status,'failed');
 assert.equal(m._status,'downloading');
});
test('local history ignores unrelated recipients and signaling',()=> {
 assert.equal(historyRecord({type:'text',fromDeviceId:'a',toDeviceId:'c',ts:1},'b'),null);
 assert.equal(historyRecord({type:'webrtc_offer',fromDeviceId:'a',toDeviceId:'b',ts:1},'b'),null);
});
test('peer thread and local message identity survive billing account changes',()=> {
 assert.equal(threadKeyOneToOne('u:1','a','b'),threadKeyOneToOne('u:2','b','a'));
 assert.equal(threadKeyOneToOne('u:1','a','b'),'device|d1:a|d2:b');
 assert.equal(historyKey({type:'text',fromDeviceId:'a',toDeviceId:'b',ts:1,payload:{localId:'123'}}),'123');
});
