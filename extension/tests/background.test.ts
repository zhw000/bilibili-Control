import {afterEach,beforeEach,expect,it,vi} from 'vitest';

let nativeMessage:(request:any)=>void,tabUpdated:(id:number,change:any)=>void,contentMessage:(message:any,sender:any,respond:()=>void)=>void;
let chromeMock:any,post:ReturnType<typeof vi.fn>;
async function flush(){for(let i=0;i<20;i++)await Promise.resolve()}
async function request(method:string,params:Record<string,unknown>={}){nativeMessage({v:1,id:'request-1',method,params});await flush();return post.mock.calls.find(([reply])=>reply.id==='request-1')?.[0]}
beforeEach(async()=>{
  vi.resetModules();post=vi.fn();
  chromeMock={
    storage:{session:{get:vi.fn().mockResolvedValue({targetId:1,managed:true,binding:{bvid:'BV1',part:1,playbackId:'queue-1',managed:true},originalAutoplay:true}),set:vi.fn().mockResolvedValue(undefined)}},
    tabs:{get:vi.fn().mockResolvedValue({id:1,url:'https://www.bilibili.com/video/BV1/',windowId:10}),sendMessage:vi.fn().mockResolvedValue({ok:true,result:{fullscreen:true}}),onRemoved:{addListener:vi.fn()},onUpdated:{addListener:vi.fn(listener=>tabUpdated=listener)}},
    windows:{get:vi.fn().mockResolvedValue({id:10,state:'maximized'}),update:vi.fn().mockResolvedValue(undefined)},
    runtime:{connectNative:vi.fn(()=>({postMessage:post,onMessage:{addListener:vi.fn(listener=>nativeMessage=listener)},onDisconnect:{addListener:vi.fn()}})),getManifest:()=>({version:'0.4.1'}),onMessage:{addListener:vi.fn(listener=>contentMessage=listener)},onInstalled:{addListener:vi.fn()},onStartup:{addListener:vi.fn()}},
    action:{setBadgeText:vi.fn(),setBadgeBackgroundColor:vi.fn()},alarms:{onAlarm:{addListener:vi.fn()},create:vi.fn()}
  };
  vi.stubGlobal('chrome',chromeMock);await import('../src/background');await flush();
});
afterEach(()=>vi.unstubAllGlobals());
it('remote fullscreen never adds a second browser fullscreen layer',async()=>{
  const result=await request('player.command',{action:'fullscreen',value:true});expect(result.ok).toBe(true);
  expect(chromeMock.tabs.sendMessage).toHaveBeenCalledWith(1,{method:'player.command',params:{action:'fullscreen',value:true}});
  expect(chromeMock.windows.update).not.toHaveBeenCalled();
});
it.each(['https://www.bilibili.com/video/BV2/','https://www.bilibili.com/video/BV1/?p=2'])('releases the old page queue on manual navigation to %s',async url=>{
  tabUpdated(1,{url});await flush();
  expect(post).toHaveBeenCalledWith({v:1,event:'target.navigated',data:{}});
  expect(chromeMock.tabs.sendMessage).toHaveBeenCalledWith(1,{method:'player.manage',params:{enabled:false}});
  expect(chromeMock.storage.session.set).toHaveBeenCalledWith(expect.objectContaining({binding:null,managed:false,originalAutoNext:null}));
  chromeMock.tabs.sendMessage.mockClear();contentMessage({event:'content.ready'},{tab:{id:1}},()=>{});await flush();expect(chromeMock.tabs.sendMessage).not.toHaveBeenCalled();
});
it('keeps the binding when only tracking parameters change',async()=>{
  tabUpdated(1,{url:'https://www.bilibili.com/video/BV1/?p=1&spm_id_from=test'});await flush();
  expect(post.mock.calls.some(([event])=>event.event==='target.navigated')).toBe(false);
});
it('does not reuse the old auto-start preference as a next-video preference',async()=>{
  contentMessage({event:'content.ready'},{tab:{id:1}},()=>{});await flush();
  expect(chromeMock.tabs.sendMessage).toHaveBeenCalledWith(1,{method:'player.attach',params:expect.objectContaining({originalAutoNext:undefined})});
});
it('does not reattach a stopped queue when the page reloads',async()=>{
  await request('player.manage',{enabled:false});chromeMock.tabs.sendMessage.mockClear();
  contentMessage({event:'content.ready'},{tab:{id:1}},()=>{});await flush();expect(chromeMock.tabs.sendMessage).not.toHaveBeenCalled();
});
