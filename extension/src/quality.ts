import {RemoteError} from './types';

export interface VideoQualityOption { id:string; label:string; badge?:string; disabled:boolean }
export interface PlaybackQuality { currentId?:string; currentLabel?:string; options:VideoQualityOption[]; width?:number; height?:number }
const text=(element:Element|null)=>element?.textContent?.replace(/\s+/g,' ').trim()||undefined;
function mainPlayer(root:ParentNode){return root instanceof Element&&root.id==='bilibili-player'?root:root.querySelector('#bilibili-player')}
function menu(root:ParentNode){return mainPlayer(root)?.querySelector('.bpx-player-ctrl-quality')}
function entries(root:ParentNode){return [...(menu(root)?.querySelectorAll<HTMLElement>('.bpx-player-ctrl-quality-menu-item[data-value]')??[])]}
function isDisabled(element:HTMLElement){return element.getAttribute('aria-disabled')==='true'||element.hasAttribute('disabled')||element.classList.contains('bpx-state-disabled')}

export function readQuality(root:ParentNode=document):PlaybackQuality {
  const options:VideoQualityOption[]=[];
  let currentId:string|undefined;
  for(const element of entries(root)){
    const id=element.getAttribute('data-value')??'';
    const label=text(element.querySelector('.bpx-player-ctrl-quality-text'));
    if(!/^\d{1,6}$/.test(id)||!label||options.some(option=>option.id===id))continue;
    // A VIP badge describes the tier, not the current account's entitlement.
    options.push({id,label,badge:text(element.querySelector('.bpx-player-ctrl-quality-badge')),disabled:isDisabled(element)});
    if(element.classList.contains('bpx-state-active')||element.getAttribute('aria-selected')==='true')currentId=id;
  }
  const video=mainPlayer(root)?.querySelector<HTMLVideoElement>('.bpx-player-video-wrap video');
  return {currentId,currentLabel:text(menu(root)?.querySelector('.bpx-player-ctrl-quality-result-name')??null)??options.find(option=>option.id===currentId)?.label,
    options,width:video?.videoWidth||undefined,height:video?.videoHeight||undefined};
}

export async function switchQuality(value:unknown,isCurrent:()=>boolean,root:ParentNode=document):Promise<void> {
  if(typeof value!=='string'||!/^\d{1,6}$/.test(value))throw new RemoteError('invalid_request','清晰度选项无效，请重新选择');
  const checkTarget=()=>{if(!isCurrent())throw new RemoteError('target_changed','电脑已切换视频，请重新选择清晰度')};
  checkTarget();
  const option=readQuality(root).options.find(option=>option.id===value);
  const element=entries(root).find(element=>element.getAttribute('data-value')===value);
  if(!option||!element)throw new RemoteError('quality_unavailable','当前视频不提供这个清晰度，请重新选择');
  if(option.disabled)throw new RemoteError('quality_unavailable','这个清晰度目前不可用，请在电脑播放器中检查');
  if(readQuality(root).currentId===value)return;
  // Use the site's own switch: it retains progress and enforces login/VIP access.
  element.click();
  for(let attempt=0;attempt<40;attempt++){
    checkTarget();
    if(readQuality(root).currentId===value)return;
    await new Promise(resolve=>setTimeout(resolve,200));
  }
  checkTarget();
  if(readQuality(root).currentId===value)return;
  throw new RemoteError('quality_not_changed','网页尚未确认切换成功，请在电脑端检查登录、大会员权限或播放器提示后重试');
}
