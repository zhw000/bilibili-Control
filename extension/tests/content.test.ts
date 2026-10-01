// @vitest-environment jsdom
// @vitest-environment-options {"url":"https://www.bilibili.com/video/BV1/"}
import {afterEach,beforeEach,expect,it,vi} from 'vitest';

let receive:(message:unknown,sender:unknown,respond:(reply:any)=>void)=>unknown;
let emit:ReturnType<typeof vi.fn>,play:ReturnType<typeof vi.fn>,pause:ReturnType<typeof vi.fn>;
const listeners:Array<()=>void>=[];
const binding={bvid:'BV1',part:1,playbackId:'queue-1',managed:true};
function request(method:string,params:Record<string,unknown>={}){return new Promise<any>(resolve=>receive({method,params},{},resolve))}
beforeEach(async()=>{
  vi.resetModules();vi.useFakeTimers();history.replaceState({},'','/video/BV1/');
  document.body.innerHTML='<div class="bpx-player-container" data-screen="normal"><div class="bpx-player-video-wrap"><video></video></div><div class="bpx-player-ctrl-setting-autoplay"><input type="checkbox" aria-label="自动开播" checked></div></div>';
  play=vi.spyOn(HTMLMediaElement.prototype,'play').mockResolvedValue();pause=vi.spyOn(HTMLMediaElement.prototype,'pause').mockImplementation(()=>{});
  for(const target of [document,window]){
    const add=target.addEventListener.bind(target);
    vi.spyOn(target,'addEventListener').mockImplementation((type:any,listener:any,options:any)=>{add(type,listener,options);listeners.push(()=>target.removeEventListener(type,listener,options))});
  }
  const observe=MutationObserver.prototype.observe;
  vi.spyOn(MutationObserver.prototype,'observe').mockImplementation(function(this:MutationObserver,target:Node,options?:MutationObserverInit){observe.call(this,target,options);listeners.push(()=>this.disconnect())});
  emit=vi.fn().mockResolvedValue(undefined);
  vi.stubGlobal('chrome',{runtime:{id:'test-extension',sendMessage:emit,onMessage:{addListener:vi.fn(listener=>receive=listener),removeListener:vi.fn()}}});
  await import('../src/content');
});
afterEach(()=>{listeners.splice(0).forEach(remove=>remove());vi.clearAllTimers();vi.useRealTimers();vi.restoreAllMocks();vi.unstubAllGlobals()});

