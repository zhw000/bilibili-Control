// @vitest-environment jsdom
import {afterEach,beforeEach,expect,it,vi} from 'vitest';
import {installFullscreenEscape,isPlayerFullscreen,setPlayerFullscreen} from '../src/fullscreen';
const listeners:Array<()=>void>=[];
beforeEach(()=>{
  vi.useFakeTimers();document.head.innerHTML='';document.body.innerHTML='<div class="bpx-player-container" data-screen="normal"><button class="bpx-player-ctrl-web"></button></div>';
  Object.defineProperty(document,'fullscreenElement',{configurable:true,value:null});
  const add=document.addEventListener.bind(document);
  vi.spyOn(document,'addEventListener').mockImplementation((type:any,listener:any,options:any)=>{add(type,listener,options);listeners.push(()=>document.removeEventListener(type,listener,options))});
});
afterEach(()=>{listeners.splice(0).forEach(remove=>remove());vi.clearAllTimers();vi.useRealTimers();vi.restoreAllMocks()});
function siteToggle(){
  const player=document.querySelector('.bpx-player-container')!;
  const click=vi.fn(()=>player.setAttribute('data-screen',player.getAttribute('data-screen')==='web'?'normal':'web'));
  document.querySelector('button')!.addEventListener('click',click);return click;
}
it('enters and exits the website fullscreen with idempotent commands',async()=>{
  const click=siteToggle();await setPlayerFullscreen(true);await setPlayerFullscreen(true);expect(isPlayerFullscreen()).toBe(true);
  await setPlayerFullscreen(false);await setPlayerFullscreen(false);expect(isPlayerFullscreen()).toBe(false);expect(click).toHaveBeenCalledTimes(2);
});
it.each([false,true])('Escape exits once, including when the site also handles it (%s)',async siteHandlesEscape=>{
  const click=siteToggle(),changed=vi.fn();installFullscreenEscape(changed);await setPlayerFullscreen(true);
  if(siteHandlesEscape)document.addEventListener('keydown',()=>document.querySelector('button')!.click());
  document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}));await vi.runAllTimersAsync();
  expect(isPlayerFullscreen()).toBe(false);expect(click).toHaveBeenCalledTimes(2);expect(changed).toHaveBeenCalledOnce();
});
it('removes the legacy CSS overlay even after the site control appears',async()=>{
  const click=siteToggle();document.head.innerHTML='<style id="biliremote-fullscreen"></style>';
  await setPlayerFullscreen(false);expect(isPlayerFullscreen()).toBe(false);expect(document.getElementById('biliremote-fullscreen')).toBeNull();expect(click).not.toHaveBeenCalled();
});
it('does not create an inescapable CSS overlay when the player control is absent',async()=>{
  document.querySelector('button')!.remove();await expect(setPlayerFullscreen(true)).rejects.toMatchObject({code:'unsupported'});
  expect(document.getElementById('biliremote-fullscreen')).toBeNull();
});
it('reports and exits real player fullscreen without toggling web fullscreen on',async()=>{
  const click=siteToggle();Object.defineProperty(document,'fullscreenElement',{configurable:true,value:document.querySelector('.bpx-player-container')});
  Object.defineProperty(document,'exitFullscreen',{configurable:true,value:vi.fn(async()=>Object.defineProperty(document,'fullscreenElement',{configurable:true,value:null}))});
  expect(isPlayerFullscreen()).toBe(true);await setPlayerFullscreen(false);expect(isPlayerFullscreen()).toBe(false);expect(click).not.toHaveBeenCalled();
});
it('reports an unsuccessful fullscreen switch instead of claiming success',async()=>{
  const result=expect(setPlayerFullscreen(true)).rejects.toMatchObject({code:'fullscreen_not_changed'});
  await vi.runAllTimersAsync();await result;expect(isPlayerFullscreen()).toBe(false);
});
it('removes Escape handling and cancels a pending exit when the content script is disposed',async()=>{
  const click=siteToggle(),changed=vi.fn(),dispose=installFullscreenEscape(changed);await setPlayerFullscreen(true);click.mockClear();
  document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}));dispose();
  await vi.runAllTimersAsync();document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}));document.dispatchEvent(new Event('fullscreenchange'));await vi.runAllTimersAsync();
  expect(click).not.toHaveBeenCalled();expect(changed).not.toHaveBeenCalled();expect(isPlayerFullscreen()).toBe(true);
});
it('does not perform a queued Escape exit after the runtime becomes invalid',async()=>{
  const click=siteToggle(),changed=vi.fn();let active=true;installFullscreenEscape(changed,()=>active);await setPlayerFullscreen(true);click.mockClear();
  document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}));active=false;await vi.runAllTimersAsync();
  expect(click).not.toHaveBeenCalled();expect(changed).not.toHaveBeenCalled();
});
