import test from 'node:test';
import assert from 'node:assert/strict';
import { createDavFolder, renameDavEntry, deleteDavEntry, uploadDav, saveDavConnection, readDavConnections, removeDavConnection } from '../src/lib/webdav.ts';
const connection = {id:'qa',name:'QA',url:'https://example.com/dav/',username:''};
const entry = {name:'file.txt',path:'https://example.com/dav/file.txt',directory:false,size:1,modified:''};

test('WebDAV mutations stay inside the selected root, including encoded traversal and foreign origins', async () => {
  const oldFetch = globalThis.fetch; let calls = [];
  globalThis.fetch = async (url, init) => { calls.push({url,init}); return new Response(null, {status:201}); };
  try {
    for (const path of ['https://evil.example/dav/file','https://example.com/dav-other/file','https://example.com/dav/../secret','https://example.com/dav/a%2f..%2f..%2fsecret','https://user:pass@example.com/dav/file']) {
      await assert.rejects(deleteDavEntry(connection,{...entry,path}), /invalid_path/);
    }
    assert.equal(calls.length,0);
    await renameDavEntry(connection,entry,'中文 文件.txt');
    assert.equal(calls[0].init.headers.get('Overwrite'),'F');
    assert.equal(new URL(calls[0].init.headers.get('Destination')).pathname,'/dav/%E4%B8%AD%E6%96%87%20%E6%96%87%E4%BB%B6.txt');
    assert.equal(calls[0].init.redirect,'error');
    await uploadDav(connection,connection.url,new File(['hello'],'sample.txt'));
    assert.equal(calls[1].init.headers.get('If-None-Match'),'*');
    await assert.rejects(createDavFolder(connection,connection.url,'../x'), /invalid_name/);
  } finally { globalThis.fetch = oldFetch; }
});
test('connection settings never persist passwords and reject URLs with embedded credentials', () => {
  const old = globalThis.localStorage; const data = new Map();
  globalThis.localStorage = {getItem:key => data.get(key) ?? null,setItem:(key,value) => data.set(key,value)};
  try {
    saveDavConnection({...connection,username:'demo'},'private-password');
    assert.equal(readDavConnections()[0].username,'demo');
    assert.ok(![...data.values()].join('').includes('private-password'));
    assert.throws(() => saveDavConnection({...connection,url:'https://user:secret@example.com/dav'},'x'), /invalid_url/);
    removeDavConnection(connection.id); assert.deepEqual(readDavConnections(),[]);
  } finally { globalThis.localStorage = old; }
});