it('leaves manual playback and auto-start untouched on load and periodic reports',async()=>{
  await vi.advanceTimersByTimeAsync(3000);
  expect(play).not.toHaveBeenCalled();expect(pause).not.toHaveBeenCalled();
  expect(document.querySelector<HTMLInputElement>('[aria-label="自动开播"]')!.checked).toBe(true);
});
it('does not switch off auto-start while attaching or running a remote queue',async()=>{
  expect((await request('player.attach',binding)).ok).toBe(true);
  await vi.advanceTimersByTimeAsync(2000);await request('player.manage',{enabled:false});
  expect(document.querySelector<HTMLInputElement>('[aria-label="自动开播"]')!.checked).toBe(true);
  expect(play).not.toHaveBeenCalled();expect(pause).not.toHaveBeenCalled();
  expect(emit.mock.calls.some(([event])=>event.event==='player.autoNextCaptured')).toBe(false);
});
it('temporarily disables only next-video autoplay and restores it on release',async()=>{
  document.body.insertAdjacentHTML('beforeend','<div class="next-play"><input type="checkbox" checked></div>');
  const next=document.querySelector<HTMLInputElement>('.next-play input')!;
  await request('player.attach',binding);expect(next.checked).toBe(false);
  expect(emit).toHaveBeenCalledWith({event:'player.autoNextCaptured',data:{value:true}});
  await request('player.manage',{enabled:false});expect(next.checked).toBe(true);
  expect(document.querySelector<HTMLInputElement>('[aria-label="自动开播"]')!.checked).toBe(true);
});
it('preserves an explicitly disabled auto-start preference',async()=>{
  const start=document.querySelector<HTMLInputElement>('[aria-label="自动开播"]')!;start.checked=false;
  await request('player.attach',binding);await request('player.manage',{enabled:false});expect(start.checked).toBe(false);
});
it('rejects a stale attach before touching the page or claiming its end event',async()=>{
  const reply=await request('player.attach',{...binding,bvid:'BV2'});
  expect(reply.error.code).toBe('target_changed');
  const site=vi.fn();document.querySelector('video')!.addEventListener('ended',site);
  document.querySelector('video')!.dispatchEvent(new Event('ended'));expect(site).toHaveBeenCalledOnce();
});
it.each(['/video/BV2/','/video/BV1/?p=2'])('releases ownership immediately when manually navigating to %s',async url=>{
  await request('player.attach',binding);history.replaceState({},'',url);
  const site=vi.fn();document.querySelector('video')!.addEventListener('ended',site);
  document.querySelector('video')!.dispatchEvent(new Event('ended'));
  expect(site).toHaveBeenCalledOnce();expect((await request('player.state')).result.playbackId).toBeUndefined();
  expect(emit.mock.calls.some(([event])=>event.event==='player.ended'||event.event==='player.partEnded')).toBe(false);
});
it('still advances a queue exactly once through the captured end event',async()=>{
  await request('player.attach',binding);const v=document.querySelector('video')!,site=vi.fn();v.addEventListener('ended',site);
  v.dispatchEvent(new Event('ended'));v.dispatchEvent(new Event('ended'));
  expect(site).not.toHaveBeenCalled();expect(emit.mock.calls.filter(([event])=>event.event==='player.ended')).toHaveLength(1);
});
it('reports leaving the player fullscreen on the computer at once and exactly once',async()=>{
  const player=document.querySelector('.bpx-player-container')!;
  player.insertAdjacentHTML('beforeend','<button class="bpx-player-ctrl-web"></button>');
  player.querySelector('.bpx-player-ctrl-web')!.addEventListener('click',()=>player.setAttribute('data-screen',player.getAttribute('data-screen')==='web'?'normal':'web'));
  expect((await request('player.command',{action:'fullscreen',value:true})).result.fullscreen).toBe(true);
  await vi.advanceTimersByTimeAsync(1000);emit.mockClear();
  player.setAttribute('data-screen','normal');await vi.advanceTimersByTimeAsync(0);
  const exits=()=>emit.mock.calls.filter(([message])=>message.event==='player.fullscreenExited').length;
  expect(exits()).toBe(1);
  await vi.advanceTimersByTimeAsync(3000);expect(exits()).toBe(1);
});
it('waits for the player controls when fullscreen is restored on a freshly loaded page',async()=>{
  const player=document.querySelector('.bpx-player-container')!;
  const reply=request('player.command',{action:'fullscreen',value:true,wait:true});
  await vi.advanceTimersByTimeAsync(600);
  player.insertAdjacentHTML('beforeend','<button class="bpx-player-ctrl-web"></button>');
  player.querySelector('.bpx-player-ctrl-web')!.addEventListener('click',()=>player.setAttribute('data-screen','web'));
  await vi.advanceTimersByTimeAsync(400);
  expect((await reply).result.fullscreen).toBe(true);
});
it('abandons a pending remote play when the user changes videos during loading',async()=>{
  const result=request('player.bind',binding);history.replaceState({},'','/video/BV2/');
  await vi.advanceTimersByTimeAsync(200);
  expect((await result).error.code).toBe('target_changed');expect(play).not.toHaveBeenCalled();expect(pause).not.toHaveBeenCalled();
});
it('cancels pending playback when the remote queue is stopped',async()=>{
  const result=request('player.bind',binding);await request('player.manage',{enabled:false});
  await vi.advanceTimersByTimeAsync(200);expect((await result).error.code).toBe('target_changed');expect(play).not.toHaveBeenCalled();
});
it('plays and seeks only for an explicit matching remote bind',async()=>{
  const v=document.querySelector('video')!;Object.defineProperties(v,{readyState:{value:1},duration:{value:100}});
  expect((await request('player.bind',{...binding,time:25})).ok).toBe(true);
  expect(play).toHaveBeenCalledOnce();expect(v.currentTime).toBe(25);
});
it.each(['sync','async','missing-id','runtime-getter'])('retires invalidated scripts (%s) and restores the player without changing playback',async mode=>{
  document.body.insertAdjacentHTML('beforeend','<div class="next-play"><input type="checkbox" checked></div>');
  const next=document.querySelector<HTMLInputElement>('.next-play input')!,v=document.querySelector('video')!,siteEnded=vi.fn();
  await request('player.attach',binding);expect(next.checked).toBe(false);v.addEventListener('ended',siteEnded);
  emit.mockClear();
  if(mode==='sync')emit.mockImplementation(()=>{throw new Error('Extension context invalidated.')});
  if(mode==='async')emit.mockRejectedValue(new Error('Extension context invalidated.'));
  if(mode==='missing-id')(chrome.runtime as any).id=undefined;
  if(mode==='runtime-getter')Object.defineProperty(chrome.runtime,'id',{get(){throw new Error('Extension context invalidated.')}});
  await vi.advanceTimersByTimeAsync(1000);
  expect(next.checked).toBe(true);expect(vi.getTimerCount()).toBe(0);
  expect(chrome.runtime.onMessage.removeListener).toHaveBeenCalledWith(receive);
  const attempts=emit.mock.calls.length;
  v.dispatchEvent(new Event('pause'));v.dispatchEvent(new Event('ended'));await vi.advanceTimersByTimeAsync(5000);
  expect(emit).toHaveBeenCalledTimes(attempts);expect(siteEnded).toHaveBeenCalledOnce();
  expect(play).not.toHaveBeenCalled();expect(pause).not.toHaveBeenCalled();
  expect(document.querySelector<HTMLInputElement>('[aria-label="自动开播"]')!.checked).toBe(true);
});
it('lets the site handle an ended event when the extension was reloaded before the next report',async()=>{
  await request('player.attach',binding);(chrome.runtime as any).id=undefined;
  const v=document.querySelector('video')!,site=vi.fn();v.addEventListener('ended',site);v.dispatchEvent(new Event('ended'));
  expect(site).toHaveBeenCalledOnce();expect(vi.getTimerCount()).toBe(0);
});
it('keeps reporting after a temporary missing receiver instead of retiring a valid extension',async()=>{
  emit.mockClear();emit.mockRejectedValueOnce(new Error('Could not establish connection. Receiving end does not exist.'));
  await vi.advanceTimersByTimeAsync(2000);expect(emit).toHaveBeenCalledTimes(2);
  expect(chrome.runtime.onMessage.removeListener).not.toHaveBeenCalled();
});
it('handles a synchronous invalidation during the initial ready notification',async()=>{
  (chrome.runtime as any).id=undefined;await vi.advanceTimersByTimeAsync(1000);
  vi.resetModules();(chrome.runtime as any).id='test-extension';emit.mockClear();
  emit.mockImplementation(()=>{throw new Error('Extension context invalidated.')});
  await expect(import('../src/content')).resolves.toBeDefined();
  expect(emit).toHaveBeenCalledWith({event:'content.ready'});expect(vi.getTimerCount()).toBe(0);
});
it('abandons an in-flight bind and its response after reload',async()=>{
  const respond=vi.fn(()=>{throw new Error('Extension context invalidated.')});
  receive({method:'player.bind',params:binding},{},respond);(chrome.runtime as any).id=undefined;
  Object.defineProperty(document.querySelector('video'),'readyState',{value:1});
  await vi.advanceTimersByTimeAsync(1000);
  expect(play).not.toHaveBeenCalled();expect(respond).not.toHaveBeenCalled();expect(vi.getTimerCount()).toBe(0);
});
it('catches a response callback that throws after its channel was invalidated',async()=>{
  receive({method:'player.state',params:{}},{},()=>{throw new Error('Extension context invalidated.')});
  await vi.advanceTimersByTimeAsync(0);expect(vi.getTimerCount()).toBe(0);
});
it('does not change the player if capturing a newly loaded auto-next control discovers invalidation',async()=>{
  const respond=vi.fn();receive({method:'player.bind',params:{...binding,time:25}},{},respond);
  document.body.insertAdjacentHTML('beforeend','<div class="next-play"><input type="checkbox" checked></div>');
  const v=document.querySelector('video')!;Object.defineProperties(v,{readyState:{value:1},duration:{value:100}});
  emit.mockImplementation(()=>{throw new Error('Extension context invalidated.')});
  await vi.advanceTimersByTimeAsync(200);
  expect(play).not.toHaveBeenCalled();expect(v.currentTime).toBe(0);expect(respond).not.toHaveBeenCalled();
  expect(document.querySelector<HTMLInputElement>('.next-play input')!.checked).toBe(true);
});
