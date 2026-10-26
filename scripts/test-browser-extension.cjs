const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const code = fs.readFileSync('BrowserExtension/bridge.js', 'utf8');
async function run(request, overrides = {}, token = '12345678-1234-1234-1234-123456789abc') {
  const sent = [], created = [], closed = [];
  const chrome = {
    runtime: { sendNativeMessage: async (_, m) => { sent.push(m); return m.action === 'claim' ? request : {ok: true}; } },
    tabs: { getCurrent: async () => ({id: 99}), create: async x => {created.push(x); return {id: created.length};}, remove: async id => closed.push(id), group: async () => {} },
    windows: { getAll: async () => [{id: 1, incognito: false, tabs: [{id: 2, title:'Work',active:false},{id:99,title:'Openly',active:true}]},{id:3,incognito:false,tabs:[{id:99}]}], get: async id => ({id}), update: async () => {} },
    tabGroups: {query: async () => [{id:4,windowId:1,title:'Group',color:'blue'}],get: async () => ({windowId:1})}
  };
  for (const [key, value] of Object.entries(overrides)) Object.assign(chrome[key], value);
  await vm.runInNewContext(code, {chrome,location:{hash:'#'+token},document:{getElementById:()=>({textContent:''})}});
  return {sent,created,closed,result:sent.find(m=>m.action==='complete')?.result};
}
(async () => {
  const list = await run({action:'list'});
  assert.equal(list.result.windows.length,1); assert.equal(list.result.windows[0].title,'Work'); assert.equal(list.result.windows[0].count,1); assert.equal(list.closed[0],99);
  const open = await run({action:'open',windowId:1,groupId:4,urls:['https://example.com']});
  assert.equal(open.result.ok,true); assert.equal(open.created[0].windowId,1);
  const stale = await run({action:'open',windowId:1,groupId:4,urls:['https://example.com']},{tabGroups:{get:async()=>({windowId:2})}});
  assert.equal(stale.created.length,0); assert.match(stale.result.error,/已移动/);
  const partial = await run({action:'open',windowId:1,urls:['https://example.com','file:///tmp/test']});
  assert.equal(partial.result.opened,1); assert.match(partial.result.error,/已提交 1/);
  const invalid = await run({action:'list'},{},'bad'); assert.equal(invalid.sent.length,0);
  console.log('PASS: 5 extension scenarios (list, group routing, stale target, partial failure, invalid token)');
})().catch(e=>{console.error(e);process.exit(1)});
