import {isWebFullscreen} from './player-dom';
import {RemoteError} from './types';

export function isPlayerFullscreen():boolean{return !!document.fullscreenElement||isWebFullscreen()}

export async function setPlayerFullscreen(enabled:boolean,isActive:()=>boolean=()=>true):Promise<void>{
  const checkActive=()=>{if(!isActive())throw new RemoteError('extension_reloaded','扩展已重新加载，请刷新这个 B 站页面')};
  checkActive();
  // Retire the old CSS fallback even if the native control has appeared since.
  if(!enabled){
    document.getElementById('biliremote-fullscreen')?.remove();
    if(document.fullscreenElement)await document.exitFullscreen();
  }
  checkActive();
  if(isPlayerFullscreen()===enabled)return;
  const control=document.querySelector<HTMLElement>('.bpx-player-ctrl-web,.bilibili-player-video-web-fullscreen');
  if(!control)throw new RemoteError('unsupported','找不到网页全屏按钮，请在电脑播放器中操作');
  control.click();
  for(let i=0;i<10;i++){
    checkActive();
    if(isPlayerFullscreen()===enabled)return;
    await new Promise(resolve=>setTimeout(resolve,100));
  }
  throw new RemoteError('fullscreen_not_changed','网页全屏未切换，请在电脑播放器中操作');
}

export function installFullscreenEscape(onChanged:()=>void,isActive:()=>boolean=()=>true):()=>void{
  const listeners=new AbortController();
  let pending:ReturnType<typeof setTimeout>|undefined;
  const active=()=>!listeners.signal.aborted&&isActive();
  document.addEventListener('keydown',event=>{
    if(!active())return;
    if(event.key!=='Escape'||document.fullscreenElement||!isWebFullscreen())return;
    // Let the site's Escape handler run first; never toggle it back on.
    clearTimeout(pending);
    pending=setTimeout(()=>{pending=undefined;if(active())void setPlayerFullscreen(false,active).then(()=>{if(active())onChanged()}).catch(()=>{})},0);
  },{signal:listeners.signal});
  document.addEventListener('fullscreenchange',()=>{if(active())onChanged()},{signal:listeners.signal});
  return ()=>{listeners.abort();clearTimeout(pending)};
}
