import {contentId,RemoteError} from './types';

export function playerIdentity(root:ParentNode=document,url:string=location.href):string {
  const id=contentId(url);
  if(!id?.startsWith('ss'))return id??'';
  const active=root.querySelector<HTMLAnchorElement>('a[class*="activeNumber"][href*="/bangumi/play/ep"],a[class*="activeVideo"][href*="/bangumi/play/ep"],.ep-item.on a[href*="/bangumi/play/ep"]');
  return active?contentId(active.href)??'':'';
}
export function playerError(root:ParentNode=document,ended=false):RemoteError|undefined {
  if(ended&&[...root.querySelectorAll('[class*="PromptBar_subtitleText"]')].some(e=>/试看/.test(e.textContent??'')))
    return new RemoteError('access_required','试看已结束，本集需要大会员或购买，请在电脑 B 站网页确认观看权限');
  const message=[...root.querySelectorAll('.error-panel,.bpx-player-error-message,.error-container,.bpx-player-ending-panel,.bpx-player-toast-item,.bpx-player-dialog')]
    .filter(e=>!e.closest('[hidden],[style*="display: none"],[style*="display:none"]'))
    .map(e=>e.textContent?.trim()??'').join(' ');
  if(!message)return undefined;
  if(/试看结束|大会员专享|开通大会员|购买本片|付费观看/.test(message))return new RemoteError('access_required','本集需要大会员或购买，请在电脑 B 站网页确认观看权限');
  if(/地区|区域|版权限制/.test(message))return new RemoteError('region_restricted','本片在当前地区无法播放，请查看电脑网页提示');
  if(/不存在|已删除|失效|不见了|被删除/.test(message))return new RemoteError('video_unavailable',message.slice(0,200));
  if(/登录|验证/.test(message))return new RemoteError('verification_required','请在电脑 B 站网页登录或完成验证后重试');
  if(/失败|错误|出错|异常/.test(message))return new RemoteError('player_error',message.slice(0,200));
  return undefined;
}
export function partInfo(root:ParentNode=document,url:string=location.href):{part:number;partCount:number}{
  if(contentId(url)?.startsWith('ep')||contentId(url)?.startsWith('ss'))return {part:1,partCount:1};
  const current=new URL(url),parsed=Number(current.searchParams.get('p'));
  const part=Number.isInteger(parsed)&&parsed>0?parsed:1;
  const heading=root.querySelector('.video-pod__header,.multi-page .head-con');
  const text=heading?.textContent??'';
  if(text.includes('视频选集')){const match=text.match(/(\d+)\s*\/\s*(\d+)/);if(match)return {part:Number(match[1]),partCount:Math.max(part,Number(match[2]))}}
  const bvid=current.pathname.match(/BV[0-9A-Za-z]+/)?.[0];
  const count=Math.max(part,...[...root.querySelectorAll<HTMLAnchorElement>('a[href*="p="]')].filter(a=>a.href.includes(bvid??'__missing__')).map(a=>Number(new URL(a.href).searchParams.get('p'))||1));
  return {part,partCount:count};
}
export function danmakuControl(root:ParentNode=document):HTMLElement|null {
  return root.querySelector('.bpx-player-dm-switch input,.bilibili-player-video-danmaku-switch input')??root.querySelector('.bpx-player-dm-switch');
}
export function danmakuOn(root:ParentNode=document):boolean {
  const control=danmakuControl(root);return control instanceof HTMLInputElement?control.checked:control?.getAttribute('aria-checked')!=='false'&&!control?.classList.contains('bpx-state-disabled');
}
export function isWebFullscreen(root:ParentNode=document):boolean {
  return root.querySelector('.bpx-player-container')?.getAttribute('data-screen')==='web'||!!root.querySelector('#biliremote-fullscreen');
}
// “自动开播” controls opening a video, not advancing a queue. Never change it.
export function autoNextControl(root:ParentNode=document):HTMLInputElement|null {
  return root.querySelector<HTMLInputElement>('.next-play input[type="checkbox"],.auto-play input[type="checkbox"],.video-pod__auto-play input[type="checkbox"]');
}
export function videoLocation(url:string=location.href):{bvid:string;part:number}{
  const current=new URL(url),part=Number(current.searchParams.get('p'));
  const id=contentId(url)??'';
  return {bvid:id,part:id.startsWith('ep')||id.startsWith('ss')?1:Number.isInteger(part)&&part>0?part:1};
}
