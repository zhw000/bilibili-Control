import {afterEach,beforeEach,expect,it,vi} from 'vitest';

let nativeMessage:(request:any)=>void,tabUpdated:(id:number,change:any)=>void,contentMessage:(message:any,sender:any,respond:()=>void)=>void;
let tabRemoved:(id:number)=>void,tabActivated:(info:{tabId:number;windowId:number})=>void;
let chromeMock:any,post:ReturnType<typeof vi.fn>,windowState:string;
async function flush(){for(let i=0;i<20;i++)await Promise.resolve()}
async function request(method:string,params:Record<string,unknown>={}){nativeMessage({v:1,id:'request-1',method,params});await flush();return post.mock.calls.find(([reply])=>reply.id==='request-1')?.[0]}
async function call(method:string,params:Record<string,unknown>,id:string){
  nativeMessage({v:1,id,method,params});
  return vi.waitFor(()=>{const found=post.mock.calls.find(([reply])=>reply.id===id)?.[0];if(!found)throw new Error('pending');return found});
}
beforeEach(async()=>{
  vi.resetModules();post=vi.fn();windowState='maximized';
  chromeMock={
    storage:{session:{get:vi.fn().mockResolvedValue({targetId:1,managed:true,binding:{bvid:'BV1',part:1,playbackId:'queue-1',managed:true},originalAutoplay:true}),set:vi.fn().mockResolvedValue(undefined)}},
    tabs:{get:vi.fn().mockResolvedValue({id:1,url:'https://www.bilibili.com/video/BV1/',windowId:10}),sendMessage:vi.fn().mockResolvedValue({ok:true,result:{fullscreen:true}}),onRemoved:{addListener:vi.fn(listener=>tabRemoved=listener)},onUpdated:{addListener:vi.fn(listener=>tabUpdated=listener)},onActivated:{addListener:vi.fn(listener=>tabActivated=listener)}},
    windows:{get:vi.fn(async()=>({id:10,state:windowState})),update:vi.fn(async(_id:number,info:{state:string})=>{windowState=info.state})},
    runtime:{connectNative:vi.fn(()=>({postMessage:post,onMessage:{addListener:vi.fn(listener=>nativeMessage=listener)},onDisconnect:{addListener:vi.fn()}})),getManifest:()=>({version:'0.4.1'}),onMessage:{addListener:vi.fn(listener=>contentMessage=listener)},onInstalled:{addListener:vi.fn()},onStartup:{addListener:vi.fn()}},
    action:{setBadgeText:vi.fn(),setBadgeBackgroundColor:vi.fn()},alarms:{onAlarm:{addListener:vi.fn()},create:vi.fn()}
  };
  vi.stubGlobal('chrome',chromeMock);await import('../src/background');await flush();
});
afterEach(()=>vi.unstubAllGlobals());
async function enterFullscreen(){
  expect((await call('player.command',{action:'fullscreen',value:true},'fullscreen-on')).ok).toBe(true);
  expect(windowState).toBe('fullscreen');chromeMock.windows.update.mockClear();chromeMock.tabs.sendMessage.mockClear();
}
it('remote fullscreen fills the page first, then hides the browser tabs, and restores the window when turned off',async()=>{
  expect((await call('player.command',{action:'fullscreen',value:true},'on')).ok).toBe(true);
  expect(chromeMock.tabs.sendMessage).toHaveBeenCalledWith(1,{method:'player.command',params:{action:'fullscreen',value:true}});
  expect(chromeMock.windows.update).toHaveBeenCalledWith(10,{state:'fullscreen'});
  expect(chromeMock.tabs.sendMessage.mock.invocationCallOrder[0]).toBeLessThan(chromeMock.windows.update.mock.invocationCallOrder[0]);
  expect(chromeMock.storage.session.set).toHaveBeenCalledWith(expect.objectContaining({fullscreenWindow:{id:10,state:'maximized'}}));
  expect((await call('player.command',{action:'fullscreen',value:false},'off')).ok).toBe(true);
  expect(chromeMock.windows.update).toHaveBeenLastCalledWith(10,{state:'maximized'});expect(windowState).toBe('maximized');
});
it('restores the window when the page is unresponsive to a remote exit',async()=>{
  await enterFullscreen();chromeMock.tabs.sendMessage.mockResolvedValue({ok:false,error:{code:'player_error',message:'网页无响应'}});
  expect((await call('player.command',{action:'fullscreen',value:false},'off')).ok).toBe(false);expect(windowState).toBe('maximized');
});
it('leaving the player fullscreen on the computer (Escape or its button) also restores the window, once',async()=>{
  await enterFullscreen();
  contentMessage({event:'player.fullscreenExited'},{tab:{id:1}},()=>{});
  await vi.waitFor(()=>expect(windowState).toBe('maximized'));
  contentMessage({event:'player.fullscreenExited'},{tab:{id:1}},()=>{});await flush();
  expect(chromeMock.windows.update).toHaveBeenCalledTimes(1);
});
it('keeps fullscreen on the next loaded page and gives the window back when the page has no player',async()=>{
  await enterFullscreen();
  contentMessage({event:'content.ready'},{tab:{id:1}},()=>{});
  await vi.waitFor(()=>expect(chromeMock.tabs.sendMessage).toHaveBeenCalledWith(1,{method:'player.command',params:{action:'fullscreen',value:true,wait:true}}));
  await flush();expect(windowState).toBe('fullscreen');
  chromeMock.tabs.sendMessage.mockResolvedValue({ok:false,error:{code:'unsupported',message:'找不到网页全屏按钮'}});
  contentMessage({event:'content.ready'},{tab:{id:1}},()=>{});
  await vi.waitFor(()=>expect(windowState).toBe('maximized'));
});
it('does not take over or undo a window the user already made fullscreen',async()=>{
  windowState='fullscreen';
  expect((await call('player.command',{action:'fullscreen',value:true},'on')).ok).toBe(true);
  expect((await call('player.command',{action:'fullscreen',value:false},'off')).ok).toBe(true);
  expect(chromeMock.windows.update).not.toHaveBeenCalled();expect(windowState).toBe('fullscreen');
});
it.each(['closing the video tab','switching to another tab','leaving Bilibili in the video tab'])('%s gives the window back',async action=>{
  await enterFullscreen();
  if(action==='closing the video tab')tabRemoved(1);
  else if(action==='switching to another tab')tabActivated({tabId:2,windowId:10});
  else tabUpdated(1,{url:'https://example.com/'});
  await vi.waitFor(()=>expect(windowState).toBe('maximized'));
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
it('reads the homepage feed through fixed API requests without touching tabs',async()=>{
  const wbi_img={img_url:'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',sub_url:'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png'};
  const fetchMock=vi.fn().mockResolvedValueOnce({ok:true,json:async()=>({code:0,data:{isLogin:true,uname:'账号',wbi_img}})}).mockResolvedValueOnce({ok:true,json:async()=>({code:0,data:{item:[]}})});
  vi.stubGlobal('fetch',fetchMock);
  nativeMessage({v:1,id:'feed-1',method:'home.feed',params:{page:1}});
  const reply=await vi.waitFor(()=>{const found=post.mock.calls.find(([message])=>message.id==='feed-1')?.[0];if(!found)throw new Error('pending');return found});
  expect(reply).toEqual({v:1,id:'feed-1',ok:true,result:{loggedIn:true,accountName:'账号',items:[],page:1,nextPage:2}});
  expect(fetchMock.mock.calls.map(([url])=>new URL(url).pathname)).toEqual(['/x/web-interface/nav','/x/web-interface/wbi/index/top/feed/rcmd']);
  expect(chromeMock.tabs.sendMessage).not.toHaveBeenCalled();
});
it('does not reattach a stopped queue when the page reloads',async()=>{
  await request('player.manage',{enabled:false});chromeMock.tabs.sendMessage.mockClear();
  contentMessage({event:'content.ready'},{tab:{id:1}},()=>{});await flush();expect(chromeMock.tabs.sendMessage).not.toHaveBeenCalled();
});
